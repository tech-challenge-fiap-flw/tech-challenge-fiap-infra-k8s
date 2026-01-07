# --- Variáveis (Caso não tenha um variables.tf separado) ---
variable "environment" {
  description = "Ambiente (dev, prod, etc)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

# --- Provider e Backend ---
terraform {
  required_version = ">= 1.3.0"
  
  backend "s3" {
    bucket         = "tech-challenge-fiap-terraform-state"
    key            = "tech-challenge-fiap-infra-k8s/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tech-challenge-fiap-terraform-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# --- VPC ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "tc-fiap-vpc-${var.environment}"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/tc-fiap-${var.environment}" = "shared"
    Environment                                        = var.environment
    Name                                               = "tc-fiap-vpc-${var.environment}"
  }
}

# --- Security Group para o Load Balancer (ALB) ---
# Cria um SG separado para o ALB para não expor o Cluster diretamente
resource "aws_security_group" "alb_sg" {
  name        = "tc-fiap-alb-sg"
  description = "Security Group para o ALB"
  vpc_id      = module.vpc.vpc_id

  # Entrada: Permite acesso HTTP na porta 3000 vindo de qualquer lugar (Internet)
  ingress {
    description = "HTTP Ingress"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Saída: Permite o ALB falar com qualquer lugar (necessário para falar com os nós)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tc-fiap-alb-sg"
  }
}

# --- IAM Role for EKS Admin ---
resource "aws_iam_role" "eks_admin" {
  name = "eks-admin-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::790144488941:user/fiap-tech-challenger"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_admin_attach" {
  role       = aws_iam_role.eks_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# --- EKS Cluster ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "tc-fiap-${var.environment}"
  cluster_version = "1.30"

  cluster_endpoint_public_access = true

  cluster_enabled_log_types = []

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  manage_aws_auth_configmap = true

  aws_auth_roles = [
    {
      rolearn  = aws_iam_role.eks_admin.arn
      username = "admin-role"
      groups   = ["system:masters"]
    }
  ]

  aws_auth_users = [
    {
      userarn  = "arn:aws:iam::790144488941:user/fiap-tech-challenger"
      username = "fiap-tech-challenger"
      groups   = ["system:masters"]
    }
  ]

  # Regras adicionais de SG para os Nodes aceitarem tráfego do ALB
  node_security_group_additional_rules = {
    ingress_allow_alb = {
      description                   = "Permitir trafego do ALB na porta 3000"
      protocol                      = "tcp"
      from_port                     = 3000
      to_port                       = 3000
      type                          = "ingress"
      source_security_group_id      = aws_security_group.alb_sg.id
    }
  }

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 2
      desired_size = 1

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
    }
  }

  tags = {
    Environment = var.environment
    Name        = "tc-fiap-${var.environment}"
  }
}

# --- Application Load Balancer (ALB) ---
resource "aws_lb" "eks_lb" {
  name               = "eks-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id] # Usa o SG dedicado criado acima
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  tags = {
    Name        = "eks-load-balancer"
    Environment = var.environment
  }
}

resource "aws_lb_listener" "eks_lb_listener" {
  load_balancer_arn = aws_lb.eks_lb.arn
  port              = 3000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.eks_lb_target_group.arn
  }
}

resource "aws_lb_target_group" "eks_lb_target_group" {
  name        = "eks-target-group"
  port        = 3000 # IMPORTANTE: Isso deve bater com o NodePort do seu Service no Kubernetes
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = {
    Name        = "eks-target-group"
    Environment = var.environment
  }
}

# --- CORREÇÃO: Attachment usando Auto Scaling Group ---
resource "aws_autoscaling_attachment" "eks_asg_attachment" {
  # Itera sobre os ASGs criados pelo Node Group "default"
  for_each = toset(module.eks.eks_managed_node_groups["default"].node_group_autoscaling_group_names)

  autoscaling_group_name = each.value
  lb_target_group_arn    = aws_lb_target_group.eks_lb_target_group.arn
}
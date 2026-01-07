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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
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
  version = "~> 21.0" # Atualizado para uma versão mais recente

  eks_cluster_id     = "tc-fiap-${var.environment}" # Substitui cluster_name
  kubernetes_version = "1.30"                       # Substitui cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true # Substitui manage_aws_auth_configmap

  node_groups_defaults = {
    ami_type       = "AL2_x86_64"
    instance_types = ["t3.medium"]
    desired_size   = 1
    min_size       = 1
    max_size       = 2
    capacity_type  = "ON_DEMAND"
  }

  node_groups = {
    default = {
      desired_size = 1
      min_size     = 1
      max_size     = 2
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
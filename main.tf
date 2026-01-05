module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "tech-challenge-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"] 
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"] 

  enable_nat_gateway = true
  single_nat_gateway = true 
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/tech-challenge-cluster" = "shared"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "tech-challenge-cluster"
  cluster_version = "1.30" 

  cluster_endpoint_public_access  = true 

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  
  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 2
      desired_size = 1 

      instance_types = ["t3.micro"]
      capacity_type  = "ON_DEMAND"
    }
  }

  tags = {
    Environment = "tech-challenge"
  }
}
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.33"

  cluster_endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  vpc_id = module.vpc.vpc_id

  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    bedrock_nodes = {
      desired_size = 6
      min_size     = 2
      max_size     = 8

      instance_types = ["t3.micro"]

      capacity_type = "ON_DEMAND"
    }
  }

  cluster_enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]

  tags = {
    Project = "karatu-2025-capstone"
  }
}
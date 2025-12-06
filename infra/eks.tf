module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_name    = var.cluster_name
  cluster_version = "1.34"

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  eks_managed_node_groups = {
    jenkins = {
      desired_size = 1
      max_size     = 1
      min_size     = 1

      instance_types = [var.jenkins_instance_type]
      labels = { role = "jenkins" }

      pre_bootstrap_user_data = <<-EOF
        #!/bin/bash
        set -e
        curl -LO https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl
        install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
      EOF
    }

    app = {
      desired_size = 1
      max_size     = 1
      min_size     = 1

      instance_types = [var.app_instance_type]
      labels = { role = "app" }

      pre_bootstrap_user_data = <<-EOF
        #!/bin/bash
        set -e
        curl -LO https://dl.k8s.io/release/v1.34.0/bin/linux/amd64/kubectl
        install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
      EOF
    }
  }
  authentication_mode = "API"

  access_entries = {
    mohamed-access = {
      principal_arn = "arn:aws:iam::905418066165:user/mohamed"
      type          = "STANDARD"

      # REQUIRED by module 20.x
      access_scope = {
        type       = "cluster"
        namespaces = []
      }

      policy_associations = {
        adminaccess = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

          # REQUIRED by module 20.x
          access_scope = {
            type       = "cluster"
            namespaces = []
          }
        }
      }
    }
  }


  tags = { Environment = var.environment }
}

output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_certificate_authority_data" { value = module.eks.cluster_certificate_authority_data }
output "cluster_name" { value = module.eks.cluster_name }

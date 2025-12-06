output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region us-east-1"
}


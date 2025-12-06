variable "cluster_name" {
  type    = string
  default = "prod-eks"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "jenkins_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "app_instance_type" {
  type    = string
  default = "t3.medium"
}

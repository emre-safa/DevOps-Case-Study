variable "project" {
  description = "Project name, used as a prefix for all resources."
  type        = string
  default     = "mern-devops"
}

variable "environment" {
  description = "Environment label (dev/stage/prod)."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.30"
}

variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired worker count."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum worker count."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum worker count."
  type        = number
  default     = 4
}

variable "alert_email" {
  description = "Email address that receives CloudWatch alarms via SNS."
  type        = string
  default     = ""
}

output "cluster_name" {
  description = "EKS cluster name (use with `aws eks update-kubeconfig`)."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN — needed when adding IRSA roles outside Terraform."
  value       = module.eks.oidc_provider_arn
}

output "ecr_repository_urls" {
  description = "Map of component → ECR repo URL."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "alb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller."
  value       = module.alb_controller_irsa_role.iam_role_arn
}

output "fluentbit_role_arn" {
  description = "IRSA role ARN for Fluent Bit."
  value       = module.fluentbit_irsa_role.iam_role_arn
}

output "alerts_sns_topic_arn" {
  description = "SNS topic ARN that CloudWatch alarms publish to."
  value       = aws_sns_topic.alerts.arn
}

output "kubeconfig_command" {
  description = "Convenience: command to update local kubeconfig."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "github_deploy_role_arn" {
  description = "Set this as the AWS_DEPLOY_ROLE_ARN secret in the GitHub repo."
  value       = aws_iam_role.github_deploy.arn
}

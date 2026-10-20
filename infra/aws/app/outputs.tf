output "app_url" {
  value       = "http://${aws_lb.app.dns_name}"
  description = "Public URL of CloudPose (via the load balancer)"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "service_name" {
  value = aws_ecs_service.app.name
}

output "log_group" {
  value = aws_cloudwatch_log_group.app.name
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${var.app_name}"
}

# Paste into GitHub: repo Settings -> Secrets and variables -> Actions -> Variables -> AWS_ROLE_ARN
output "cd_role_arn" {
  value = local.cd_oidc ? aws_iam_role.github_deploy[0].arn : ""
}

# Only with cd_auth = "iam_user": the user to create an access key for
output "cd_user_name" {
  value = local.cd_user ? aws_iam_user.github_deploy[0].name : ""
}

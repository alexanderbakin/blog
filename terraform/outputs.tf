output "cloudfront_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.blog.domain_name
}

output "cloudfront_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.blog.id
}

output "s3_bucket" {
  description = "S3 bucket name for the blog"
  value       = aws_s3_bucket.blog.id
}

output "logs_bucket" {
  description = "S3 bucket name for access logs"
  value       = aws_s3_bucket.logs.id
}

output "nameservers" {
  description = "Route53 nameservers (point your domain registrar here)"
  value       = var.create_route53_zone ? aws_route53_zone.blog[0].name_servers : null
}

output "terraform_role_arn" {
  description = "ARN of the IAM role for Terraform (infra pipeline)"
  value       = var.create_github_actions_role ? aws_iam_role.terraform[0].arn : null
}

output "deploy_role_arn" {
  description = "ARN of the IAM role for content deploys"
  value       = var.create_github_actions_role ? aws_iam_role.deploy[0].arn : null
}

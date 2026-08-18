variable "aws_region" {
  description = "AWS region for primary resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, prod)"
  type        = string
  default     = "prod"
}

variable "domain_name" {
  description = "Primary domain name for the blog (e.g. example.com)"
  type        = string
  default     = ""
}

variable "domain_aliases" {
  description = "Additional domain aliases (e.g. www.example.com)"
  type        = list(string)
  default     = []
}

variable "create_route53_zone" {
  description = "Whether to create a new Route53 hosted zone"
  type        = bool
  default     = false
}

variable "acm_certificate_arn" {
  description = "ARN of an existing ACM certificate (if pre-issued)"
  type        = string
  default     = null
}

variable "price_class" {
  description = "CloudFront price class (PriceClass_100, PriceClass_200, PriceClass_All)"
  type        = string
  default     = "PriceClass_100"
}

variable "default_root_object" {
  description = "Default root object for CloudFront"
  type        = string
  default     = "index.html"
}

variable "error_document" {
  description = "Custom error document key in S3"
  type        = string
  default     = "404.html"
}

variable "allowed_countries" {
  description = "List of country codes to allow (empty = all)"
  type        = list(string)
  default     = []
}

variable "monthly_budget" {
  description = "Monthly budget limit in USD for AWS cost alerts"
  type        = number
  default     = 10
}

variable "alert_email" {
  description = "Email address for budget and alarm notifications (e.g. admin@example.com)"
  type        = string
  default     = null
}

variable "create_github_actions_role" {
  description = "Whether to create IAM roles for GitHub Actions (terraform + deploy)"
  type        = bool
  default     = false
}

variable "github_repo" {
  description = "GitHub repository in format 'owner/repo' (required if create_github_actions_role is true)"
  type        = string
  default     = ""
}

variable "github_repo_id_format" {
  description = "GitHub repository in numeric-ID format 'owner@OWNERID/repo@REPOID'. GitHub's OIDC sub claim now uses immutable numeric IDs instead of names (e.g. 'repo:alexanderbakin@242987075/blog@1338101538:ref:refs/heads/main')"
  type        = string
  default     = ""
}

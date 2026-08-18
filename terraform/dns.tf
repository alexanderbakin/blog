# Provider configuration
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Personal Blog"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# us-east-1 provider for ACM (required by CloudFront, must be in us-east-1)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "Personal Blog"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Shared locals
locals {
  domain_slug = replace(var.domain_name, ".", "-")
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Route53 DNS
resource "aws_route53_zone" "blog" {
  count = var.create_route53_zone ? 1 : 0

  name = var.domain_name

  tags = {
    Name = var.domain_name
  }
}

data "aws_route53_zone" "blog" {
  count = var.create_route53_zone ? 0 : 1

  name         = var.domain_name
  private_zone = false
}

locals {
  zone_id = var.create_route53_zone ? aws_route53_zone.blog[0].zone_id : data.aws_route53_zone.blog[0].zone_id
}

# ACM DNS validation records
resource "aws_route53_record" "cert_validation" {
  for_each = var.acm_certificate_arn == null ? {
    for dvo in aws_acm_certificate.blog[0].domain_validation_options : dvo.domain_name => dvo
  } : {}

  zone_id = local.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60
}

# Alias A record (root domain -> CloudFront distribution)
resource "aws_route53_record" "blog_a" {
  zone_id = local.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.blog.domain_name
    zone_id                = aws_cloudfront_distribution.blog.hosted_zone_id
    evaluate_target_health = false
  }
}

# Alias AAAA record
resource "aws_route53_record" "blog_aaaa" {
  zone_id = local.zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.blog.domain_name
    zone_id                = aws_cloudfront_distribution.blog.hosted_zone_id
    evaluate_target_health = false
  }
}

# Alias A records for domain aliases (e.g. www)
resource "aws_route53_record" "alias_a" {
  for_each = toset(var.domain_aliases)

  zone_id = local.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.blog.domain_name
    zone_id                = aws_cloudfront_distribution.blog.hosted_zone_id
    evaluate_target_health = false
  }
}

# Alias AAAA records for domain aliases (e.g. www)
resource "aws_route53_record" "alias_aaaa" {
  for_each = toset(var.domain_aliases)

  zone_id = local.zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.blog.domain_name
    zone_id                = aws_cloudfront_distribution.blog.hosted_zone_id
    evaluate_target_health = false
  }
}

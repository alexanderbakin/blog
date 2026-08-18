# ACM Certificate (must be in us-east-1 for CloudFront)
resource "aws_acm_certificate" "blog" {
  count = var.acm_certificate_arn == null ? 1 : 0

  provider                  = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = var.domain_aliases
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Validation records are created in dns.tf via aws_route53_record.cert_validation
# This resource waits for the certificate to be issued.
resource "aws_acm_certificate_validation" "blog" {
  count = var.acm_certificate_arn == null ? 1 : 0

  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.blog[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

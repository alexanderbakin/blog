# CloudFront Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "blog" {
  name                              = "${var.domain_name}-oac"
  description                       = "OAC for ${var.domain_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "blog" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = var.default_root_object
  price_class         = var.price_class
  aliases             = concat([var.domain_name], var.domain_aliases)

  # S3 origin (OAC handles auth — no custom_origin_config needed for S3)
  origin {
    domain_name              = aws_s3_bucket.blog.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.blog.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.blog.id
  }

  # Default cache behavior
  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.blog.id}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD", "OPTIONS"]

    cache_policy_id            = aws_cloudfront_cache_policy.blog.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.blog.id

    # Rewrite /about → /about/index.html etc.
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite_index.arn
    }
  }

  # Custom error responses
  # 403 → 404: OAC-denied requests (wrong Origin header, direct bucket access)
  # appear as 404 to avoid leaking information about whether a resource exists.
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/${var.error_document}"
    error_caching_min_ttl = 300
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/${var.error_document}"
    error_caching_min_ttl = 300
  }

  # Access logs — writes to the dedicated logs bucket
  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    prefix          = "cloudfront/"
  }

  # SSL
  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn != null ? var.acm_certificate_arn : aws_acm_certificate.blog[0].arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # Restrictions
  restrictions {
    geo_restriction {
      restriction_type = length(var.allowed_countries) > 0 ? "whitelist" : "none"
      locations        = length(var.allowed_countries) > 0 ? var.allowed_countries : []
    }
  }

  tags = {
    Name = "${var.domain_name}-distribution"
  }

  lifecycle {
    # Prevent accidental deletion of the distribution
    prevent_destroy = true
  }
}

# CloudFront Function — rewrites directory paths to /index.html
resource "aws_cloudfront_function" "rewrite_index" {
  name    = replace(var.domain_name, ".", "-")
  comment = "Rewrite /about → /about/index.html for S3 REST origin"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/cloudfront-function.js")
}

# Cache policy - aggressive caching for static assets
resource "aws_cloudfront_cache_policy" "blog" {
  name        = "${local.domain_slug}-cache-policy"
  comment     = "Cache policy for ${var.domain_name}"
  default_ttl = 3600
  max_ttl     = 86400
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

# Response headers policy – security headers
resource "aws_cloudfront_response_headers_policy" "blog" {
  name    = "${local.domain_slug}-security-headers"
  comment = "Security headers for ${var.domain_name}"

  security_headers_config {
    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = false
      override                   = true
    }

    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }

    content_security_policy {
      content_security_policy = "default-src 'self'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; frame-ancestors 'none';"
      override                = true
    }
  }
}

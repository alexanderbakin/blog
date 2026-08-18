# TLS Certificate for GitHub Actions OIDC
data "tls_certificate" "github_oidc" {
  count = var.create_github_actions_role ? 1 : 0

  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# GitHub OIDC Connect Provider
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_actions_role ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  # Include all certificates in the chain so thumbprint survives rotations
  thumbprint_list = [for c in data.tls_certificate.github_oidc[0].certificates : c.sha1_fingerprint]
}

# ─────────────────────────────────────────────────────────────────────
# Terraform role — used by infra.yml (terraform plan/apply)
# Needs broad permissions to manage all AWS infrastructure resources.
# ─────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "terraform_assume" {
  count = var.create_github_actions_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "terraform" {
  count = var.create_github_actions_role ? 1 : 0

  name               = "${local.domain_slug}-terraform"
  assume_role_policy = data.aws_iam_policy_document.terraform_assume[0].json

  tags = {
    Name = "Terraform-${var.domain_name}"
  }
}

# Terraform role policy — full infrastructure management
data "aws_iam_policy_document" "terraform_infra" {
  count = var.create_github_actions_role ? 1 : 0

  # S3 state bucket access
  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      # State bucket — requires the actual bucket name which is known at apply time
      "arn:${data.aws_partition.current.partition}:s3:::blog-terraform-state-${data.aws_caller_identity.current.account_id}-us-east-1-an",
      "arn:${data.aws_partition.current.partition}:s3:::blog-terraform-state-${data.aws_caller_identity.current.account_id}-us-east-1-an/*",
    ]
  }

  # Full S3 management on the blog bucket
  statement {
    actions = [
      "s3:*",
    ]
    resources = [
      aws_s3_bucket.blog.arn,
      "${aws_s3_bucket.blog.arn}/*",
    ]
  }

  # CloudFront management
  statement {
    actions = [
      "cloudfront:*",
    ]
    resources = ["*"]
  }

  # ACM management
  statement {
    actions = [
      "acm:DescribeCertificate",
      "acm:RequestCertificate",
      "acm:DeleteCertificate",
      "acm:ListCertificates",
      "acm:ListTagsForCertificate",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
    ]
    resources = ["*"]
  }

  # Route53 management
  statement {
    actions = [
      "route53:*",
    ]
    resources = ["*"]
  }

  # IAM management
  statement {
    actions = [
      "iam:*",
    ]
    resources = ["*"]
  }

  # SNS management
  statement {
    actions = [
      "sns:*",
    ]
    resources = ["*"]
  }

  # CloudWatch management
  statement {
    actions = [
      "cloudwatch:*",
      "logs:*",
    ]
    resources = ["*"]
  }

  # Budgets management
  statement {
    actions = [
      "budgets:*",
    ]
    resources = ["*"]
  }

  # S3 logs bucket management
  statement {
    actions = [
      "s3:*",
    ]
    resources = [
      aws_s3_bucket.logs.arn,
      "${aws_s3_bucket.logs.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "terraform_infra" {
  count = var.create_github_actions_role ? 1 : 0

  role   = aws_iam_role.terraform[0].id
  policy = data.aws_iam_policy_document.terraform_infra[0].json
}

# ─────────────────────────────────────────────────────────────────────
# Deploy role — used by deploy-content.yml (hugo build → s3 sync → cf invalidation)
# Narrow permissions: S3 object CRUD + CloudFront invalidation only.
# ─────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "deploy_assume" {
  count = var.create_github_actions_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  count = var.create_github_actions_role ? 1 : 0

  name               = "${local.domain_slug}-deploy"
  assume_role_policy = data.aws_iam_policy_document.deploy_assume[0].json

  tags = {
    Name = "Deploy-${var.domain_name}"
  }
}

# Deploy role policy: S3 object CRUD + CloudFront invalidation
data "aws_iam_policy_document" "deploy_s3" {
  count = var.create_github_actions_role ? 1 : 0

  statement {
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.blog.arn,
      "${aws_s3_bucket.blog.arn}/*",
    ]
  }

  statement {
    actions   = ["s3:GetBucketLocation"]
    resources = [aws_s3_bucket.blog.arn]
  }

  # Allow creating invalidation after deployment
  statement {
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.blog.arn]
  }
}

resource "aws_iam_role_policy" "deploy_s3" {
  count = var.create_github_actions_role ? 1 : 0

  role   = aws_iam_role.deploy[0].id
  policy = data.aws_iam_policy_document.deploy_s3[0].json
}

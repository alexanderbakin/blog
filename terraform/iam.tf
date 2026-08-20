# TLS Certificate for GitHub Actions OIDC
data "tls_certificate" "github_oidc" {
  count = var.create_github_actions_role ? 1 : 0

  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# GitHub OIDC Connect Provider
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_actions_role ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
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
      # GitHub migrated sub claims from "owner/repo" to numeric-ID form
      # "owner@USERID/repo@REPOID". Allow both formats during transition.
      # See: https://github.blog/changelog/2026-08-10-github-actions-oidc-subject-claim-format-change/
      # compact() drops any pattern whose variable is unset, so an empty
      # variable can never widen the match to "repo::*" (all repos).
      values = compact([
        "repo:${var.github_repo}:*",
        var.github_repo_id_format != "" ? "repo:${var.github_repo_id_format}:*" : "",
      ])
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

  # CloudFront management — scoped to the actions the managed resources
  # (distribution, OAC, function, cache policy, response headers policy)
  # actually use. CloudFront doesn't support resource-level ARNs for most
  # of these (create actions target a not-yet-existing resource), so the
  # resource stays "*"; the action list is what keeps this from being a
  # blanket grant over unrelated CloudFront features (key groups, field-level
  # encryption, real-time logs, streaming distributions, etc).
  statement {
    actions = [
      "cloudfront:CreateDistribution",
      "cloudfront:CreateDistributionWithTags",
      "cloudfront:GetDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:ListDistributions",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
      "cloudfront:ListTagsForResource",
      "cloudfront:CreateOriginAccessControl",
      "cloudfront:GetOriginAccessControl",
      "cloudfront:GetOriginAccessControlConfig",
      "cloudfront:UpdateOriginAccessControl",
      "cloudfront:DeleteOriginAccessControl",
      "cloudfront:ListOriginAccessControls",
      "cloudfront:CreateFunction",
      "cloudfront:GetFunction",
      "cloudfront:DescribeFunction",
      "cloudfront:UpdateFunction",
      "cloudfront:DeleteFunction",
      "cloudfront:PublishFunction",
      "cloudfront:ListFunctions",
      "cloudfront:CreateCachePolicy",
      "cloudfront:GetCachePolicy",
      "cloudfront:GetCachePolicyConfig",
      "cloudfront:UpdateCachePolicy",
      "cloudfront:DeleteCachePolicy",
      "cloudfront:ListCachePolicies",
      "cloudfront:CreateResponseHeadersPolicy",
      "cloudfront:GetResponseHeadersPolicy",
      "cloudfront:GetResponseHeadersPolicyConfig",
      "cloudfront:UpdateResponseHeadersPolicy",
      "cloudfront:DeleteResponseHeadersPolicy",
      "cloudfront:ListResponseHeadersPolicies",
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

  # Route53 management — the zone/change IDs aren't known ahead of creation,
  # so the resource stays wildcarded within the hostedzone/change namespaces,
  # but scoping the resource type still keeps this role off Resolver, health
  # checks, traffic policies, and query logging.
  statement {
    actions = [
      "route53:CreateHostedZone",
      "route53:GetHostedZone",
      "route53:DeleteHostedZone",
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
      "route53:ChangeTagsForResource",
      "route53:ListTagsForResource",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:route53:::hostedzone/*",
    ]
  }

  statement {
    actions   = ["route53:GetChange"]
    resources = ["arn:${data.aws_partition.current.partition}:route53:::change/*"]
  }

  # IAM management — scoped to only the two roles and the OIDC provider this
  # config manages. Deliberately NOT "iam:*" on "*": that would let this role
  # grant itself AdministratorAccess or create a backdoor IAM user, turning a
  # compromised PR/provider into a full account takeover.
  statement {
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.domain_slug}-terraform",
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.domain_slug}-deploy",
    ]
  }

  statement {
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com",
    ]
  }

  # SNS management — scoped to the one alerts topic this config creates.
  # Subscribe/TagResource/etc. take the topic ARN, but Unsubscribe and
  # GetSubscriptionAttributes act on the *subscription* ARN, which has an
  # unpredictable ID suffix (topic-arn:uuid) — so that needs its own
  # statement with a trailing wildcard rather than the exact topic ARN.
  statement {
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:Subscribe",
      "sns:ListSubscriptionsByTopic",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${local.domain_slug}-alerts",
    ]
  }

  # Unlike topic-level actions above, SNS subscription actions don't support
  # resource-level scoping in identity-based policies — confirmed via
  # simulate-custom-policy and a live apply, both denying a scoped
  # "topic-arn:*" (and even an explicit "*") resource once --resource-arns
  # was the actual subscription ARN. AWS requires Resource = "*" here.
  statement {
    actions = [
      "sns:GetSubscriptionAttributes",
      "sns:SetSubscriptionAttributes",
      "sns:Unsubscribe",
    ]
    resources = ["*"]
  }

  # CloudWatch management — scoped to the one dashboard and one alarm this
  # config creates. (No CloudWatch Logs resources exist anywhere in this
  # config — CloudFront access logs go to S3 — so no "logs:*" is needed.)
  statement {
    actions = [
      "cloudwatch:PutDashboard",
      "cloudwatch:GetDashboard",
      "cloudwatch:DeleteDashboards",
      "cloudwatch:ListDashboards",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
      "cloudwatch:ListTagsForResource",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:cloudwatch::${data.aws_caller_identity.current.account_id}:dashboard/${local.domain_slug}-dashboard",
      "arn:${data.aws_partition.current.partition}:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${var.domain_name}-high-error-rate",
    ]
  }

  # Budgets management — scoped to the one budget this config creates.
  # TagResource/UntagResource/ListTagsForResource are required because the
  # provider's default_tags applies tags to the budget on create/update.
  statement {
    actions = [
      "budgets:ViewBudget",
      "budgets:ModifyBudget",
      "budgets:TagResource",
      "budgets:UntagResource",
      "budgets:ListTagsForResource",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:budgets::${data.aws_caller_identity.current.account_id}:budget/${local.domain_slug}-monthly-budget",
    ]
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
      # GitHub migrated sub claims from "owner/repo" to numeric-ID form
      # "owner@USERID/repo@REPOID". Allow both formats during transition.
      # See: https://github.blog/changelog/2026-08-10-github-actions-oidc-subject-claim-format-change/
      # compact() drops any pattern whose variable is unset, so an empty
      # variable can never widen the match to "repo::*" (all repos).
      values = compact([
        "repo:${var.github_repo}:*",
        var.github_repo_id_format != "" ? "repo:${var.github_repo_id_format}:*" : "",
      ])
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

# Personal Blog — Production-Grade AWS Infrastructure

A personal blog built with **Hugo**, deployed via **GitHub Actions**, and hosted on **AWS CloudFront + S3** — all managed with **Terraform**.

This is a fully-production-ready setup designed to showcase DevOps best practices on a CV/resume.

---

## Architecture

```
User → Route53 → CloudFront (HTTPS) → S3 (private, OAC only)
                                      ↓
                              CloudWatch Alarms + Budget Alert
```

> **Architecture diagram:** `hugo-site/static/images/architecture-diagram.svg` - also viewable in the architecture blog post at `/meta/`.

## Features

| Capability | Implementation |
|---|---|
| **Static Site** | Hugo SSG from Markdown |
| **CI/CD** | GitHub Actions with OIDC (no AWS keys) |
| **State Mgmt** | S3 backend remote state (industry standard) |
| **Infra Pipeline** | PR plan → merge apply (never from local) |
| **Content Pipeline** | Separate deploy role (least-privilege) for hugo build → S3 sync → CloudFront invalidation |
| **Origin** | S3 bucket (fully private, versioned, encrypted) |
| **CDN** | CloudFront (HTTP→HTTPS, Brotli/Gzip, security headers, geo-restriction) |
| **TLS** | ACM certificate (auto-renewal, TLSv1.2_2021) |
| **DNS** | Route 53 alias records (A + AAAA, root + www) |
| **Cost Control** | AWS Budgets alert (direct email when spending exceeds threshold) |
| **Observability** | CloudWatch dashboard + error rate alarm |
| **Performance** | CloudFront edge caching with Brotli/Gzip compression, tiered cache headers |
| **IAM** | Two OIDC roles: terraform role (broad infra management) + deploy role (S3 CRUD + CloudFront invalidation only) |

## Prerequisites

- [Hugo extended](https://gohugo.io/installation/) (local dev)
- [Terraform](https://developer.hashicorp.com/terraform/downloads) ≥ 1.5
- [AWS CLI](https://aws.amazon.com/cli/) (configured)
- [GitHub CLI](https://cli.github.com/) (for setting pipeline variables)
- A domain name (registered in Route 53 or externally)

## Getting Started

### 1. Configure Hugo

Before deploying, update `hugo-site/config.yaml` with your actual domain, author name, and social links.
Replace all placeholders (`yourdomain.com`, `your-username`, `your-profile`, `your-handle`, `your-blog-repo`):

```yaml
baseURL: "https://yourdomain.com/"
params:
  author: "Your Name"
  github: "https://github.com/your-username"
  linkedin: "https://linkedin.com/in/your-profile"
  twitter: "https://twitter.com/your-handle"
  repo: "https://github.com/your-username/your-blog-repo"
```

If these are not updated, your deployed site will have broken canonical URLs, RSS feeds, and sitemaps.

### 2. Local Dev

```bash
# Install Hugo theme (PaperMod)
git submodule update --init --recursive

# Start dev server (live reload at http://localhost:1313) — run from project root
./dev.sh

# Create a new post — run from project root
./new-post.sh "My Awesome Post"
```

### 3. First-Time Infrastructure Deploy

> This is the **only** time you run `terraform apply` from your machine.
> After this, all infrastructure changes go through the CI/CD pipeline.
> The pipeline needs the CloudFront distribution ID and IAM role ARN —
> values that only exist after Terraform creates them.

```bash
# ── 3a. Create the S3 state bucket ──
./bootstrap.sh

# ── 3b. Deploy everything ──
cd terraform
terraform init
terraform apply -var="domain_name=alexanderbakin.com" -var="create_route53_zone=true" -var="create_github_actions_role=true" -var="github_repo=alexanderbakin/blog" -var="alert_email=admin@alexanderbakin.com"
```

> **Important:** The first `apply` must set `create_github_actions_role=true` so the
> IAM roles that the CI/CD pipeline needs are created. Without this flag, the
> role ARN outputs will be `null` and the pipeline won't work.

Terraform will create: S3 bucket, CloudFront distribution, ACM certificate,
Route 53 zone and records, IAM roles (terraform + deploy), CloudWatch dashboard + alarm,
SNS topic, logs bucket, and a monthly budget alert.

After it completes, note the outputs:

```bash
terraform output
```

### 4. Wire Up CI/CD Pipeline

After `terraform apply` completes, grab the outputs and configure GitHub.
Values are split into two categories:

| Type | Visibility | Used for |
|------|-----------|----------|
| **Variable** | Visible in workflow logs | Non-sensitive config (domain, URLs) |
| **Secret** | Masked in logs | Credentials, account IDs, role ARNs |

```bash
cd terraform
terraform output

# Example output:
#   cloudfront_id        = "E123456789ABC"
#   terraform_role_arn   = "arn:aws:iam::123456789012:role/alexanderbakin-com-terraform"
#   deploy_role_arn      = "arn:aws:iam::123456789012:role/alexanderbakin-com-deploy"
#   nameservers          = ["ns-xxx.awsdns-xx.com", ...]
```

Set GitHub **variables** (visible in workflow logs — safe because these values
are public information once the site is live):

```bash
gh variable set DOMAIN_NAME --body "alexanderbakin.com" --repo alexanderbakin/blog
gh variable set S3_BUCKET --body "alexanderbakin.com" --repo alexanderbakin/blog
gh variable set CLOUDFRONT_DISTRIBUTION_ID --body "E123456789ABC" --repo alexanderbakin/blog
gh variable set SITE_URL --body "https://alexanderbakin.com" --repo alexanderbakin/blog
```

Set GitHub **secrets** (masked in workflow logs — these grant access to your
AWS account):

```bash
gh secret set AWS_ACCOUNT_ID --body "796761619073" --repo alexanderbakin/blog
gh secret set AWS_TERRAFORM_ROLE_ARN --body "arn:aws:iam::796761619073:role/alexanderbakin-com-terraform" --repo alexanderbakin/blog
gh secret set AWS_DEPLOY_ROLE_ARN --body "arn:aws:iam::796761619073:role/alexanderbakin-com-deploy" --repo alexanderbakin/blog
```

> **Why two roles?** The terraform role has broad permissions to manage all
> infrastructure (IAM, ACM, Route53, CloudWatch...). The deploy role has
> narrow permissions — only S3 object CRUD + CloudFront `CreateInvalidation`.
> This follows least-privilege best practices: if the content pipeline is
> compromised, an attacker can only update blog files, not modify infrastructure.

> **Why this is necessary**: The workflows reference these values via
> `${{ vars.* }}` and `${{ secrets.* }}`. They can't exist until Terraform
> creates the resources. After this one-time setup, you never need to touch
> them again.

### 5. Validate ACM Certificate

The ACM certificate requests DNS validation records. Terraform creates these records
in Route 53 automatically, but your domain must resolve to Route 53 first.

**If your domain registrar points to Route 53 nameservers:**
- Certificate validates automatically once DNS propagates (up to 48 hours)
- Run `terraform apply -target=aws_acm_certificate_validation.blog` to check

**If you're applying in stages (like us):**
The certificate is created in `PENDING_VALIDATION` state first. The validation
records exist in Route 53 but your domain doesn't resolve there yet. You have
three options:

1. **Wait for DNS propagation** — update nameservers at your registrar, then the
   certificate auto-validates within hours.
2. **Use email validation** — request an email validation instead of DNS (manual).
3. **Create the validation records manually** at your current DNS provider
   while waiting for nameservers to propagate.

The CloudFront distribution can reference the certificate while it's in
`PENDING_VALIDATION` but the site won't serve HTTPS until validation completes.

### 6. Configure DNS at Your Registrar

Route 53 nameservers are created via Terraform, but your domain registrar
(Namecheap, GoDaddy, etc.) needs to point to them:

1. Note the `nameservers` from `terraform output`
2. Log into your registrar's control panel
3. Replace your domain's nameservers with the Route 53 values
4. Propagation can take 24-48 hours — ACM certificate validation completes
   automatically once the DNS changes propagate

### 7. Enable CloudWatch Billing Metrics (One-Time Manual Step)

The `EstimatedCharges` CloudWatch dashboard widget requires billing metrics to be enabled.
This is a one-time manual step Terraform cannot automate:

1. Go to **AWS Console → Billing → Billing preferences**
2. Check **"Receive CloudWatch billing alerts"**
3. Save

The AWS Budgets alert works independently — it emails you directly without needing this opt-in.

### 8. Push to GitHub

```bash
git add .
git commit -m "initial commit: blog infrastructure + content"
git remote add origin git@github.com:alexanderbakin/blog.git
git push -u origin main
```

### 9. Normal Workflow (Pipeline-Only)

From this point forward, `terraform apply` never runs locally.

## Why No WAF?

This project intentionally does **not** include a WAF web ACL. For a static site served
through CloudFront:

- **OWASP managed rules protect nothing** — SQLi needs a database, command injection
  needs a shell, stored XSS needs a backend. Against a bucket of HTML these are
  security theater.
- **AWS Shield Standard** is automatic and free on CloudFront, absorbing L3/L4
  volumetric attacks at the edge.
- **The origin is unreachable directly** — the bucket policy allows only the
  CloudFront distribution, so nobody can bypass the CDN to run up S3 costs.

The residual risk is an L7 GET flood that runs up the CloudFront bill (denial-of-wallet).
WAF rate rules are per-IP, so a distributed botnet stays under each IP's threshold.
The cost comparison:

| Approach | Fixed cost | What it stops |
|---|---|---|
| WAF | ~$11/mo always | Single-IP floods only; OWASP rules stop nothing |
| Budget alert | Free | Nothing — but bounds loss to ~1 day of flood spend |

Budget alerts are free and provide the
same practical protection against bill shock. This decision record — evaluating the
actual threat model and choosing billing alerts over WAF — demonstrates stronger
cloud engineering judgment than blindly adding WAF because a tutorial had it.

## Project Structure

```
.
├── .github/workflows/
│   ├── infra.yml                  # Terraform: PR plan → merge apply
│   └── deploy-content.yml         # Content: build Hugo → sync S3 → invalidate
├── hugo-site/                      # Hugo blog source
│   ├── config.yaml                 # Blog configuration
│   ├── content/                    # Markdown posts
│   │   ├── _index.md               # Homepage
│   │   ├── about.md                # About page
│   │   └── posts/                  # Blog posts
│   ├── static/                     # Static assets
│   │   └── images/                  # Images and diagrams
│   │       └── architecture.mmd     # Architecture diagram (Mermaid)
├── terraform/                      # Infrastructure as Code
│   ├── main.tf.template            # Backend config template (generates main.tf)
│   ├── variables.tf                # All variables
│   ├── dns.tf                      # Provider config + locals + Route 53 records
│   ├── s3.tf                       # S3 bucket (origin)
│   ├── cloudfront.tf              # CloudFront distribution
│   ├── acm.tf                      # SSL/TLS certificate
│   ├── logs.tf                     # Access logs
│   ├── iam.tf                      # GitHub Actions OIDC roles (terraform + deploy)
│   ├── monitoring.tf               # Dashboard + alarms + SNS + budget alert
│   └── outputs.tf                  # Terraform outputs
├── dev.sh                          # Local dev server
├── new-post.sh                     # New post helper
├── bootstrap.sh                    # Bootstrap S3 state bucket
└── README.md                       # This file
```

## LinkedIn / CV Talking Points

> **"Built a production-grade personal blog with 100% serverless architecture on AWS."**

- **Infrastructure as Code**: Entire AWS stack defined in Terraform (9 modules, 350+ lines HCL)
- **State Management**: S3 backend remote state (industry standard, not local)
- **GitOps-style Pipeline**: Two GitHub Actions workflows — `infra.yml` runs `terraform plan` on PRs and `apply` on merge; `deploy-content.yml` handles content deploys with a separate least-privilege IAM role
- **Zero-trust security**: S3 bucket fully private, CloudFront OAC only, no static credentials
- **Passwordless CI/CD**: GitHub Actions assumes IAM roles via OIDC (no AWS keys stored anywhere)
- **Security Headers**: HSTS (2 year), CSP, X-Frame-Options, X-Content-Type-Options applied at CloudFront edge
- **Cost-effective**: ~$0–2/month at low traffic (no WAF, minimal S3+CloudFront usage)
- **Cost Control**: AWS Budgets alert sends email when monthly spending exceeds a configurable threshold
- **Observability**: CloudWatch dashboard + error rate alarm
- **Security Decision Record**: Evaluated WAF vs. billing alerts for a CloudFront+S3 static origin; chose billing alerts based on threat-model analysis

## License

MIT

# CloudWatch dashboard - operational overview
resource "aws_cloudwatch_dashboard" "blog" {
  dashboard_name = "${local.domain_slug}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/CloudFront", "Requests", { stat = "Sum" }],
          ]
          period = 300
          stat   = "Sum"
          region = "us-east-1"
          title  = "CloudFront Requests"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/CloudFront", "TotalErrorRate", { stat = "Average" }],
          ]
          period = 300
          stat   = "Average"
          region = "us-east-1"
          title  = "CloudFront Error Rate"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD", { stat = "Maximum" }],
          ]
          period = 21600
          stat   = "Maximum"
          region = "us-east-1"
          title  = "Estimated Charges"
        }
      },
    ]
  })
}

# SNS topic for CloudWatch alarms
resource "aws_sns_topic" "alerts" {
  name = "${local.domain_slug}-alerts"
}

# SNS email subscription
resource "aws_sns_topic_subscription" "email" {
  count     = local.alert_email != null ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = local.alert_email
}

# CloudWatch alarm - high error rate
resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name          = "${var.domain_name}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 5
  alarm_description   = "5xx error rate > 5% for ${var.domain_name}"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DistributionId = aws_cloudfront_distribution.blog.id
  }
}

# Budget alarm — first 2 budgets are free. Emails directly (no SNS dependency).
# Budgets work without the "Receive Billing Alerts" CloudWatch opt-in.
resource "aws_budgets_budget" "monthly" {
  count = local.alert_email != null ? 1 : 0

  name         = "${local.domain_slug}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [local.alert_email]
  }
}

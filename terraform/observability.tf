# CloudWatch log groups that Fluent Bit ships container logs into.
# Created up-front so retention is enforced from day one.
resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/eks/${local.name}-eks/application"
  retention_in_days = 30
  tags              = local.tags
}

resource "aws_cloudwatch_log_group" "platform" {
  name              = "/aws/eks/${local.name}-eks/platform"
  retention_in_days = 30
  tags              = local.tags
}

resource "aws_cloudwatch_log_group" "host" {
  name              = "/aws/eks/${local.name}-eks/host"
  retention_in_days = 30
  tags              = local.tags
}

# SNS topic + (optional) email subscription. CloudWatch alarms publish here.
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
  tags = local.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Alarm: Fluent Bit emits a metric "backend_5xx_total" via the metric
# filter below; if backend 5xx errors exceed 5/min, page the SNS topic.
resource "aws_cloudwatch_log_metric_filter" "backend_5xx" {
  name           = "${local.name}-backend-5xx"
  log_group_name = aws_cloudwatch_log_group.application.name

  # Backend logs are JSON (kubernetes metadata + raw container line).
  # We match any 5xx status the Express access log emits using a clean regex.
  pattern = "{ $.kubernetes.container_name = \"backend\" && $.log = % 5[0-9]{2} % }"

  metric_transformation {
    name          = "BackendHttp5xx"
    namespace     = "MERN/Backend"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "backend_5xx" {
  alarm_name          = "${local.name}-backend-5xx"
  alarm_description   = "Backend is returning HTTP 5xx (>5 in 5 min)."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BackendHttp5xx"
  namespace           = "MERN/Backend"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = local.tags
}

# Alarm: any node CPU above 80% for 10 minutes.
resource "aws_cloudwatch_metric_alarm" "node_cpu_high" {
  alarm_name          = "${local.name}-node-cpu-high"
  alarm_description   = "EKS worker node CPU > 80% for 10 minutes."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = module.eks.cluster_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = local.tags
}

# SNS topic = where alarms send their message; email subscription is optional.
resource "aws_sns_topic" "alerts" {
  name = "${var.app_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # AWS emails a confirmation link; click it
}

locals {
  alb_dims = { LoadBalancer = aws_lb.app.arn_suffix }
  tg_dims  = { LoadBalancer = aws_lb.app.arn_suffix, TargetGroup = aws_lb_target_group.app.arn_suffix }
  ecs_dims = { ClusterName = aws_ecs_cluster.main.name, ServiceName = aws_ecs_service.app.name }
}

# The same golden signals as Track A, using CloudWatch metrics AWS collects for free.

# ERRORS: the app answered with 5xx
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.app_name}-target-5xx"
  alarm_description   = "More than 5 server errors per minute for 2 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = local.alb_dims
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# AVAILABILITY: a task is failing the /health check
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.app_name}-unhealthy-targets"
  alarm_description   = "At least one task failing health checks for 2 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = local.tg_dims
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# LATENCY: slowest 5% of requests over 2 seconds
resource "aws_cloudwatch_metric_alarm" "p95_latency" {
  alarm_name          = "${var.app_name}-p95-latency"
  alarm_description   = "p95 response time above 2 s for 3 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.alb_dims
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 3
  threshold           = 2
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# SATURATION: tasks running hot even after scaling
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.app_name}-cpu-high"
  alarm_description   = "Average task CPU above 85% for 3 minutes"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = local.ecs_dims
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# One dashboard with the golden signals (dashboards as code, like Track A's Grafana JSON).
resource "aws_cloudwatch_dashboard" "app" {
  dashboard_name = var.app_name
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "Traffic: requests per minute", region = var.region, stat = "Sum", period = 60
          metrics = [["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.app.arn_suffix]]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title = "Latency: p50 / p95 (seconds)", region = var.region, period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.app.arn_suffix, { stat = "p50", label = "p50" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.app.arn_suffix, { stat = "p95", label = "p95" }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title = "Errors: 5xx and failed health checks", region = var.region, period = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.app.arn_suffix, { stat = "Sum", label = "target 5xx" }],
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.app.arn_suffix, { stat = "Sum", label = "ALB 5xx" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", aws_lb_target_group.app.arn_suffix, "LoadBalancer", aws_lb.app.arn_suffix, { stat = "Maximum", label = "unhealthy tasks" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title = "Saturation: task CPU / memory (%) and healthy tasks", region = var.region, period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name, { stat = "Average", label = "CPU %" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app.name, { stat = "Average", label = "memory %" }],
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.app.arn_suffix, "LoadBalancer", aws_lb.app.arn_suffix, { stat = "Maximum", label = "healthy tasks", yAxis = "right" }]
          ]
        }
      }
    ]
  })
}

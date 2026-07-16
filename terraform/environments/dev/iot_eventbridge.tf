# ============================================================
# IoT Core → EventBridge — Jour 29
# Utilise le bus existant : aws_cloudwatch_event_bus.main
# ============================================================

# ── Rôle IAM : IoT Core autorisé à publier sur EventBridge ──
resource "aws_iam_role" "iot_to_eventbridge" {
  name = "iot-to-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "iot.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_iam_role_policy" "iot_to_eventbridge" {
  name = "iot-put-events-policy"
  role = aws_iam_role.iot_to_eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "events:PutEvents"
        Resource = aws_cloudwatch_event_bus.main.arn
      },
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.intervention.arn
      }
    ]
  })
}

# ── Règle EventBridge : capture les événements CRITICAL ──────
# NOTE : L'action "eventBridge" n'est pas disponible dans aws_iot_topic_rule
# en eu-west-3 (juillet 2026). Le routing IoT → EventBridge passe par Lambda
# (flux existant : IoT → Lambda → EventBridge via PutEvents).
resource "aws_cloudwatch_event_rule" "iot_direct_critical" {
  name           = "smart-assembly-iot-direct-critical"
  description    = "Capture les événements CRITICAL sur le bus assembly"
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    source      = ["aws.iot"]
    detail-type = ["IoTMessage"]
    detail = {
      statut = ["CRITICAL"]
    }
  })

  tags = {
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_cloudwatch_log_group" "iot_direct_events" {
  name              = "/aws/events/iot-direct-critical"
  retention_in_days = 7

  tags = {
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_cloudwatch_event_target" "iot_direct_critical_to_logs" {
  rule           = aws_cloudwatch_event_rule.iot_direct_critical.name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  target_id      = "IotDirectCriticalLogs"
  arn            = aws_cloudwatch_log_group.iot_direct_events.arn
}

resource "aws_cloudwatch_log_resource_policy" "iot_direct_events" {
  policy_name = "eventbridge-iot-direct-logs-policy"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${aws_cloudwatch_log_group.iot_direct_events.arn}:*"
    }]
  })
}

output "iot_direct_log_group" {
  description = "Log group des événements CRITICAL"
  value       = aws_cloudwatch_log_group.iot_direct_events.name
}
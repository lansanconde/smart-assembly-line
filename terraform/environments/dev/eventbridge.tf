# ──────────────────────────────────────────────
# EventBridge — Bus d'événements custom
# ──────────────────────────────────────────────

resource "aws_cloudwatch_event_bus" "main" {
  name = "smart-assembly-events"

  tags = {
    Name        = "smart-assembly-events"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

# ──────────────────────────────────────────────
# Règle EventBridge — anomalie.critique → SQS
# ──────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "critical_to_sqs" {
  name           = "smart-assembly-critical-to-sqs"
  description    = "Route les anomalies critiques vers SQS InterventionQueue"
  event_bus_name = aws_cloudwatch_event_bus.main.name

  event_pattern = jsonencode({
    source      = ["smart-assembly.iot"]
    detail-type = ["anomalie.critique"]
  })

  tags = {
    Name        = "smart-assembly-critical-to-sqs"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_cloudwatch_event_target" "sqs" {
  rule           = aws_cloudwatch_event_rule.critical_to_sqs.name
  event_bus_name = aws_cloudwatch_event_bus.main.name
  target_id      = "InterventionQueue"
  arn            = aws_sqs_queue.intervention.arn
}
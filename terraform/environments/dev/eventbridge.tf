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
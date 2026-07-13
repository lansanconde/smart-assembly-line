# ──────────────────────────────────────────────
# Dead Letter Queue — messages en échec après 3 tentatives
# ──────────────────────────────────────────────

resource "aws_sqs_queue" "intervention_dlq" {
  name                      = "smart-assembly-intervention-dlq"
  message_retention_seconds = 1209600 # 14 jours

  tags = {
    Name        = "smart-assembly-intervention-dlq"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

# ──────────────────────────────────────────────
# Queue principale — InterventionQueue
# ──────────────────────────────────────────────

resource "aws_sqs_queue" "intervention" {
  name                       = "smart-assembly-intervention"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400 # 24 heures
  receive_wait_time_seconds  = 20    # long polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.intervention_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "smart-assembly-intervention"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

# Autoriser EventBridge à envoyer des messages dans SQS
resource "aws_sqs_queue_policy" "intervention" {
  queue_url = aws_sqs_queue.intervention.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridge"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.intervention.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_cloudwatch_event_rule.critical_to_sqs.arn
          }
        }
      }
    ]
  })
}
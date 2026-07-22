# ============================================================
# CloudWatch Alarms + SNS — Alerting IoT
# Smart Assembly Line
#
# Métriques source : namespace SmartAssemblyLine
# Alarms : Vibration | Temperature | AnomalyScore | MessageCount CRITICAL
# Composite : Vibration AND AnomalyML → escalade haute confiance
# ============================================================

# ── SNS Topic ───────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "smart-assembly-alerts"

  tags = { Project = "smart-assembly-line" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "lansana.conde.pro@gmail.com"
}

# ── Permission CloudWatch → SNS ─────────────────────────────
resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudWatchAlarms"
      Effect = "Allow"
      Principal = {
        Service = "cloudwatch.amazonaws.com"
      }
      Action   = "SNS:Publish"
      Resource = aws_sns_topic.alerts.arn
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:cloudwatch:eu-west-3:${data.aws_caller_identity.current.account_id}:alarm:*"
        }
      }
    }]
  })
}


# ── Alarm 1 : Vibration CRITICAL ────────────────────────────
resource "aws_cloudwatch_metric_alarm" "vibration_critical" {
  alarm_name          = "smart-assembly-vibration-critical"
  alarm_description   = "Vibration poste_1 > 2.5 m/s² pendant 2 minutes — CRITICAL"
  namespace           = "SmartAssemblyLine"
  metric_name         = "Vibration"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 2.5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    Poste = "poste_1"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Project = "smart-assembly-line", Jour = "34" }
}

# ── Alarm 2 : Temperature CRITICAL ──────────────────────────
resource "aws_cloudwatch_metric_alarm" "temperature_critical" {
  alarm_name          = "smart-assembly-temperature-critical"
  alarm_description   = "Température poste_1 > 95°C pendant 2 minutes — CRITICAL"
  namespace           = "SmartAssemblyLine"
  metric_name         = "Temperature"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 95.0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    Poste = "poste_1"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Project = "smart-assembly-line" }
}

# ── Alarm 3 : Anomaly Score ML ───────────────────────────────
resource "aws_cloudwatch_metric_alarm" "anomaly_ml" {
  alarm_name          = "smart-assembly-anomaly-ml"
  alarm_description   = "Anomalie ML détectée sur poste_1 — score < -0.1"
  namespace           = "SmartAssemblyLine"
  metric_name         = "AnomalyScore"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = -0.1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    Poste = "poste_1"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Project = "smart-assembly-line" }
}

# ── Alarm 4 : Burst de messages CRITICAL ────────────────────
resource "aws_cloudwatch_metric_alarm" "message_critical_burst" {
  alarm_name          = "smart-assembly-message-critical-burst"
  alarm_description   = "Plus de 5 messages CRITICAL sur poste_1 en 1 minute"
  namespace           = "SmartAssemblyLine"
  metric_name         = "MessageCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    Poste  = "poste_1"
    Statut = "CRITICAL"
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Project = "smart-assembly-line", Jour = "34" }
}

# ── Composite Alarm : Vibration AND AnomalyML ───────────────
# Déclenche uniquement si la vibration est CRITIQUE _et_ que
# le ML confirme une anomalie de pattern → double validation,
# zéro faux positif pour l'escalade technicien.
resource "aws_cloudwatch_composite_alarm" "vibration_ml_escalade" {
  alarm_name        = "smart-assembly-vibration-ml-escalade"
  alarm_description = "ESCALADE : vibration critique confirmée par ML — intervention requise"

  alarm_rule = "ALARM(\"${aws_cloudwatch_metric_alarm.vibration_critical.alarm_name}\") AND ALARM(\"${aws_cloudwatch_metric_alarm.anomaly_ml.alarm_name}\")"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Project = "smart-assembly-line", Jour = "34" }
}

# ── Outputs ─────────────────────────────────────────────────
output "sns_topic_arn" {
  description = "ARN du topic SNS d'alertes"
  value       = aws_sns_topic.alerts.arn
}

output "alarms_summary" {
  description = "Alarms déployées"
  value = {
    vibration_critical     = aws_cloudwatch_metric_alarm.vibration_critical.alarm_name
    temperature_critical   = aws_cloudwatch_metric_alarm.temperature_critical.alarm_name
    anomaly_ml             = aws_cloudwatch_metric_alarm.anomaly_ml.alarm_name
    message_critical_burst = aws_cloudwatch_metric_alarm.message_critical_burst.alarm_name
    composite_escalade     = aws_cloudwatch_composite_alarm.vibration_ml_escalade.alarm_name
  }
}

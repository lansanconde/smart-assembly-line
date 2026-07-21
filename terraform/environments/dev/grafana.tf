# ============================================================
# Amazon Managed Grafana — Monitoring dashboards
# Monitoring industriel
#
# Remplace IoT SiteWise Monitor (non disponible en eu-west-3)
# Datasource : CloudWatch namespace SmartAssemblyLine
# ============================================================

# ── IAM Role : Grafana → CloudWatch (lecture) ──────────────
resource "aws_iam_role" "grafana" {
  name = "smart-assembly-grafana-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "grafana.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Project = "smart-assembly-line", Jour = "33" }
}

resource "aws_iam_role_policy" "grafana_cloudwatch" {
  name = "grafana-cloudwatch-read"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchMetricsRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarmsForMetric",
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:GetQueryResults",
          "logs:FilterLogEvents",
        ]
        Resource = "*"
      },
    ]
  })
}

# ── Permission Lambda → CloudWatch PutMetricData ────────────
# Référence le rôle Lambda existant (défini dans lambda.tf)
resource "aws_iam_role_policy" "lambda_put_metrics" {
  name = "lambda-cloudwatch-put-metrics"
  role = aws_iam_role.lambda_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "PutMetrics"
      Effect   = "Allow"
      Action   = ["cloudwatch:PutMetricData"]
      Resource = "*"
      Condition = {
        StringEquals = {
          "cloudwatch:namespace" = "SmartAssemblyLine"
        }
      }
    }]
  })
}

# ── CloudWatch Dashboard — Smart Assembly Line ─────────────
# Amazon Managed Grafana non disponible en eu-west-3.
# CloudWatch native dashboards utilisés à la place.
# Architecture Grafana (eu-west-1 + CW cross-région) documentée dans docs/monitoring/grafana.md

resource "aws_cloudwatch_dashboard" "smart_assembly" {
  dashboard_name = "SmartAssemblyLine"

  dashboard_body = jsonencode({
    widgets = [
      # ── Ligne 1 : Métriques temps réel ─────────────────
      {
        type = "metric"
        x    = 0
        y    = 0
        width = 12
        height = 6
        properties = {
          title  = "Vibration — poste_1 (m/s²)"
          region = "eu-west-3"
          view   = "timeSeries"
          stat   = "Average"
          period = 10
          metrics = [[
            "SmartAssemblyLine", "Vibration",
            "Poste", "poste_1"
          ]]
          annotations = {
            horizontal = [
              { label = "WARN", value = 2.0, color = "#f89256" },
              { label = "CRITICAL", value = 2.5, color = "#d62728" },
            ]
          }
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type = "metric"
        x    = 12
        y    = 0
        width = 12
        height = 6
        properties = {
          title  = "Température — poste_1 (°C)"
          region = "eu-west-3"
          view   = "timeSeries"
          stat   = "Average"
          period = 10
          metrics = [[
            "SmartAssemblyLine", "Temperature",
            "Poste", "poste_1"
          ]]
          annotations = {
            horizontal = [
              { label = "WARN", value = 80.0, color = "#f89256" },
              { label = "CRITICAL", value = 95.0, color = "#d62728" },
            ]
          }
        }
      },
      # ── Ligne 2 : Comptage par statut ──────────────────
      {
        type = "metric"
        x    = 0
        y    = 6
        width = 8
        height = 6
        properties = {
          title  = "Messages CRITICAL — poste_1"
          region = "eu-west-3"
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [[
            "SmartAssemblyLine", "MessageCount",
            "Poste", "poste_1", "Statut", "CRITICAL",
            { color = "#d62728" }
          ]]
        }
      },
      {
        type = "metric"
        x    = 8
        y    = 6
        width = 8
        height = 6
        properties = {
          title  = "Messages WARN — poste_1"
          region = "eu-west-3"
          view   = "timeSeries"
          stat   = "Sum"
          period = 60
          metrics = [[
            "SmartAssemblyLine", "MessageCount",
            "Poste", "poste_1", "Statut", "WARN",
            { color = "#f89256" }
          ]]
        }
      },
      {
        type = "metric"
        x    = 16
        y    = 6
        width = 8
        height = 6
        properties = {
          title  = "Pression — poste_1 (bar)"
          region = "eu-west-3"
          view   = "timeSeries"
          stat   = "Average"
          period = 10
          metrics = [[
            "SmartAssemblyLine", "Pression",
            "Poste", "poste_1"
          ]]
        }
      },
      # ── Ligne 3 : KPI anomalies ML ──────────────────────
      {
        type = "metric"
        x    = 0
        y    = 12
        width = 24
        height = 6
        properties = {
          title  = "Anomaly Score ML — poste_1 (seuil : -0.1)"
          region = "eu-west-3"
          view   = "timeSeries"
          stat   = "Minimum"
          period = 10
          metrics = [[
            "SmartAssemblyLine", "AnomalyScore",
            "Poste", "poste_1",
            { color = "#9467bd" }
          ]]
          annotations = {
            horizontal = [
              { label = "Seuil anomalie", value = -0.1, color = "#d62728" }
            ]
          }
          yAxis = { left = { min = -1, max = 1 } }
        }
      },
    ]
  })
}

# ── Outputs ────────────────────────────────────────────────
output "cloudwatch_dashboard_url" {
  description = "URL du dashboard CloudWatch"
  value       = "https://eu-west-3.console.aws.amazon.com/cloudwatch/home?region=eu-west-3#dashboards:name=SmartAssemblyLine"
}

output "grafana_note" {
  description = "Note architecture Grafana production"
  value       = "Amazon Managed Grafana non disponible en eu-west-3. Déployer en eu-west-1 avec datasource CloudWatch cross-région pour la production."
}

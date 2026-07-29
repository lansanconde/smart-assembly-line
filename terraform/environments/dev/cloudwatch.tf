# =============================================================
# CloudWatch Dashboard — Smart Assembly Line
#
# Vue unifiée sur 4 couches :
#   - Lambda (analyze_vibration, detect_anomaly, store_metrics)
#   - ECS Fargate (supervision-api)
#   - ALB (smart-assembly-alb)
#   - DynamoDB (machine_state)
#
# Grille : 24 colonnes × hauteur libre
# Chaque ligne = 3 widgets de 8 colonnes (8+8+8 = 24)
# =============================================================

locals {
  region         = "eu-west-3"
  dashboard_name = "smart-assembly-overview"

  # Noms des ressources référencées dans les widgets
  lambda_analyze = aws_lambda_function.analyze_vibration.function_name
  lambda_detect  = aws_lambda_function.detect_anomaly.function_name
  lambda_store   = aws_lambda_function.store_metrics.function_name
  ecs_cluster    = aws_ecs_cluster.main.name
  ecs_service    = aws_ecs_service.supervision_api.name
  dynamo_table   = aws_dynamodb_table.machine_state.name
  alb_suffix     = aws_lb.main.arn_suffix
  tg_suffix      = aws_lb_target_group.backend.arn_suffix
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.dashboard_name

  dashboard_body = jsonencode({
    widgets = [

      # ──────────────────────────────────────────────────────
      # LIGNE 0 — Titre
      # ──────────────────────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# Smart Assembly Line — Tableau de bord\nObservabilité unifiée : Lambda · ECS Fargate · ALB · DynamoDB | Région : eu-west-3"
        }
      },

      # ──────────────────────────────────────────────────────
      # LIGNE 1 — Lambda : analyze_vibration
      # ──────────────────────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Lambda — Invocations (analyze_vibration)"
          view   = "timeSeries"
          region = local.region
          period = 300
          metrics = [[
            "AWS/Lambda", "Invocations",
            "FunctionName", local.lambda_analyze,
            { stat = "Sum", color = "#1f77b4" }
          ]]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Lambda — Erreurs (analyze_vibration)"
          view   = "timeSeries"
          region = local.region
          period = 300
          metrics = [[
            "AWS/Lambda", "Errors",
            "FunctionName", local.lambda_analyze,
            { stat = "Sum", color = "#d62728" }
          ]]
          annotations = {
            horizontal = [{ value = 1, label = "Seuil alerte", color = "#ff7f0e" }]
          }
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Lambda — Durée p99 (3 fonctions)"
          view   = "timeSeries"
          region = local.region
          period = 300
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", local.lambda_analyze,
            { stat = "p99", label = "analyze_vibration", color = "#1f77b4" }],
            ["AWS/Lambda", "Duration", "FunctionName", local.lambda_detect,
            { stat = "p99", label = "detect_anomaly", color = "#ff7f0e" }],
            ["AWS/Lambda", "Duration", "FunctionName", local.lambda_store,
            { stat = "p99", label = "store_metrics", color = "#2ca02c" }]
          ]
          yAxis = { left = { min = 0, label = "ms" } }
        }
      },

      # ──────────────────────────────────────────────────────
      # LIGNE 2 — ECS Fargate : supervision-api
      # ──────────────────────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "ECS — CPU Utilization (%)"
          view   = "timeSeries"
          region = local.region
          period = 60
          metrics = [[
            "ECS/ContainerInsights", "CpuUtilized",
            "ClusterName", local.ecs_cluster,
            "ServiceName", local.ecs_service,
            { stat = "Average", color = "#9467bd" }
          ]]
          annotations = {
            horizontal = [{ value = 80, label = "Seuil scale-out", color = "#d62728" }]
          }
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "ECS — Memory Utilization (%)"
          view   = "timeSeries"
          region = local.region
          period = 60
          metrics = [[
            "ECS/ContainerInsights", "MemoryUtilized",
            "ClusterName", local.ecs_cluster,
            "ServiceName", local.ecs_service,
            { stat = "Average", color = "#8c564b" }
          ]]
          annotations = {
            horizontal = [{ value = 85, label = "Seuil alerte", color = "#d62728" }]
          }
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 8
        width  = 8
        height = 6
        properties = {
          title  = "ECS — Running Tasks"
          view   = "timeSeries"
          region = local.region
          period = 60
          metrics = [[
            "ECS/ContainerInsights", "RunningTaskCount",
            "ClusterName", local.ecs_cluster,
            "ServiceName", local.ecs_service,
            { stat = "Average", color = "#2ca02c" }
          ]]
          annotations = {
            horizontal = [{ value = 1, label = "Desired", color = "#7f7f7f" }]
          }
          yAxis = { left = { min = 0 } }
        }
      },

      # ──────────────────────────────────────────────────────
      # LIGNE 3 — ALB
      # ──────────────────────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "ALB — Requêtes par minute"
          view   = "timeSeries"
          region = local.region
          period = 60
          metrics = [[
            "AWS/ApplicationELB", "RequestCount",
            "LoadBalancer", local.alb_suffix,
            { stat = "Sum", color = "#1f77b4" }
          ]]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "ALB — Latence p99 (ms)"
          view   = "timeSeries"
          region = local.region
          period = 60
          metrics = [[
            "AWS/ApplicationELB", "TargetResponseTime",
            "LoadBalancer", local.alb_suffix,
            { stat = "p99", color = "#ff7f0e" }
          ]]
          annotations = {
            horizontal = [{ value = 2, label = "SLA 2s", color = "#d62728" }]
          }
          yAxis = { left = { min = 0, label = "secondes" } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "ALB — Erreurs 5xx + Healthy Hosts"
          view   = "timeSeries"
          region = local.region
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count",
              "LoadBalancer", local.alb_suffix,
            { stat = "Sum", label = "5xx ECS", color = "#d62728" }],
            ["AWS/ApplicationELB", "HealthyHostCount",
              "LoadBalancer", local.alb_suffix,
              "TargetGroup", local.tg_suffix,
            { stat = "Minimum", label = "Healthy Hosts", color = "#2ca02c", yAxis = "right" }]
          ]
          yAxis = {
            left  = { min = 0, label = "erreurs" }
            right = { min = 0, label = "hosts sains" }
          }
        }
      },

      # ──────────────────────────────────────────────────────
      # LIGNE 4 — DynamoDB
      # ──────────────────────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 20
        width  = 8
        height = 6
        properties = {
          title  = "DynamoDB — Lectures (RCU consommées)"
          view   = "timeSeries"
          region = local.region
          period = 300
          metrics = [[
            "AWS/DynamoDB", "ConsumedReadCapacityUnits",
            "TableName", local.dynamo_table,
            { stat = "Sum", color = "#17becf" }
          ]]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 20
        width  = 8
        height = 6
        properties = {
          title  = "DynamoDB — Écritures (WCU consommées)"
          view   = "timeSeries"
          region = local.region
          period = 300
          metrics = [[
            "AWS/DynamoDB", "ConsumedWriteCapacityUnits",
            "TableName", local.dynamo_table,
            { stat = "Sum", color = "#bcbd22" }
          ]]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 20
        width  = 8
        height = 6
        properties = {
          title  = "DynamoDB — Latence p99 (ms)"
          view   = "timeSeries"
          region = local.region
          period = 300
          metrics = [
            ["AWS/DynamoDB", "SuccessfulRequestLatency",
              "TableName", local.dynamo_table,
              "Operation", "GetItem",
            { stat = "p99", label = "GetItem p99" }],
            ["AWS/DynamoDB", "SuccessfulRequestLatency",
              "TableName", local.dynamo_table,
              "Operation", "Scan",
            { stat = "p99", label = "Scan p99" }]
          ]
          yAxis = { left = { min = 0, label = "ms" } }
        }
      },

      # ──────────────────────────────────────────────────────
      # LIGNE 5 — État des alarmes
      # ──────────────────────────────────────────────────────
      {
        type   = "alarm"
        x      = 0
        y      = 26
        width  = 24
        height = 4
        properties = {
          title = "État des Alarmes — Smart Assembly Line"
          alarms = [
            aws_cloudwatch_metric_alarm.vibration_critical.arn,
            aws_cloudwatch_metric_alarm.temperature_critical.arn,
            aws_cloudwatch_metric_alarm.anomaly_ml.arn,
            aws_cloudwatch_metric_alarm.message_critical_burst.arn,
            aws_cloudwatch_composite_alarm.vibration_ml_escalade.arn
          ]
        }
      }
    ]
  })
}

# ──────────────────────────────────────────────────────────
# Output — URL console du dashboard
# ──────────────────────────────────────────────────────────
output "dashboard_url" {
  description = "URL console CloudWatch du dashboard"
  value       = "https://${local.region}.console.aws.amazon.com/cloudwatch/home?region=${local.region}#dashboards:name=${local.dashboard_name}"
}

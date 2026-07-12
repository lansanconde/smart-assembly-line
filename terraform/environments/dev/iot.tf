# Thing - representing logique du device dans IoT Core
# Un Thing par poste physique d'assemblage, avec un nom unique dans le compte AWS

resource "aws_iot_thing" "poste_1" {
  name = "poste_1"
}


# Policy — autorisations strictes par device (least privilege)
# Un device ne peut publier que sur son propre topic
resource "aws_iot_policy" "device_policy" {
  name = "smart-assembly-device-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Autoriser la connexion avec son propre ClientId
        Effect   = "Allow"
        Action   = "iot:Connect"
        Resource = "arn:aws:iot:eu-west-3:169237360990:client/$${iot:ClientId}"
      },
      {
        # Publier uniquement sur son propre topic — isolation stricte entre postes
        Effect   = "Allow"
        Action   = "iot:Publish"
        Resource = "arn:aws:iot:eu-west-3:169237360990:topic/assembly-line/$${iot:ClientId}/metrics"
      },
      {
        # Accès au Device Shadow pour synchronisation état desired/reported
        Effect   = "Allow"
        Action   = ["iot:GetThingShadow", "iot:UpdateThingShadow"]
        Resource = "arn:aws:iot:eu-west-3:169237360990:thing/$${iot:ClientId}"
      }
    ]
  })
}


# ──────────────────────────────────────────────
# IoT Rules Engine — Déclenchement des Lambdas
# ──────────────────────────────────────────────

resource "aws_iot_topic_rule" "analyze_vibration_rule" {
  name        = "smart_assembly_analyze_vibration"
  description = "Déclenche AnalyzeVibration sur chaque message capteur"
  enabled     = true
  sql         = "SELECT * FROM 'assembly-line/+/metrics'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.analyze_vibration.arn
  }
}

resource "aws_iot_topic_rule" "store_metrics_rule" {
  name        = "smart_assembly_store_metrics"
  description = "Déclenche StoreMetrics pour archiver chaque message dans S3"
  enabled     = true
  sql         = "SELECT * FROM 'assembly-line/+/metrics'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.store_metrics.arn
  }
}


resource "aws_iot_topic_rule" "detect_anomaly_rule" {
  name        = "smart_assembly_detect_anomaly"
  description = "Declenche DetectAnomaly pour les regles metier avancees"
  enabled     = true
  sql         = "SELECT * FROM 'assembly-line/+/metrics'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.detect_anomaly.arn
  }
}

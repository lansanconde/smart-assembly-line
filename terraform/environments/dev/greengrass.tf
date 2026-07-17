# ============================================================
# AWS IoT Greengrass v2 — Core Device
# Edge Computing (Docker sur PC local)
#
# Crée dans IoT Core eu-west-3 :
#   - IoT Thing  : greengrass-core-poste
#   - Certificat : X.509 pour le Core Device
#   - IoT Policy : autorisations Greengrass + MQTT
#   - IAM Role   : GreengrassV2TokenExchangeRole
# ============================================================

# ── IoT Thing — le Core Device Greengrass ───────────────────
resource "aws_iot_thing" "greengrass_core" {
  name = "greengrass-core-poste"

  attributes = {
    type        = "greengrass-core"
    environment = "dev"
  }
}

# ── Certificat X.509 pour le Core Device ────────────────────
resource "aws_iot_certificate" "greengrass_core" {
  active = true
}

# Attacher le certificat au Thing
resource "aws_iot_thing_principal_attachment" "greengrass_core" {
  thing     = aws_iot_thing.greengrass_core.name
  principal = aws_iot_certificate.greengrass_core.arn
}

# ── IoT Policy — autorisations Greengrass ───────────────────
resource "aws_iot_policy" "greengrass_core" {
  name = "GreengrassCorePolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Connexion MQTT
      {
        Effect   = "Allow"
        Action   = "iot:Connect"
        Resource = "arn:aws:iot:eu-west-3:${data.aws_caller_identity.current.account_id}:client/greengrass-core-poste"
      },
      # Publication vers IoT Core (données filtrées WARN/CRITICAL)
      {
        Effect   = "Allow"
        Action   = "iot:Publish"
        Resource = [
          "arn:aws:iot:eu-west-3:${data.aws_caller_identity.current.account_id}:topic/assembly-line/*/metrics",
          "arn:aws:iot:eu-west-3:${data.aws_caller_identity.current.account_id}:topic/assembly-line/*/alerts",
          "arn:aws:iot:eu-west-3:${data.aws_caller_identity.current.account_id}:topic/$aws/things/*/shadow/*",
          "arn:aws:iot:eu-west-3:${data.aws_caller_identity.current.account_id}:topic/$aws/things/greengrass-core-poste/*"
        ]
      },
      # Abonnement aux topics (delta Shadow, commandes OTA)
      {
        Effect   = "Allow"
        Action   = ["iot:Subscribe", "iot:Receive"]
        Resource = [
          "arn:aws:iot:eu-west-3:${data.aws_caller_identity.current.account_id}:topicfilter/assembly-line/*",
          "arn:aws:iot:eu-west-3:${data.aws_caller_identity.current.account_id}:topicfilter/$aws/things/*/shadow/*",
          "arn:aws:iot:eu-west-3:${data.aws_caller_identity.current.account_id}:topicfilter/$aws/things/greengrass-core-poste/*"
        ]
      },
      # Device Shadow
      {
        Effect   = "Allow"
        Action   = [
          "iot:GetThingShadow",
          "iot:UpdateThingShadow",
          "iot:DeleteThingShadow"
        ]
        Resource = "arn:aws:iot:eu-west-3:${data.aws_caller_identity.current.account_id}:thing/greengrass-core-poste"
      },
      # Token Exchange — requis par Greengrass Nucleus
      {
        Effect   = "Allow"
        Action   = "iot:AssumeRoleWithCertificate"
        Resource = "arn:aws:iot:eu-west-3:${data.aws_caller_identity.current.account_id}:rolealias/GreengrassV2TokenExchangeRoleAlias"
      }
    ]
  })
}

# Attacher la policy au certificat
resource "aws_iot_policy_attachment" "greengrass_core" {
  policy = aws_iot_policy.greengrass_core.name
  target = aws_iot_certificate.greengrass_core.arn
}

# ── IAM Role — Token Exchange (requis par Greengrass Nucleus) ─
resource "aws_iam_role" "greengrass_token_exchange" {
  name = "GreengrassV2TokenExchangeRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "credentials.iot.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_iam_role_policy" "greengrass_token_exchange" {
  name = "GreengrassV2TokenExchangePolicy"
  role = aws_iam_role.greengrass_token_exchange.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Logs CloudWatch (pour les components)
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:eu-west-3:${data.aws_caller_identity.current.account_id}:*"
      },
      # S3 — téléchargement des artefacts des components
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.raw_data.arn}/components/*"
      }
    ]
  })
}

# ── IoT Role Alias — lien entre certificat et IAM Role ───────
resource "aws_iot_role_alias" "greengrass_token_exchange" {
  alias    = "GreengrassV2TokenExchangeRoleAlias"
  role_arn = aws_iam_role.greengrass_token_exchange.arn
}

# ── Écriture locale des certificats pour Docker ──────────────
# Les certificats sont écrits dans greengrass/certs/
# pour être montés dans le conteneur Docker
resource "local_file" "greengrass_cert" {
  content         = aws_iot_certificate.greengrass_core.certificate_pem
  filename        = "${path.module}/../../../src/greengrass/certs/device.pem.crt"
  file_permission = "0644"
}

resource "local_file" "greengrass_key" {
  content         = aws_iot_certificate.greengrass_core.private_key
  filename        = "${path.module}/../../../src/greengrass/certs/private.pem.key"
  file_permission = "0600"
}

# ── Outputs ──────────────────────────────────────────────────
output "greengrass_thing_name" {
  description = "Nom du Core Device Greengrass"
  value       = aws_iot_thing.greengrass_core.name
}

output "greengrass_cert_arn" {
  description = "ARN du certificat du Core Device"
  value       = aws_iot_certificate.greengrass_core.arn
}

output "greengrass_role_alias" {
  description = "Role Alias pour le Token Exchange"
  value       = aws_iot_role_alias.greengrass_token_exchange.alias
}

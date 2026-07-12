# ──────────────────────────────────────────────
# Data source — compte AWS courant
# ──────────────────────────────────────────────

data "aws_caller_identity" "current" {}

# ──────────────────────────────────────────────
# CMK — Customer Managed Key
# Chiffrement S3 + DynamoDB
# ──────────────────────────────────────────────

resource "aws_kms_key" "main" {
  description             = "smart-assembly-line — chiffrement S3 et DynamoDB"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # L'admin IAM du compte peut gérer la clé
        Sid    = "AdminAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # Lambda peut utiliser la clé pour chiffrer/déchiffrer
        Sid    = "LambdaAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_role.arn
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = "*"
      },
      {
        # S3 et DynamoDB peuvent utiliser la clé (service principals)
        Sid    = "AWSServiceAccess"
        Effect = "Allow"
        Principal = {
          Service = [
            "s3.amazonaws.com",
            "dynamodb.amazonaws.com"
          ]
        }
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name        = "smart-assembly-key"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

# Alias lisible pour la clé
resource "aws_kms_alias" "main" {
  name          = "alias/smart-assembly-key"
  target_key_id = aws_kms_key.main.key_id
}
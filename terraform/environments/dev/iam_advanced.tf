# ──────────────────────────────────────────────
# Permission Boundary — plafond de permissions Lambda
# Empêche toute privilege escalation même si la policy s'élargit
# ──────────────────────────────────────────────

resource "aws_iam_policy" "lambda_boundary" {
  name        = "smart-assembly-lambda-boundary"
  description = "Permission boundary for Lambda role — hard limit on allowed actions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Write"
        Effect = "Allow"
        Action = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.raw_data.arn}/*"
      },
      {
        Sid    = "AllowDynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Resource = aws_dynamodb_table.machine_state.arn
      },
      {
        Sid    = "AllowKMS"
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = aws_kms_key.main.arn
      },
      {
        Sid    = "AllowLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:eu-west-3:*:*"
      }
    ]
  })
}

# Attacher la boundary au rôle Lambda existant
resource "aws_iam_role_policy_attachment" "lambda_boundary" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_boundary.arn
}

# ──────────────────────────────────────────────
# Policy data lake — écriture restreinte au rôle Lambda uniquement
# Interdit explicitement la lecture depuis Lambda (séparation des responsabilités)
# ──────────────────────────────────────────────

resource "aws_s3_bucket_policy" "raw_data" {
  bucket = aws_s3_bucket.raw_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaWrite"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_role.arn
        }
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.raw_data.arn}/*"
      },
      {
        Sid    = "DenyPublicAccess"
        Effect = "Deny"
        Principal = "*"
        Action   = ["s3:*"]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
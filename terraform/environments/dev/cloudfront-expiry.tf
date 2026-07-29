# ─────────────────────────────────────────────────────────────────────────────
# CloudFront auto-expiry — 31 décembre 2026 23h59 (heure Paris)
#
# Mécanisme : EventBridge Scheduler (one-time) → Lambda → UpdateDistribution
# La distribution supervision_api est désactivée automatiquement.
# La distribution portfolio (E271YNMVZ3GMXD) reste active.
# ─────────────────────────────────────────────────────────────────────────────

# ── Code Lambda inline ───────────────────────────────────────────────────────
data "archive_file" "cf_expiry" {
  type        = "zip"
  output_path = "${path.module}/cf_expiry.zip"

  source {
    filename = "handler.py"
    content  = <<-PYTHON
import boto3
import os

CF_DISTRIBUTION_ID = os.environ["CF_DISTRIBUTION_ID"]
ECS_CLUSTER        = os.environ["ECS_CLUSTER"]
ECS_SERVICE        = os.environ["ECS_SERVICE"]

def disable_cloudfront():
    cf   = boto3.client("cloudfront")
    resp = cf.get_distribution_config(Id=CF_DISTRIBUTION_ID)
    config = resp["DistributionConfig"]
    etag   = resp["ETag"]

    if not config["Enabled"]:
        print(f"[INFO] CloudFront {CF_DISTRIBUTION_ID} déjà désactivée.")
        return "already_disabled"

    config["Enabled"] = False
    cf.update_distribution(DistributionConfig=config, Id=CF_DISTRIBUTION_ID, IfMatch=etag)
    print(f"[OK] CloudFront {CF_DISTRIBUTION_ID} désactivée.")
    return "disabled"

def stop_ecs():
    ecs = boto3.client("ecs")
    ecs.update_service(
        cluster=ECS_CLUSTER,
        service=ECS_SERVICE,
        desiredCount=0
    )
    print(f"[OK] ECS service {ECS_SERVICE} → desiredCount=0 (Fargate stoppé).")
    return "stopped"

def handler(event, context):
    cf_status  = disable_cloudfront()
    ecs_status = stop_ecs()

    print(f"[DONE] Fin période recherche emploi 2026-12 — CF: {cf_status}, ECS: {ecs_status}")
    return {
        "cloudfront": cf_status,
        "ecs":        ecs_status
    }
PYTHON
  }
}

# ── IAM — rôle d'exécution Lambda ───────────────────────────────────────────
resource "aws_iam_role" "cf_expiry_lambda" {
  name = "smart-assembly-cf-expiry-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project   = "smart-assembly-line"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy" "cf_expiry_lambda" {
  name = "cf-expiry-policy"
  role = aws_iam_role.cf_expiry_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudFrontDisable"
        Effect = "Allow"
        Action = [
          "cloudfront:GetDistributionConfig",
          "cloudfront:UpdateDistribution"
        ]
        Resource = "*"
      },
      {
        Sid      = "ECSStop"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService"]
        Resource = "arn:aws:ecs:eu-west-3:*:service/smart-assembly-cluster/supervision-api"
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ── Lambda ───────────────────────────────────────────────────────────────────
resource "aws_lambda_function" "cf_expiry" {
  function_name    = "smart-assembly-cf-expiry"
  filename         = data.archive_file.cf_expiry.output_path
  source_code_hash = data.archive_file.cf_expiry.output_base64sha256
  role             = aws_iam_role.cf_expiry_lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      CF_DISTRIBUTION_ID = aws_cloudfront_distribution.supervision_api.id
      ECS_CLUSTER        = "smart-assembly-cluster"
      ECS_SERVICE        = "supervision-api"
    }
  }

  tags = {
    Project   = "smart-assembly-line"
    ManagedBy = "terraform"
  }
}

# ── IAM — rôle EventBridge Scheduler ────────────────────────────────────────
resource "aws_iam_role" "scheduler_cf_expiry" {
  name = "smart-assembly-scheduler-cf-expiry"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_cf_expiry" {
  name = "invoke-cf-expiry-lambda"
  role = aws_iam_role.scheduler_cf_expiry.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.cf_expiry.arn
    }]
  })
}

# ── EventBridge Scheduler — one-time, 31 décembre 2026 22:59 UTC ─────────────
# 22:59 UTC = 23:59 heure Paris (UTC+1 en hiver)
resource "aws_scheduler_schedule" "cf_expiry" {
  name        = "smart-assembly-cf-expiry-2026-12-31"
  group_name  = "default"
  description = "Désactive la distribution CloudFront supervision-api — fin période recherche emploi"

  flexible_time_window { mode = "OFF" }

  schedule_expression          = "at(2026-12-31T22:59:00)"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.cf_expiry.arn
    role_arn = aws_iam_role.scheduler_cf_expiry.arn
    input = jsonencode({
      reason       = "job-search-deadline-2026-12"
      triggered_by = "EventBridge Scheduler"
    })
  }
}

# ── Output confirmation ───────────────────────────────────────────────────────
output "cf_expiry_scheduled_at" {
  description = "Date/heure de désactivation automatique de la distribution API"
  value       = "2026-12-31T23:59:00 (heure Paris) — EventBridge Scheduler → Lambda cf_expiry"
}

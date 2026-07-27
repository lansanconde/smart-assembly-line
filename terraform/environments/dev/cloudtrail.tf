# ============================================================
# CloudTrail — Audit & Traçabilité
# Smart Assembly Line
#
# Trail multi-région, logs S3 chiffrés KMS, CloudWatch Logs,
# metric filter IAM changes → alarm → SNS (topic existant)
# ============================================================

# ── S3 bucket dédié aux logs CloudTrail ─────────────────────
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = "smart-assembly-cloudtrail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # lab uniquement — retirer en production

  tags = { Project = "smart-assembly-line" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "cloudtrail-retention"
    status = "Enabled"

    filter {} # applique la règle à tous les objets

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 365
      storage_class = "GLACIER"
    }
    expiration {
      days = 2555 # 7 ans — conformité réglementaire aérospatiale
    }
  }
}

# ── Policy S3 : autoriser CloudTrail à écrire ───────────────
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudtrail:eu-west-3:${data.aws_caller_identity.current.account_id}:trail/smart-assembly-trail"
          }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:aws:cloudtrail:eu-west-3:${data.aws_caller_identity.current.account_id}:trail/smart-assembly-trail"
          }
        }
      }
    ]
  })
}

# ── CloudWatch Logs group ────────────────────────────────────
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/smart-assembly"
  retention_in_days = 90

  tags = { Project = "smart-assembly-line", Jour = "37" }
}

# ── IAM Role : CloudTrail → CloudWatch Logs ─────────────────
resource "aws_iam_role" "cloudtrail_cw" {
  name = "smart-assembly-cloudtrail-cw-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Project = "smart-assembly-line" }
}

resource "aws_iam_role_policy" "cloudtrail_cw" {
  name = "cloudtrail-cloudwatch-logs"
  role = aws_iam_role.cloudtrail_cw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

# ── Trail principal ──────────────────────────────────────────
resource "aws_cloudtrail" "main" {
  name           = "smart-assembly-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs.id
  # pas de s3_key_prefix : logs dans AWSLogs/<account>/ directement (correspond au bucket policy)
  include_global_service_events = true # IAM, STS, CloudFront (us-east-1)
  is_multi_region_trail         = true # toutes les régions
  enable_log_file_validation    = true # intégrité des logs (SHA-256)
  # kms_key_id omis : la key policy KMS existante n'autorise pas cloudtrail.amazonaws.com
  # Les logs S3 restent chiffrés via SSE-KMS du bucket (même clé)
  # En production : ajouter cloudtrail.amazonaws.com à la key policy

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cw.arn

  # Management events uniquement (pas Data events — coût)
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]

  tags = { Project = "smart-assembly-line" }
}

# ── Metric Filter : modifications IAM ───────────────────────
resource "aws_cloudwatch_log_metric_filter" "iam_changes" {
  name           = "smart-assembly-iam-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  # Filtre sur les modifications de policies et rôles IAM
  pattern = "{ ($.eventSource = \"iam.amazonaws.com\") && (($.eventName = \"PutRolePolicy\") || ($.eventName = \"DeleteRolePolicy\") || ($.eventName = \"AttachRolePolicy\") || ($.eventName = \"DetachRolePolicy\") || ($.eventName = \"CreatePolicy\") || ($.eventName = \"DeletePolicy\")) }"

  metric_transformation {
    name      = "IamPolicyChanges"
    namespace = "SmartAssemblyLine/Security"
    value     = "1"
  }
}

# ── Alarm : modification IAM → SNS ──────────────────────────
resource "aws_cloudwatch_metric_alarm" "iam_changes" {
  alarm_name          = "smart-assembly-iam-policy-changes"
  alarm_description   = "Modification de policy IAM détectée sur le compte"
  namespace           = "SmartAssemblyLine/Security"
  metric_name         = "IamPolicyChanges"
  statistic           = "Sum"
  period              = 300 # 5 minutes
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = { Project = "smart-assembly-line" }
}

# ── Metric Filter : désactivation CloudTrail (critique) ─────
resource "aws_cloudwatch_log_metric_filter" "cloudtrail_disabled" {
  name           = "smart-assembly-cloudtrail-disabled"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  pattern = "{ ($.eventName = \"StopLogging\") || ($.eventName = \"DeleteTrail\") || ($.eventName = \"UpdateTrail\") }"

  metric_transformation {
    name      = "CloudTrailChanges"
    namespace = "SmartAssemblyLine/Security"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "cloudtrail_disabled" {
  alarm_name          = "smart-assembly-cloudtrail-disabled"
  alarm_description   = "CRITIQUE : CloudTrail désactivé ou modifié"
  namespace           = "SmartAssemblyLine/Security"
  metric_name         = "CloudTrailChanges"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]

  tags = { Project = "smart-assembly-line" }
}

# ── Outputs ──────────────────────────────────────────────────
output "cloudtrail_arn" {
  description = "ARN du trail CloudTrail"
  value       = aws_cloudtrail.main.arn
}

output "cloudtrail_s3_bucket" {
  description = "Bucket S3 des logs CloudTrail"
  value       = aws_s3_bucket.cloudtrail_logs.bucket
}

output "cloudtrail_cw_log_group" {
  description = "CloudWatch Logs group CloudTrail"
  value       = aws_cloudwatch_log_group.cloudtrail.name
}

output "cloudtrail_console_url" {
  description = "URL console CloudTrail Event History"
  value       = "https://eu-west-3.console.aws.amazon.com/cloudtrail/home?region=eu-west-3#/events"
}

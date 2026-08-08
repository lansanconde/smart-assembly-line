# Sécurité — Ressources Terraform

```hcl
# GuardDuty
resource "aws_guardduty_detector" "main" {
  enable = true
  finding_publishing_frequency = "SIX_HOURS"
}

# Security Hub
resource "aws_securityhub_account" "main" {}
resource "aws_securityhub_standards_subscription" "aws_foundational" {
  standards_arn = "arn:aws:securityhub:::ruleset/aws-foundational-security-best-practices/v/1.0.0"
}

# Config recorder
resource "aws_config_configuration_recorder" "main" {
  name     = "smart-assembly-recorder"
  role_arn = aws_iam_role.config.arn
  recording_group { all_supported = true }
}

# KMS CMK
resource "aws_kms_key" "dynamodb" {
  description             = "CMK DynamoDB — Smart Assembly Line"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}
```

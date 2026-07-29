# Terraform — Sécurité avancée (GuardDuty · Security Hub · AWS Config)

---

## Structure des fichiers

```
terraform/
├── guardduty.tf       ← Activation + EventBridge remediation
├── securityhub.tf     ← Standards CIS + FSBP
├── config.tf          ← Rules + Remediation
└── security-alerts.tf ← SNS + Lambda remediation
```

---

## guardduty.tf

```hcl
# ── Activation GuardDuty ──────────────────────────────────────────

resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true  # Analyse des accès S3
    }
    kubernetes {
      audit_logs {
        enable = false  # Pas de K8s dans le projet
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  finding_publishing_frequency = "SIX_HOURS"  # FIFTEEN_MINUTES en prod

  tags = {
    Project     = "smart-assembly-line"
    Environment = var.environment
    Jour        = "47"
  }
}

# ── EventBridge Rule — Findings GuardDuty → SNS ──────────────────

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "smart-assembly-guardduty-findings"
  description = "Capture GuardDuty HIGH/MEDIUM findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 4] }]  # >= 4 = MEDIUM+
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "guardduty-to-sns"
  arn       = aws_sns_topic.security_alerts.arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      type        = "$.detail.type"
      description = "$.detail.description"
      account     = "$.account"
      region      = "$.region"
      time        = "$.time"
    }
    input_template = <<EOF
"[GuardDuty ALERT] Sévérité: <severity> | Type: <type> | Compte: <account> | Région: <region> | Heure: <time> | Description: <description>"
EOF
  }
}

# ── EventBridge Rule — Findings HIGH → Lambda Remediation ────────

resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "smart-assembly-guardduty-high"
  description = "GuardDuty HIGH findings → remediation automatique"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]  # >= 7 = HIGH
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_high_remediation" {
  rule      = aws_cloudwatch_event_rule.guardduty_high.name
  target_id = "guardduty-high-remediation"
  arn       = aws_lambda_function.security_remediation.arn
}

resource "aws_lambda_permission" "guardduty_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_remediation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_high.arn
}
```

---

## securityhub.tf

```hcl
# ── Activation Security Hub ───────────────────────────────────────

resource "aws_securityhub_account" "main" {}

# ── Standard : AWS Foundational Security Best Practices ──────────

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:eu-west-3::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.main]
}

# ── Standard : CIS AWS Foundations Benchmark v1.4 ────────────────

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:eu-west-3::standards/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.main]
}

# ── Intégration GuardDuty → Security Hub ─────────────────────────

resource "aws_securityhub_product_subscription" "guardduty" {
  product_arn = "arn:aws:securityhub:eu-west-3::product/aws/guardduty"
  depends_on  = [aws_securityhub_account.main]
}

# ── Intégration AWS Config → Security Hub ────────────────────────

resource "aws_securityhub_product_subscription" "config" {
  product_arn = "arn:aws:securityhub:eu-west-3::product/aws/config"
  depends_on  = [aws_securityhub_account.main]
}

# ── EventBridge — Findings CRITICAL Security Hub ─────────────────

resource "aws_cloudwatch_event_rule" "securityhub_critical" {
  name        = "smart-assembly-securityhub-critical"
  description = "Security Hub CRITICAL findings"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["CRITICAL", "HIGH"]
        }
        Workflow = {
          Status = ["NEW"]
        }
        RecordState = ["ACTIVE"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "securityhub_to_sns" {
  rule      = aws_cloudwatch_event_rule.securityhub_critical.name
  target_id = "securityhub-to-sns"
  arn       = aws_sns_topic.security_alerts.arn
}
```

---

## config.tf

```hcl
# ── Rôle IAM pour AWS Config ──────────────────────────────────────

resource "aws_iam_role" "config" {
  name = "smart-assembly-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# ── Bucket S3 pour Config (historique de conformité) ─────────────

resource "aws_s3_bucket" "config" {
  bucket = "smart-assembly-config-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.config.arn
      },
      {
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# ── Configuration Recorder ────────────────────────────────────────

resource "aws_config_configuration_recorder" "main" {
  name     = "smart-assembly-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "smart-assembly-config-channel"
  s3_bucket_name = aws_s3_bucket.config.id
  depends_on     = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

# ── Règles de conformité ──────────────────────────────────────────

# DynamoDB PITR activé
resource "aws_config_config_rule" "dynamodb_pitr" {
  name = "dynamodb-pitr-enabled"

  source {
    owner             = "AWS"
    source_identifier = "DYNAMODB_PITR_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# KMS rotation activée
resource "aws_config_config_rule" "kms_rotation" {
  name = "kms-key-rotation-enabled"

  source {
    owner             = "AWS"
    source_identifier = "CMK_BACKING_KEY_ROTATION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# VPC Flow Logs activés
resource "aws_config_config_rule" "vpc_flow_logs" {
  name = "vpc-flow-logs-enabled"

  source {
    owner             = "AWS"
    source_identifier = "VPC_FLOW_LOGS_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# Pas de secrets en clair dans les définitions de tâches ECS
resource "aws_config_config_rule" "ecs_no_secrets" {
  name = "ecs-task-definition-no-environment-secrets"

  source {
    owner             = "AWS"
    source_identifier = "ECS_TASK_DEFINITION_NO_ENVIRONMENT_VARIABLES"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# S3 Block Public Access
resource "aws_config_config_rule" "s3_public_access" {
  name = "s3-account-level-public-access-blocks"

  source {
    owner             = "AWS"
    source_identifier = "S3_ACCOUNT_LEVEL_PUBLIC_ACCESS_BLOCKS_PERIODIC"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# MFA obligatoire pour les users IAM avec accès console
resource "aws_config_config_rule" "iam_mfa" {
  name = "mfa-enabled-for-iam-console-access"

  source {
    owner             = "AWS"
    source_identifier = "MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}

# Pas de clé d'accès sur le compte root
resource "aws_config_config_rule" "root_no_access_key" {
  name = "iam-root-access-key-check"

  source {
    owner             = "AWS"
    source_identifier = "IAM_ROOT_ACCESS_KEY_CHECK"
  }

  depends_on = [aws_config_configuration_recorder_status.main]
}
```

---

## security-alerts.tf

```hcl
# ── SNS Topic sécurité ────────────────────────────────────────────

resource "aws_sns_topic" "security_alerts" {
  name              = "smart-assembly-security-alerts"
  kms_master_key_id = aws_kms_key.sns.id

  tags = {
    Project = "smart-assembly-line"
  }
}

resource "aws_sns_topic_subscription" "security_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = "lansana.conde.pro@gmail.com"
}

# ── Lambda — Remediation automatique GuardDuty HIGH ───────────────

resource "aws_lambda_function" "security_remediation" {
  function_name = "smart-assembly-security-remediation"
  handler       = "index.handler"
  runtime       = "python3.12"
  role          = aws_iam_role.security_remediation.arn
  timeout       = 60

  filename         = data.archive_file.security_remediation.output_path
  source_code_hash = data.archive_file.security_remediation.output_base64sha256

  environment {
    variables = {
      SNS_TOPIC_ARN   = aws_sns_topic.security_alerts.arn
      ECS_CLUSTER_ARN = aws_ecs_cluster.main.arn
    }
  }
}

# Code de la Lambda de remediation
# (inline via archive_file pour simplifier — en prod : S3 ou ECR)
```

### Code Python — Lambda de remediation

```python
import boto3
import json
import os

ecs = boto3.client('ecs')
ec2 = boto3.client('ec2')
sns = boto3.client('sns')

SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
ECS_CLUSTER_ARN = os.environ['ECS_CLUSTER_ARN']

def handler(event, context):
    finding = event['detail']
    finding_type = finding['type']
    severity = finding['severity']
    
    print(f"GuardDuty finding HIGH: {finding_type} (sévérité: {severity})")
    
    actions_taken = []
    
    # CryptoCurrency → stopper les tâches ECS suspectes
    if 'CryptoCurrency' in finding_type:
        affected_instance = finding.get('resource', {}).get('instanceDetails', {})
        if affected_instance:
            tasks = ecs.list_tasks(cluster=ECS_CLUSTER_ARN)['taskArns']
            for task_arn in tasks:
                ecs.stop_task(
                    cluster=ECS_CLUSTER_ARN,
                    task=task_arn,
                    reason=f"GuardDuty auto-remediation: {finding_type}"
                )
                actions_taken.append(f"Stopped ECS task: {task_arn}")
    
    # UnauthorizedAccess:IAMUser → désactiver la clé d'accès
    if 'UnauthorizedAccess:IAMUser' in finding_type:
        iam_user = finding.get('resource', {}).get('accessKeyDetails', {}).get('userName')
        if iam_user:
            iam = boto3.client('iam')
            access_key_id = finding['resource']['accessKeyDetails']['accessKeyId']
            iam.update_access_key(
                UserName=iam_user,
                AccessKeyId=access_key_id,
                Status='Inactive'
            )
            actions_taken.append(f"Disabled IAM key: {access_key_id} for user {iam_user}")
    
    # Toujours notifier via SNS avec les actions prises
    message = {
        'finding_type': finding_type,
        'severity': severity,
        'actions_taken': actions_taken,
        'account': event['account'],
        'region': event['region'],
        'time': event['time']
    }
    
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f'[AUTO-REMEDIATION] GuardDuty {finding_type}',
        Message=json.dumps(message, indent=2)
    )
    
    return {'statusCode': 200, 'actions_taken': actions_taken}
```

---

## Coût estimé Jour 47

```
SERVICE              USAGE                        COÛT/MOIS
──────────────────────────────────────────────────────────
GuardDuty            ~100K events CloudTrail/mois  ~4 €
                     ~500 Mo VPC Flow Logs/mois     ~1 €
Security Hub         2 standards × 100 checks      ~0 € (30j gratuits)
                     Après 30j : ~0.001$/check/mois ~1 €
AWS Config           ~50 ressources surveillées     ~3.50 €
                     5 règles actives               ~1 €
S3 Config bucket     ~100 Mo/mois                  ~0.002 €
Lambda remediation   Quelques invocations/mois      ~0 €
──────────────────────────────────────────────────────────
TOTAL SÉCURITÉ       Niveau dev                    ~10 €/mois

Rapport coût/bénéfice :
  10 €/mois de monitoring sécurité
  vs 1 incident de sécurité = pertes potentielles > 100 000 €
```

# Terraform — Architecture multi-région

> Code Terraform complet pour déployer l'architecture active/passive eu-west-3 → eu-central-1.

---

## Structure des fichiers

```
terraform/
├── providers.tf          ← providers multi-région
├── variables.tf          ← variables d'environnement
├── route53.tf            ← health checks + failover records
├── dynamodb-global.tf    ← Global Tables
├── s3-replication.tf     ← Cross-Region Replication
├── iam-replication.tf    ← rôles IAM pour CRR
└── outputs.tf            ← endpoints exposés
```

---

## providers.tf

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Région primaire (défaut)
provider "aws" {
  region = "eu-west-3"
  alias  = "primary"
}

# Région secondaire
provider "aws" {
  region = "eu-central-1"
  alias  = "secondary"
}

# Route 53 (global — toujours us-east-1)
provider "aws" {
  region = "us-east-1"
  alias  = "global"
}
```

---

## dynamodb-global.tf

```hcl
# Table principale avec réplication Global Tables
resource "aws_dynamodb_table" "machine_state_v2" {
  provider = aws.primary

  name             = "machine_state_v2"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "site_poste_id"
  range_key        = "sensor_type"

  # DynamoDB Streams — requis pour Global Tables
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "site_poste_id"
    type = "S"
  }
  attribute {
    name = "sensor_type"
    type = "S"
  }
  attribute {
    name = "statut"
    type = "S"
  }
  attribute {
    name = "site_id"
    type = "S"
  }

  global_secondary_index {
    name            = "statut-site-index"
    hash_key        = "statut"
    range_key       = "site_id"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb_primary.arn
  }

  # Réplica en région secondaire
  replica {
    region_name    = "eu-central-1"
    propagate_tags = true
  }

  tags = {
    Project     = "smart-assembly-line"
    Environment = var.environment
    Jour        = "46"
  }
}
```

---

## route53.tf

```hcl
# ── Health Check sur le ALB primaire ─────────────────────────────

resource "aws_route53_health_check" "primary_alb" {
  provider = aws.global

  fqdn              = aws_lb.primary.dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = "3"
  request_interval  = "30"

  # CloudWatch alarm optionnel si health check échoue
  cloudwatch_alarm_region = "eu-west-3"

  tags = {
    Name    = "smart-assembly-primary-alb"
    Project = "smart-assembly-line"
  }
}

# ── Zone Route 53 privée ──────────────────────────────────────────

resource "aws_route53_zone" "smart_assembly" {
  provider = aws.global
  name     = "smart-assembly.internal"

  # Zone privée — accessible uniquement depuis les VPCs associés
  vpc {
    vpc_id     = aws_vpc.primary.id
    vpc_region = "eu-west-3"
  }

  vpc {
    vpc_id     = aws_vpc.secondary.id
    vpc_region = "eu-central-1"
  }
}

# ── Record PRIMAIRE ───────────────────────────────────────────────

resource "aws_route53_record" "api_primary" {
  provider = aws.global

  zone_id        = aws_route53_zone.smart_assembly.zone_id
  name           = "api.smart-assembly.internal"
  type           = "A"
  set_identifier = "primary-eu-west-3"

  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary_alb.id

  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
}

# ── Record SECONDAIRE (failover) ──────────────────────────────────

resource "aws_route53_record" "api_secondary" {
  provider = aws.global

  zone_id        = aws_route53_zone.smart_assembly.zone_id
  name           = "api.smart-assembly.internal"
  type           = "A"
  set_identifier = "secondary-eu-central-1"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = aws_lb.secondary.dns_name
    zone_id                = aws_lb.secondary.zone_id
    evaluate_target_health = true
  }
}

# ── Alarme CloudWatch si failover déclenché ───────────────────────

resource "aws_cloudwatch_metric_alarm" "failover_triggered" {
  alarm_name          = "route53-failover-triggered"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "1"

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary_alb.id
  }

  alarm_description = "Route 53 health check primary ALB échoue — failover probable"
  alarm_actions     = [aws_sns_topic.alerts.arn]
  ok_actions        = [aws_sns_topic.alerts.arn]
}
```

---

## s3-replication.tf

```hcl
# ── Bucket source (eu-west-3) ─────────────────────────────────────

resource "aws_s3_bucket_versioning" "raw_data_primary" {
  provider = aws.primary
  bucket   = aws_s3_bucket.raw_data.id

  versioning_configuration {
    status = "Enabled"  # Requis pour CRR
  }
}

# ── Bucket destination (eu-central-1) ────────────────────────────

resource "aws_s3_bucket" "raw_data_replica" {
  provider = aws.secondary
  bucket   = "smart-assembly-raw-data-replica-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "raw_data_replica" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.raw_data_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "raw_data_replica" {
  provider = aws.secondary
  bucket   = aws_s3_bucket.raw_data_replica.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_INSTANT_RETRIEVAL"
    }
  }
}

# ── Règle de réplication CRR ──────────────────────────────────────

resource "aws_s3_bucket_replication_configuration" "raw_data" {
  provider = aws.primary
  bucket   = aws_s3_bucket.raw_data.id
  role     = aws_iam_role.s3_replication.arn

  depends_on = [aws_s3_bucket_versioning.raw_data_primary]

  rule {
    id     = "replicate-all-to-eu-central-1"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.raw_data_replica.arn
      storage_class = "STANDARD_IA"

      # Replication Time Control — garantit < 15 min (optionnel, surcoût)
      # replication_time {
      #   status = "Enabled"
      #   time { minutes = 15 }
      # }
    }
  }
}
```

---

## iam-replication.tf

```hcl
# Rôle IAM pour S3 Cross-Region Replication
resource "aws_iam_role" "s3_replication" {
  provider = aws.primary
  name     = "smart-assembly-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  provider = aws.primary
  name     = "s3-replication-policy"
  role     = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = [aws_s3_bucket.raw_data.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObjectVersionForReplication",
                    "s3:GetObjectVersionAcl",
                    "s3:GetObjectVersionTagging"]
        Resource = ["${aws_s3_bucket.raw_data.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ReplicateObject",
                    "s3:ReplicateDelete",
                    "s3:ReplicateTags"]
        Resource = ["${aws_s3_bucket.raw_data_replica.arn}/*"]
      }
    ]
  })
}
```

---

## outputs.tf

```hcl
output "primary_api_endpoint" {
  description = "Endpoint API région primaire (eu-west-3)"
  value       = "https://${aws_lb.primary.dns_name}"
}

output "secondary_api_endpoint" {
  description = "Endpoint API région secondaire (eu-central-1)"
  value       = "https://${aws_lb.secondary.dns_name}"
}

output "failover_dns" {
  description = "DNS avec failover automatique Route 53"
  value       = "api.smart-assembly.internal"
}

output "dynamodb_global_table_arn" {
  description = "ARN de la table DynamoDB Global Table"
  value       = aws_dynamodb_table.machine_state_v2.arn
}

output "health_check_id" {
  description = "ID du health check Route 53"
  value       = aws_route53_health_check.primary_alb.id
}
```

---

## Coût estimé du surcoût multi-région

```
COMPOSANT                   MONO-RÉGION    MULTI-RÉGION   DELTA
────────────────────────────────────────────────────────────────
DynamoDB (prod 10K WCU/s)   258 €/mois     604 €/mois    +346 €
ECS Fargate secondaire      0 €            11 €/mois     +11 €
ALB secondaire              0 €            7 €/mois      +7 €
NAT/VPC EP secondaire       0 €            14 €/mois     +14 €
Route 53 health check       0 €            0.75 €/mois   +0.75 €
S3 CRR (réplication 10Go)   0 €            0.23 €/mois   +0.23 €
────────────────────────────────────────────────────────────────
SURCOÛT TOTAL               —              ~379 €/mois   +379 €

Surcoût en % du total prod  : +21%
Justification ROI            : 1 heure d'arrêt évité = 40 000 €
                               Surcoût annuel = ~4 548 €
                               → Amorti en 7 minutes de production récupérée
```

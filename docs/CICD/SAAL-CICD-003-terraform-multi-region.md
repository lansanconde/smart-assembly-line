# Terraform — Infrastructure multi-région

Config Terraform pour la réplication DynamoDB et le failover Route 53.

---

## DynamoDB Global Tables

```hcl
resource "aws_dynamodb_table" "machine_state" {
  name         = "machine_state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "site_id"
  range_key    = "poste_id"

  replica {
    region_name = "eu-west-1"  # Irlande — secondaire
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }
}
```

---

## Route 53 Failover

```hcl
# Health check sur l'ALB primaire (Paris)
resource "aws_route53_health_check" "primary" {
  fqdn              = aws_lb.main.dns_name
  port              = 80
  type              = "HTTP"
  resource_path     = "/actuator/health"
  request_interval  = 30
  failure_threshold = 3
}

# Record primaire (Paris)
resource "aws_route53_record" "primary" {
  failover_routing_policy { type = "PRIMARY" }
  health_check_id = aws_route53_health_check.primary.id
}

# Record secondaire (Irlande) — activé si health check échoue
resource "aws_route53_record" "secondary" {
  failover_routing_policy { type = "SECONDARY" }
}
```

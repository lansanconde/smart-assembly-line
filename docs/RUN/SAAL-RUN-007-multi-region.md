# Runbook — Architecture multi-région

## Déploiement Global Tables + Route 53
```bash
cd terraform/environments/dev
terraform apply -target=aws_dynamodb_table.machine_state \
                -target=aws_route53_health_check.primary \
                -target=aws_route53_record.primary \
                -target=aws_route53_record.secondary
```

## Vérifier la réplication DynamoDB
```bash
aws dynamodb describe-table --table-name machine_state \
  --region eu-west-3 --query "Table.Replicas"
```

## Simuler failover
```bash
# Forcer health check en échec → Route 53 bascule vers eu-west-1
aws route53 update-health-check --health-check-id $HC_ID \
  --disabled   # à ne faire qu'en test
```

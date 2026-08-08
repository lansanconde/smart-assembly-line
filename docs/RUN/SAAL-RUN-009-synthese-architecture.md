# Runbook — Synthèse architecture

## État du système
```bash
# ECS
aws ecs describe-services --cluster smart-assembly-cluster \
  --services supervision-api --region eu-west-3 \
  --query 'services[0].{desired:desiredCount,running:runningCount}'

# API health
curl -s https://dv03heuf7nfn6.cloudfront.net/api/machines | jq length

# Coût estimé mois en cours
aws ce get-cost-forecast --time-period Start=2026-08-08,End=2026-09-01 \
  --metric BLENDED_COST --granularity MONTHLY --region eu-west-3
```

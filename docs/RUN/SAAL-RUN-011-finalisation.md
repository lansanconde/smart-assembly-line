# Runbook — Finalisation & Vérification globale

## Checklist déploiement complet

```bash
# 1. Terraform state OK
terraform show | grep -E "(aws_ecs|aws_cloudfront|aws_dynamodb)" | head -20

# 2. Portfolio accessible
curl -o /dev/null -s -w "%{http_code}" https://do1vmragia1j9.cloudfront.net

# 3. API accessible (si ECS démarré)
curl -s https://dv03heuf7nfn6.cloudfront.net/api/machines | jq length

# 4. DynamoDB réplication active
aws dynamodb describe-table --table-name machine_state \
  --query "Table.Replicas[*].{Region:RegionName,Status:ReplicaStatus}"

# 5. GuardDuty actif
aws guardduty list-detectors --region eu-west-3
```

## Git
```bash
git log --oneline -10   # vérifier les derniers commits
git status              # pas de fichiers non commités
```

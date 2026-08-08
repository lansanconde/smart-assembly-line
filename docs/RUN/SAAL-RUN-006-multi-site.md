# Runbook — Architecture multi-site

> Design uniquement — non déployé en production.

## Appliquer le modèle DynamoDB multi-site
```bash
terraform apply -target=aws_dynamodb_table.machine_state
```

La table `machine_state` utilise `site_id` (PK) + `poste_id` (SK).

## Tester le routage multi-site
```bash
aws dynamodb query \
  --table-name machine_state \
  --key-condition-expression "site_id = :s" \
  --expression-attribute-values '{":s":{"S":"toulouse"}}' \
  --region eu-west-3
```

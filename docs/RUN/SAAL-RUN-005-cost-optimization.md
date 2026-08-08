# Runbook — Gestion des coûts

## Arrêter ECS (économie ~$12/mois)
```powershell
& "C:\Users\conde\AppData\Local\Python\pythoncore-3.14-64\Scripts\aws.cmd" ecs update-service `
  --cluster smart-assembly-cluster --service supervision-api `
  --desired-count 0 --region eu-west-3 2>$null | Out-Null
```

## Relancer ECS (avant entretien)
```powershell
$td = (& "C:\...\aws.cmd" ecs describe-task-definition `
  --task-definition supervision-api --region eu-west-3 2>$null `
  | ConvertFrom-Json).taskDefinition.taskDefinitionArn
& "C:\...\aws.cmd" ecs update-service `
  --cluster smart-assembly-cluster --service supervision-api `
  --task-definition $td --desired-count 1 --region eu-west-3 2>$null | Out-Null
Write-Host "ECS redémarre — disponible dans ~2 minutes"
```

## Consulter les coûts du mois
```powershell
& "C:\...\aws.cmd" ce get-cost-and-usage `
  --time-period Start=2026-08-01,End=2026-09-01 `
  --granularity MONTHLY --metrics BlendedCost `
  --group-by Type=DIMENSION,Key=SERVICE `
  --filter '{"Dimensions":{"Key":"RECORD_TYPE","Values":["Usage"]}}' `
  --region eu-west-3 2>$null | ConvertFrom-Json
```

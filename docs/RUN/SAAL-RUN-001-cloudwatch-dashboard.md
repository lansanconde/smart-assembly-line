# Runbook — CloudWatch Dashboard

## Déploiement
```bash
cd terraform/environments/dev
terraform apply -target=aws_cloudwatch_dashboard.main
```

## Vérification
Console AWS → CloudWatch → Dashboards → `SmartAssemblyLine`

## Métriques custom publiées
Lambda `analyze_vibration` → `cloudwatch.put_metric_data(Namespace='SmartAssemblyLine', ...)`

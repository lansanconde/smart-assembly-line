# Runbook — X-Ray Tracing

## Déploiement
```bash
terraform apply -target=aws_xray_sampling_rule.analyze_vibration
```

## Vérifier les traces actives
```bash
aws xray get-trace-summaries \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --region eu-west-3
```

## Accès console
Console → X-Ray → Traces → Filter: `service("analyze_vibration")`

## Sampling actuel
| Fonction | Taux |
|----------|------|
| `analyze_vibration` | 10% |
| ECS `/api/machines` | 5% |

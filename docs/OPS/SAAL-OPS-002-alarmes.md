# CloudWatch Alarms — Alerting

Alertes automatiques → SNS → Email opérateur.

---

## Alarmes déployées

| Alarme | Condition | Seuil | Périodes |
|--------|-----------|-------|---------|
| `lambda-errors` | Lambda Errors > N | 5 erreurs | 2 × 1min |
| `lambda-throttles` | Throttles > N | 10 | 1 × 1min |
| `ecs-cpu-high` | ECS CPU > 80% | 80% | 3 × 1min |
| `alb-5xx` | ALB 5xx > N | 10 | 2 × 1min |
| `anomaly-rate` | AnomalyCount > N | 20/min | 1 × 1min |

---

## Flux d'alerte

```
ALARM state
    → SNS Topic (smart-assembly-alerts)
        → Email : lansana.conde.pro@gmail.com
        → [Prod] Slack / PagerDuty
```

---

## États

| État | Signification |
|------|--------------|
| `OK` | Métrique dans les seuils |
| `ALARM` | Seuil dépassé N périodes consécutives |
| `INSUFFICIENT_DATA` | Pas assez de données (service arrêté) |

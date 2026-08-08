# CloudWatch Dashboard

Vue unifiée de la santé du système en temps réel.

---

## Widgets déployés

| Widget | Métrique | Namespace |
|--------|---------|-----------|
| Lambda Invocations | Count | `AWS/Lambda` |
| Lambda Errors | Count | `AWS/Lambda` |
| Lambda Duration (P99) | Milliseconds | `AWS/Lambda` |
| DynamoDB Latency (P99) | Milliseconds | `AWS/DynamoDB` |
| ECS CPU | % | `AWS/ECS` |
| ECS Memory | % | `AWS/ECS` |
| ALB Request Count | Count | `AWS/ApplicationELB` |
| ALB 5xx Errors | Count | `AWS/ApplicationELB` |
| Custom — Anomalies/min | Count | `SmartAssemblyLine` |
| Custom — Vibration avg | Number | `SmartAssemblyLine` |

---

## Métriques custom (publiées par Lambda)

```python
cloudwatch.put_metric_data(
    Namespace='SmartAssemblyLine',
    MetricData=[
        {'MetricName': 'AnomalyCount', 'Value': 1, 'Unit': 'Count'},
        {'MetricName': 'VibrationAvg', 'Value': avg_vibration, 'Unit': 'None'}
    ]
)
```

---

## Accès

Console AWS → CloudWatch → Dashboards → `SmartAssemblyLine`

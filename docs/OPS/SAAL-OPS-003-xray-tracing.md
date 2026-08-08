# AWS X-Ray — Distributed Tracing

Trace le chemin d'une requête de IoT Core jusqu'à DynamoDB.

---

## Composants tracés

| Service | Instrumentation |
|---------|----------------|
| Lambda `analyze_vibration` | SDK X-Ray Python — segments auto |
| ECS Spring Boot | SDK X-Ray Java — `AWSXRayServletFilter` |
| DynamoDB | Subsegment auto via SDK AWS |
| S3 | Subsegment auto via SDK AWS |

---

## Exemple de trace

```
Trace: IoT Rule → Lambda [45ms]
  ├── DynamoDB PutItem     [8ms]  ✅
  ├── EventBridge Publish  [12ms] ✅
  └── S3 PutObject         [23ms] ✅
```

---

## Sampling

| Règle | Taux |
|-------|------|
| Default | 5% (1 req/s min) |
| `analyze_vibration` | 10% |
| `/api/machines` | 5% |

---

## Accès

Console AWS → X-Ray → Traces → filter: `service("supervision-api")`

# Smart Aerospace Assembly Line

> Supervision IoT temps réel d'une ligne d'assemblage aérospatiale — AWS `eu-west-3` · 100% Terraform · Event-driven  
> **Lansana CONDÉ** · [Portfolio](https://do1vmragia1j9.cloudfront.net) · [LinkedIn](https://www.linkedin.com/in/lansana-conde)

---

## Architecture

```
🏭 Edge (Atelier)
   Simulateur MQTT → Greengrass v2 (TinyML + buffer offline)
          │ MQTT/TLS 8883
          ▼
   AWS IoT Core — Rules Engine SQL · mTLS X.509
          │
    ┌─────┴──────┐
    ▼            ▼
Lambda           EventBridge → SQS + DLQ → Step Functions
analyze_vibration       │
    │                   ▼
    ├── DynamoDB    SNS → Email opérateur
    └── S3
          │
          ▼
   ECS Fargate — Spring Boot API :8080
          │
   ALB → CloudFront (dv03heuf7nfn6)

Observabilité : CloudWatch · X-Ray · GuardDuty · CloudTrail
DR            : DynamoDB Global Tables (eu-west-1) · Route 53 Failover
```

---

## Stack déployée

| Couche | Services |
|--------|---------|
| **Edge** | Greengrass v2, TinyML (Isolation Forest), buffer JSONL |
| **Ingestion** | IoT Core, Rules Engine, Device Shadow, mTLS X.509 |
| **Compute** | Lambda ×4, EventBridge, SQS+DLQ, Step Functions |
| **Data** | DynamoDB (Global Tables, KMS), S3 data lake |
| **API** | ECS Fargate Spring Boot, ALB multi-AZ, CloudFront ×2 |
| **Sécurité** | KMS CMK, IAM least privilege, GuardDuty, Security Hub, Config |
| **Observabilité** | CloudWatch, X-Ray, CloudTrail, SNS alerting |
| **IaC / CI/CD** | Terraform 100%, GitHub Actions (validate → test → apply) |
| **DR** | DynamoDB Global Tables eu-west-1, Route 53 Failover |

---

## Résilience

| Pattern | Implémentation |
|---------|---------------|
| Retry storm | Full Jitter reconnexion — reconnexions étalées sur 0–60s |
| Circuit Breaker | Greengrass CLOSED/OPEN/HALF_OPEN |
| Buffer offline | Greengrass JSONL local — replay à la reconnexion |
| Dead Letter Queue | SQS DLQ après 3 échecs + alarme CloudWatch |
| Orchestration retry | Step Functions backoff exponentiel |
| Failover géo | Route 53 → bascule eu-west-1 si Paris KO (RTO < 5min) |

---

## Métriques clés

| Métrique | Valeur |
|----------|--------|
| Latence end-to-end (capteur → alerte) | **104 ms** (X-Ray) |
| Taux succès reconnexion (chaos test) | 98% avec jitter |
| RTO | < 5 min |
| RPO | < 30 s |
| Coût infrastructure | ~$18–30/mois |

---

## URLs

| Service | URL |
|---------|-----|
| Portfolio | https://do1vmragia1j9.cloudfront.net |
| API supervision | https://dv03heuf7nfn6.cloudfront.net/api/machines |

---

## Structure du repo

```
smart-assembly-line/
├── src/
│   ├── lambda/              # analyze_vibration, store_metrics, sqs_processor...
│   ├── greengrass/          # EdgeFilter, AnomalyDetector, buffer local
│   ├── iot-simulator/       # publish_vibration.py (simulateur MQTT)
│   ├── supervision-api/     # Spring Boot Java 21
│   └── portfolio/           # HTML/CSS CloudFront
├── terraform/environments/dev/
│   ├── vpc.tf · iot.tf · lambda.tf · ecs.tf · alb.tf
│   ├── dynamodb.tf · s3.tf · sqs.tf · eventbridge.tf
│   ├── cloudfront-api.tf · cloudfront-expiry.tf
│   ├── cloudwatch.tf · cloudtrail.tf · kms.tf
│   └── step_functions.tf · greengrass.tf · kinesis.tf
├── docs/                    # MkDocs Material (ARCH · OPS · SEC · CICD · RES · INFRA · RUN)
├── mkdocs.yml
└── .github/workflows/       # CI/CD GitHub Actions
```

---

## Lancer en local

```bash
# Infrastructure
cd terraform/environments/dev && terraform init && terraform apply

# Simulateur IoT
pip install awsiotsdk && python src/iot-simulator/publish_vibration.py

# Tests Lambda
pip install pytest boto3 moto && pytest src/lambda/tests/

# API Spring Boot
cd src/supervision-api && ./mvnw spring-boot:run

# Documentation
pip install mkdocs-material && mkdocs serve
```

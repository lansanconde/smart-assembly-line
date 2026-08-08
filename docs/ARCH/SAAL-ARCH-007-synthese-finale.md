# Synthèse — Architecture complète

**Document de référence** — vue unique de tout le système déployé.

---

## Diagramme complet

```mermaid
flowchart TD
    subgraph EDGE["🏭 Edge — Atelier"]
        SIM[Python Simulator\n2s interval]
        GG[Greengrass v2\nTinyML · Buffer · Jitter]
        SIM -->|MQTT| GG
    end

    subgraph CLOUD["☁️ AWS eu-west-3"]
        IOT[IoT Core\nX.509 mTLS · Rules SQL]
        GG -->|MQTT TLS 8883| IOT

        subgraph COMPUTE["Compute"]
            LV[Lambda\nanalyze_vibration\nX-Ray traced]
            EB[EventBridge Bus]
            SQS[SQS + DLQ]
            SF[Step Functions\nWorkflow intervention]
            IOT --> LV & EB
            LV -->|anomalie| EB
            EB --> SQS --> SF
        end

        subgraph DATA["Data"]
            DDB[(DynamoDB\nmachine_state\nKMS encrypted)]
            S3[(S3 Data Lake)]
            LV --> DDB & S3
        end

        subgraph SERVE["Supervision"]
            ECS[ECS Fargate\nSpring Boot :8080\nPublic subnet]
            ALB[ALB\neu-west-3a/b]
            CF_API[CloudFront API\ndv03heuf7nfn6]
            CF_WEB[CloudFront Portfolio\ndo1vmragia1j9]
            DDB --> ECS --> ALB --> CF_API
        end

        subgraph OPS["Observabilité"]
            CW[CloudWatch\nDashboard · Alarms]
            XR[X-Ray\nTraces]
            GD[GuardDuty\nSecurity Hub]
        end
    end

    SNS[SNS → Email] --- SF
    ECS & LV --> CW & XR
```

---

## Stack déployée

| Catégorie | Services |
|-----------|---------|
| **IoT** | IoT Core, Greengrass v2, Device Shadow |
| **Compute** | Lambda (×4), EventBridge, SQS+DLQ, Step Functions |
| **Data** | DynamoDB Global Tables, S3 |
| **API** | ECS Fargate, ALB, CloudFront (×2) |
| **Sécurité** | KMS, IAM, GuardDuty, Security Hub, AWS Config |
| **Ops** | CloudWatch, X-Ray, SNS, CloudTrail |
| **IaC** | Terraform + GitHub Actions CI/CD |

---

## URLs de production

| Service | URL |
|---------|-----|
| Portfolio | https://do1vmragia1j9.cloudfront.net |
| API supervision | https://dv03heuf7nfn6.cloudfront.net/api/machines |

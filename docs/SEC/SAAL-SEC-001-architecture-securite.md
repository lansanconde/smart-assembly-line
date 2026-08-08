# Sécurité — Vue d'ensemble

---

## Réseau

```mermaid
flowchart TB
    subgraph VPC["VPC 10.10.0.0/16"]
        IGW[Internet Gateway]

        subgraph PUB_A["Subnet Public A — 10.10.1.0/24"]
            ALB[ALB :80]
            ECS[ECS Fargate\nassign_public_ip=true]
        end

        subgraph PUB_B["Subnet Public B — 10.10.3.0/24"]
            ALB_B[ALB — AZ b]
        end

        subgraph PRIV["Subnet Privé — 10.10.2.0/24"]
            LV[Lambda]
        end
    end

    INTERNET -->|HTTPS| IGW --> ALB
    ECS -->|ECR/DynamoDB via IGW| IGW
    LV -.->|VPC Endpoints optionnels| DDB[(DynamoDB)]
```

> NAT Gateway supprimée. ECS accède à ECR et DynamoDB via IGW (subnet public).

---

## IAM — Rôles déployés

| Rôle | Service | Permissions |
|------|---------|------------|
| `ecs-task-execution-role` | ECS | Pull ECR, write CloudWatch Logs |
| `supervision-api-task-role` | ECS (app) | DynamoDB read, KMS decrypt, CloudWatch read |
| `analyze-vibration-role` | Lambda | DynamoDB write, S3 put, EventBridge publish, X-Ray |
| `cf-expiry-role` | Lambda | ECS update-service, CloudFront update |

---

## Chiffrement

| Donnée | Mécanisme |
|--------|-----------|
| DynamoDB at rest | KMS CMK `7d2fd7d2...` |
| S3 at rest | KMS CMK |
| IoT transport | TLS 1.2 (mTLS X.509) |
| API transport | HTTPS (CloudFront → TLS) |

---

## IoT — Authentification devices

- Chaque device possède un certificat X.509 signé par AWS CA
- IoT Policy : `iot:Publish` sur `assembly-line/${iot:ClientId}/metrics` uniquement
- Révocation individuelle possible sans affecter les autres devices

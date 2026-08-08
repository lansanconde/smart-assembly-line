# Architecture globale

**Supervision IoT temps réel d'une ligne d'assemblage aérospatiale.**  
Déployé sur AWS `eu-west-3` (Paris) — 100% Terraform — event-driven.

---

## Flux bout en bout

```mermaid
flowchart LR
    subgraph EDGE["🏭 Edge"]
        SIM[Simulateur MQTT\nPython]
        GG[Greengrass v2\nTinyML + buffer local]
    end

    subgraph AWS["☁️ AWS — eu-west-3"]
        IOT[IoT Core\nRules Engine]
        LV[Lambda\nanalyze_vibration]
        EB[EventBridge]
        SQS[SQS + DLQ]
        SF[Step Functions]
        DDB[(DynamoDB\nmachine_state)]
        S3[(S3\ndata lake)]
        ECS[ECS Fargate\nSpring Boot API]
        ALB[ALB]
        CF[CloudFront]
        CW[CloudWatch · X-Ray · Alarms]
    end

    SIM -->|MQTT TLS| GG
    GG -->|agrégation| IOT
    IOT --> LV & EB
    LV --> DDB & S3
    EB --> SQS --> SF
    DDB --> ECS --> ALB --> CF
    LV & ECS --> CW
```

---

## Couches

| Couche | Rôle | Services |
|--------|------|----------|
| **Edge** | Collecte, filtrage, buffer offline | Greengrass v2, TinyML |
| **Ingestion** | Transport sécurisé, routage | IoT Core, Rules Engine |
| **Compute** | Détection anomalies, orchestration | Lambda, EventBridge, SQS, Step Functions |
| **Stockage** | État temps réel, archive | DynamoDB, S3 |
| **Supervision** | API REST opérateur | ECS Fargate, ALB, CloudFront |
| **Observabilité** | Métriques, traces, alertes | CloudWatch, X-Ray, SNS |

---

## Principes

- **Event-driven** : aucun polling — chaque message capteur déclenche le traitement
- **Least Privilege** : chaque service a son propre rôle IAM minimal
- **IaC 100%** : tout Terraform, zéro modification console AWS
- **Résilience** : SQS DLQ + Step Functions retry + Greengrass buffer offline

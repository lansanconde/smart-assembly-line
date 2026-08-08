# Consolidation — Vue end-to-end

Flux complet du capteur terrain jusqu'à l'opérateur.

---

## Flux nominal

```mermaid
sequenceDiagram
    participant C as Capteur (Simulateur)
    participant GG as Greengrass v2
    participant IOT as IoT Core
    participant LV as Lambda analyze_vibration
    participant DDB as DynamoDB
    participant EB as EventBridge
    participant SF as Step Functions
    participant API as ECS Spring Boot
    participant OPS as Opérateur

    C->>GG: MQTT local (2s)
    GG->>GG: TinyML + buffer
    GG->>IOT: MQTT TLS (agrégé)
    IOT->>LV: Rules Engine trigger
    LV->>DDB: PutItem (état + statut)
    alt Anomalie détectée
        LV->>EB: Publish event
        EB->>SF: Start execution
        SF->>OPS: SNS notification
    end
    OPS->>API: GET /api/machines
    API->>DDB: Scan / Query
    API->>OPS: JSON état postes
```

---

## Points de résilience

| Point | Mécanisme |
|-------|-----------|
| Coupure réseau edge | Greengrass buffer JSONL + reconnect Full Jitter |
| Lambda failure | SQS DLQ après 3 tentatives |
| ECS down | CloudFront cache + ALB health check |
| Région AWS down | DynamoDB Global Tables + Route 53 failover |
| Pic de trafic | EventBridge → SQS découple le burst |

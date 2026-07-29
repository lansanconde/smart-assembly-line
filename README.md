# Smart Aerospace Assembly Line — AWS Staff Architect Portfolio

> Système de supervision industrielle IoT temps réel sur AWS  
> Architecture event-driven · Edge computing · Résilience chaos-tested · 100 % Terraform  
> **Lansana CONDÉ** — Architecte logiciel Industrie 4.0 · [Portfolio](https://do1vmragia1j9.cloudfront.net) · [LinkedIn](https://www.linkedin.com/in/lansana-conde)

---

## Contexte

Simulation d'une ligne d'assemblage aérospatiale avec supervision en temps réel de capteurs industriels (vibration, température, pression). Le projet couvre l'ensemble du stack — de l'edge (Greengrass) jusqu'au DR multi-région (eu-central-1) — en passant par la détection d'anomalies, l'orchestration, l'observabilité et la sécurité avancée.

**Cible de scalabilité :** 100 000 capteurs · 1 000 événements/seconde · RTO < 5 min · RPO < 1 s

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  EDGE (Atelier industriel)                                        │
│  Capteurs MQTT → Greengrass v2 (EdgeFilter + TinyML + Buffer)    │
└──────────────────────┬───────────────────────────────────────────┘
                       │ MQTT over TLS — agrégation 100:1
┌──────────────────────▼───────────────────────────────────────────┐
│  INGESTION — AWS IoT Core eu-west-3                               │
│  Rules Engine SQL · Thing Groups / Certificats X.509             │
└──────┬───────────────┬──────────────────────────────────────────┘
       │               │
  IoT Rule         IoT Rule
       │               │
┌──────▼──────┐  ┌─────▼──────────────────────────────────────────┐
│  Kinesis    │  │  Compute — Axe 1 Core                           │
│  1000 evt/s │  │  Lambda (analyze_vibration · DetectAnomaly)     │
│  shards dim.│  │  EventBridge (bus SmartAssemblyLine)            │
└──────┬──────┘  │  SQS (InterventionQueue + DLQ)                  │
       │  ▲      │  Step Functions (InterventionWorkflow)           │
       └──┘      └──────────────────┬──────────────────────────────┘
  consumer                          │
  Lambda                     ┌──────▼──────────────────────────────┐
                              │  Data — Axe 2                       │
                              │  DynamoDB machine_state_v2          │
                              │  (Global Tables · PITR · KMS)       │
                              │  S3 raw-data lake (CRR · Glacier)   │
                              └──────────────────┬──────────────────┘
                                                 │ query
┌────────────────────────────────────────────────▼──────────────────┐
│  API & Supervision                                                  │
│  ECS Fargate supervision-api · ALB multi-AZ · Canary deployment   │
│  X-Ray sidecar daemon · CloudWatch · CloudTrail                   │
└────────────────────────────────────────────────────────────────────┘
                              │
                     Route 53 Failover
                              │
┌─────────────────────────────▼──────────────────────────────────────┐
│  DISASTER RECOVERY — eu-central-1 (Francfort)                      │
│  DynamoDB Global Tables Replica · S3 CRR · ECS Warm Standby       │
└────────────────────────────────────────────────────────────────────┘
```

📄 **[Diagramme complet interactif →](docs/architecture/synthese-finale.md)**

---

## Stack technique

| Couche | Services AWS |
|---|---|
| **Edge** | AWS IoT Greengrass v2, MQTT over TLS, TinyML (TensorFlow Lite) |
| **Ingestion** | AWS IoT Core, Rules Engine SQL, Thing Groups, Device Certificates |
| **Compute** | Lambda (Python), EventBridge, SQS + DLQ, Step Functions |
| **Data** | DynamoDB (Global Tables, GSI, TTL, PITR), S3 (CRR, Lifecycle), Kinesis |
| **API** | ECS Fargate (Spring Boot), ALB multi-AZ, ECR, API Canary |
| **Observabilité** | CloudWatch (Dashboard + Alarms), X-Ray (Distributed Tracing), CloudTrail |
| **Sécurité** | KMS CMK, IAM least privilege, VPC Endpoints, GuardDuty, Security Hub (FSBP + CIS), AWS Config |
| **CI/CD** | GitHub Actions, Terraform, Docker |
| **DR** | Route 53 Failover, DynamoDB Global Tables, S3 Cross-Region Replication |

---

## Patterns de résilience

| Pattern | Implémentation |
|---|---|
| **Idempotency** | Clé `id_mesure` sur Lambda + condition expression DynamoDB |
| **Retry + Backoff exponentiel** | Backoff avec jitter, max 3 tentatives, DLQ en sortie |
| **Dead Letter Queue** | SQS DLQ + alarme CloudWatch sur profondeur DLQ |
| **Circuit Breaker** | Step Functions — état « circuit ouvert » après N échecs |
| **Backpressure** | SQS rejet propre si backlog > seuil |
| **Edge Buffering** | Greengrass LocalBuffer si IoT Core indisponible |
| **Jitter reconnexion** | Reconnexion aléatoire 0-30s → évite le retry storm |
| **Canary Deployment** | ALB Weighted Target Groups 10% → rollback automatique si erreur |
| **Active/Passive DR** | Route 53 Failover + DynamoDB Global Tables (RPO < 1s) |

---

## Chaos Engineering — 5 scénarios testés

| # | Scénario | Résultat |
|---|---|---|
| 1 | **IoT Core Down 10 min** | Greengrass buffer local, 0 donnée perdue, reprise en 18s |
| 2 | **Lambda Concurrency Limit** | SQS absorbe, DLQ capture, alarme CloudWatch, 0 perte |
| 3 | **EventBridge Delay 30s** | Lambda directe non impactée, alertes différées seulement |
| 4 | **DynamoDB Throttling** | Retry backoff + DLQ, données sauvegardées, 0 perte |
| 5 | **Retry Storm (200 capteurs simultanés)** | Jitter étale la reconnexion sur 30s, 0 throttling IoT Core |

---

## Structure du repo

```
smart-assembly-line/
├── src/
│   ├── lambda/
│   │   ├── analyze_vibration/   # Détection anomalie (Python)
│   │   ├── detect_anomaly/      # Classification seuil
│   │   ├── log_intervention/    # Traçabilité S3
│   │   ├── sqs_processor/       # Consommateur SQS
│   │   ├── store_metrics/       # Métriques CloudWatch custom
│   │   └── tests/               # Tests unitaires pytest
│   ├── greengrass/
│   │   ├── analyzer.py          # EdgeFilter + LocalBuffer
│   │   ├── detector.py          # Détection locale TinyML
│   │   └── docker-compose.yml   # Stack edge locale
│   ├── iot-simulator/
│   │   ├── publish_vibration.py # Simulateur capteur MQTT
│   │   └── stress_test.py       # Test de charge
│   ├── supervision-api/         # Backend Spring Boot (Java)
│   └── portfolio/               # Portfolio CloudFront (HTML/CSS)
├── terraform/
│   └── environments/dev/        # Infrastructure complète IaC
│       ├── vpc.tf               # VPC + subnets + NAT
│       ├── iot.tf               # IoT Core + Things + Rules
│       ├── lambda.tf            # Lambda functions + layers
│       ├── dynamodb.tf          # Tables + GSI + autoscaling
│       ├── ecs.tf               # ECS Fargate + task definitions
│       ├── alb.tf               # ALB + target groups
│       ├── eventbridge.tf       # Bus + rules + targets
│       ├── sqs.tf               # Queues + DLQ
│       ├── step_functions.tf    # State machines
│       ├── kinesis.tf           # Streams + shards
│       ├── kms.tf               # CMK par service
│       ├── cloudwatch.tf        # Dashboard + Alarms
│       ├── cloudtrail.tf        # Audit trail
│       ├── canary.tf            # Weighted target groups
│       ├── s3.tf                # Buckets + lifecycle
│       └── ...
├── docs/                        # Documentation MkDocs Material
│   ├── architecture/            # Vue d'ensemble, synthèse, multi-site, multi-région
│   ├── observability/           # CloudWatch, CloudTrail, X-Ray
│   ├── security/                # GuardDuty, Security Hub, Config
│   ├── chaos/                   # Rapports chaos engineering
│   ├── cost/                    # CAPEX/OPEX/ROI
│   └── runbooks/                # Jour 40 → Jour 50
├── mkdocs.yml                   # Documentation Material for MkDocs
└── .github/workflows/ci.yml     # Pipeline CI/CD GitHub Actions
```

---

## Trade-offs documentés

### SQS vs Kinesis vs Kafka

- **SQS** → `InterventionQueue` : découplage simple, scaling auto, zéro opérationnel
- **Kinesis** → `SmartAssemblyLine-Sensors` : ordre garanti par shard, multi-consommateurs, rejeu
- **Kafka** → non retenu : coût d'exploitation non justifié à ce stade

### Lambda vs ECS

- **Lambda** → détection event-driven (scale à zéro, < 15 min, stateless)
- **ECS Fargate** → `supervision-api` toujours active (API REST, état en mémoire)

### DynamoDB vs RDS

- **DynamoDB** → latence < 10ms constant à l'échelle, scaling automatique
- **RDS** → justifié uniquement pour du reporting SQL complexe (hors scope actuel)

---

## Métriques défendables

| Métrique | Valeur |
|---|---|
| Capteurs actifs (cible) | 100 000 |
| Throughput après Greengrass | 500 msg/s (agrégation 100:1) |
| Latence end-to-end (vibration → alerte) | **104 ms** (mesuré X-Ray) |
| WCU DynamoDB prod | 12 000 WCU/s provisioned |
| RTO | < 5 minutes |
| RPO | < 1 seconde |
| Disponibilité cible | 99.99% |
| Coût infra prod | ~1 834 €/mois |
| ROI industriel | +69 700% (vs coût arrêts non planifiés) |

---

## Documentation

La documentation complète est générée avec **MkDocs Material** :

```bash
pip install mkdocs-material
mkdocs serve       # http://localhost:8000
mkdocs build       # génère le site statique
```

📚 **Documentation en ligne** : [GitHub Pages](https://github.com/lansanconde/smart-assembly-line.git)

---

## Setup local

### Prérequis

- AWS CLI configuré (`aws configure`)
- Terraform >= 1.5
- Python >= 3.11
- Java 21 + Maven (pour supervision-api)
- Docker

### Déployer l'infrastructure

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

### Lancer le simulateur IoT

```bash
pip install awsiotsdk
python src/iot-simulator/publish_vibration.py
```

### Lancer les tests Lambda

```bash
pip install pytest boto3 moto
pytest src/lambda/tests/
```

### Lancer l'API locale

```bash
cd src/supervision-api
./mvnw spring-boot:run
```

---

## Objectif

Ce projet est conçu pour répondre aux questions de **System Design niveau Staff Architect** :

> *"Design a real-time monitoring system for 100,000 industrial IoT sensors across multiple sites."*

---

*Projet fil rouge conçu pour démontrer une maîtrise opérationnelle de l'architecture AWS en contexte industriel critique — Industrie 4.0/5.0*

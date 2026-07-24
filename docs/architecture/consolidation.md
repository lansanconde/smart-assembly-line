# Consolidation des 3 Axes — Vue d'ensemble (Jour 35)

> Flux complet du système Smart Aerospace Assembly Line.
> Ce document relie les 3 axes forts (Core, Data, IoT) en une seule vue cohérente,
> avec les trade-offs, patterns de résilience et points de défaillance.

---

## 1. Flux bout en bout

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     SMART AEROSPACE ASSEMBLY LINE                        │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │                     AXE 3 — IoT Edge-to-Cloud                    │   │
│  │                                                                   │   │
│  │  Capteur physique                                                 │   │
│  │      │ MQTT 2s                                                    │   │
│  │      ▼                                                            │   │
│  │  Mosquitto (local, port 1883)                                     │   │
│  │      │                                                            │   │
│  │      ▼                                                            │   │
│  │  analyzer.py                                                      │   │
│  │      ├── TinyML (Isolation Forest)   ← detector.py               │   │
│  │      ├── Seuils statiques (WARN/CRITICAL)                         │   │
│  │      ├── Circuit Breaker (CLOSED/OPEN/HALF_OPEN)                 │   │
│  │      ├── Buffer JSONL (volume Docker)                             │   │
│  │      └── reconnect_loop() — Full Jitter                          │   │
│  │                   │                                               │   │
│  │                   │ MQTT TLS (WARN/CRITICAL/ANOMALY uniquement)  │   │
│  │                   ▼                                               │   │
│  │  AWS IoT Core                                                     │   │
│  │      ├── Device Shadow (état désiré ↔ état réel)                │   │
│  │      └── Rules Engine → Lambda                                   │   │
│  └───────────────────┬───────────────────────────────────────────── ┘   │
│                       │                                                  │
│  ┌────────────────────▼─────────────────────────────────────────────┐   │
│  │                    AXE 1 — Core Architecture                      │   │
│  │                                                                   │   │
│  │  Lambda AnalyzeVibration                                          │   │
│  │      ├── Évalue statut (OK/WARN/CRITICAL)                        │   │
│  │      ├── PutMetricData → CloudWatch (SmartAssemblyLine)          │   │
│  │      ├── PutEvents → EventBridge (anomalie.critique)             │   │
│  │      └── PutItem → DynamoDB (machine_state)                      │   │
│  │                                                                   │   │
│  │  EventBridge (smart-assembly-events)                              │   │
│  │      └── Règle → SQS (InterventionQueue)                         │   │
│  │                                                                   │   │
│  │  SQS → Lambda SQSProcessor                                       │   │
│  │      └── StartExecution → Step Functions                         │   │
│  │                                                                   │   │
│  │  Step Functions (InterventionWorkflow)                            │   │
│  │      ├── CircuitBreaker (EN_INTERVENTION ?)                      │   │
│  │      ├── LogIntervention (DynamoDB)                              │   │
│  │      └── NotifyTechnicien (SNS / future)                         │   │
│  └───────────────────┬───────────────────────────────────────────── ┘   │
│                       │                                                  │
│  ┌────────────────────▼─────────────────────────────────────────────┐   │
│  │                      AXE 2 — Data                                 │   │
│  │                                                                   │   │
│  │  DynamoDB (machine_state)                                         │   │
│  │      ├── État courant par poste (id_poste PK)                    │   │
│  │      ├── GSI statut-index (requêtes par statut)                  │   │
│  │      └── PITR activé (recovery point-in-time)                    │   │
│  │                                                                   │   │
│  │  S3 (smart-assembly-raw-data)                                     │   │
│  │      ├── Historique réglementaire (lifecycle 30j → IA → Glacier) │   │
│  │      └── Chiffrement KMS                                         │   │
│  │                                                                   │   │
│  │  Kinesis (smart-assembly-sensors)                                 │   │
│  │      └── Flux haute fréquence (1 000 events/s cible)             │   │
│  │                                                                   │   │
│  │  CloudWatch (SmartAssemblyLine)                                   │   │
│  │      ├── Métriques : Vibration, Temperature, Pression,           │   │
│  │      │               MessageCount, AnomalyScore                  │   │
│  │      ├── Dashboard : 6 panels temps réel                         │   │
│  │      ├── Alarms : vibration, temperature, ML, burst              │   │
│  │      └── Composite Alarm → SNS → Email                           │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Scénario de bout en bout — cas nominal

### Étape 1 : Capteur publie une mesure normale

```
publish_vibration_edge.py → Mosquitto:1883
Payload : {"id_poste": "poste_1", "vibration": 1.2, "temperature": 65.0, "pression": 3.5}
```

**Résultat attendu :**
- `analyzer.py` détecte statut=OK → event **filtré localement**, non transmis au cloud
- Log : `[EDGE] OK filtré — vib=1.2 temp=65.0`

### Étape 2 : Capteur publie une anomalie CRITICAL

```
Payload : {"id_poste": "poste_1", "vibration": 3.1, "temperature": 97.0, "pression": 4.5}
```

**Résultat attendu :**
- `analyzer.py` → statut=CRITICAL → CB CLOSED → publish IoT Core
- Log : `[CLOUD] [CLOSED] CRITICAL — vib=3.1 temp=97.0`

### Étape 3 : IoT Core → Lambda AnalyzeVibration

```
IoT Rule (SQL) : SELECT * FROM 'assembly-line/+/metrics' WHERE vibration > 1.5
→ Lambda invoquée
```

**Résultat attendu :**
- DynamoDB `machine_state` : `{id_poste: "poste_1", statut: "CRITICAL", vibration_last: "3.1"}`
- CloudWatch : `Vibration=3.1`, `MessageCount{Statut=CRITICAL}=1`
- EventBridge : event `anomalie.critique` publié sur `smart-assembly-events`

### Étape 4 : EventBridge → SQS → Step Functions

```
Règle : source = "smart-assembly.iot", detail-type = "anomalie.critique"
→ SQS InterventionQueue
→ Lambda SQSProcessor
→ Step Functions InterventionWorkflow
```

**Résultat attendu :**
- DynamoDB : `statut = "EN_INTERVENTION"`
- CloudWatch Logs `/aws/lambda/smart-assembly-log-intervention` : intervention loguée
- Circuit breaker DynamoDB : bloque les prochaines alertes pour ce poste

### Étape 5 : CloudWatch Alarm → SNS Email

```
Alarm vibration-critical : Maximum(Vibration, 60s) > 2.5 pendant 2 périodes
→ SNS Topic smart-assembly-alerts
→ Email lansana.conde.pro@gmail.com
```

**Résultat attendu :**
- Email reçu avec AlarmName, valeur observée, timestamp

---

## 3. Scénario bout en bout — cas dégradé (chaos)

### IoT Core indisponible

```
Réseau coupé → 3 échecs Lambda publish → CB OPEN
→ Buffer JSONL actif (events persistés sur volume Docker)
→ reconnect_loop() : Full Jitter (base=1s, max=60s)
→ Réseau revenu → HALF_OPEN → CLOSED → flush buffer
```

**Garantie** : zéro perte d'events WARN/CRITICAL, détection locale continue.

### Lambda throttling (Axe 1)

```
Limite concurrence atteinte → événement mis en file SQS (DLQ si N retries)
→ Backoff exponentiel SQS → re-traitement différé
```

### DynamoDB throttling (Axe 2)

```
Capacité on-demand : scaling automatique en quelques secondes
→ Retry Lambda avec backoff
→ Alerte CloudWatch sur WriteThrottleEvents
```

---

## 4. Trade-offs retenus

### SQS vs Kafka vs Kinesis

| Cas d'usage | Choix | Raison |
|-------------|-------|--------|
| Dispatch intervention (1 consommateur) | **SQS** | Simple, DLQ native, pas de rétention longue |
| Flux capteurs haute fréquence | **Kinesis** | Ordre, multi-consommateurs, rejeu |
| Bus d'événements métier | **EventBridge** | Pattern matching JSON, routing sans code |
| Multi-équipes, rétention longue | Kafka (non retenu) | Coût ops non justifié à ce stade |

### Lambda vs ECS

| Critère | Lambda | ECS |
|---------|--------|-----|
| Durée exécution | < 15 min ✅ | Longue durée |
| Avec état en mémoire | Non | ✅ |
| Scale à zéro | ✅ | Non |
| Détection anomalie | ✅ Lambda | — |
| Backend supervision | — | ✅ ECS (Semaine 6) |

### DynamoDB vs RDS

| Critère | DynamoDB | RDS |
|---------|----------|-----|
| Accès par clé (état temps réel) | ✅ | Possible |
| Requêtes relationnelles complexes | Limité | ✅ |
| Latence constante à l'échelle | ✅ | Variable |
| Ce projet | ✅ retenu | Reporting avancé uniquement |

---

## 5. Failure-first design — synthèse des 3 axes

| Composant | Échec | Récupération | Dégradation |
|-----------|-------|--------------|-------------|
| **IoT Core** | Réseau coupé | CB + reconnect jitter | Détection locale, buffer JSONL |
| **analyzer.py** | Exception Python | try/except, continue | Event perdu si non WARN/CRITICAL |
| **Lambda** | Throttling / timeout | Retry SQS + DLQ | Traitement différé, alerte CW |
| **EventBridge** | Délai routage | Retry natif 24h | Alerte si délai > seuil métier |
| **SQS** | Backlog massif | Scaling consommateur | DLQ, priorisation CRITICAL |
| **Step Functions** | Étape échouée | Retry par état + circuit CB | Mode intervention manuelle |
| **DynamoDB** | Throttling | Retry + on-demand scaling | Lecture cache |
| **CloudWatch** | Délai métriques | Eventual consistency 1-3 min | Dashboard légèrement en retard |
| **TinyML** | Warm-up incomplet | Seuils statiques en fallback | Détection ML inactive |

---

## 6. Chiffres clés du projet

| Métrique | Valeur | Justification |
|----------|--------|---------------|
| Fréquence capteurs | 1 mesure / 2s | 1 poste dev, scalable à 1/s en prod |
| Filtrage edge | ~60-70% | Seuls WARN/CRITICAL remontent |
| Warm-up TinyML | 200 mesures (~7min) | Isolation Forest, fenêtre 10 |
| Circuit Breaker | 3 failures / 30s recovery | Équilibre réactivité / stabilité |
| Jitter reconnexion | 0..60s (Full Jitter) | Anti retry storm 1 000 postes |
| Buffer survie | Volume Docker | Persisté entre redémarrages |
| CloudWatch alarms | 4 + 1 composite | Vibration, Temp, ML, Burst, Escalade |
| Rétention S3 | 30j Standard → IA → Glacier | Réglementaire aérospatial |

---

## 7. Services AWS utilisés — cartographie complète

### Axe 3 — IoT (Semaine 5)
- **AWS IoT Core** : broker MQTT managé, Rules Engine, Device Shadow
- **Mosquitto** (edge) : broker local Docker, filtrage avant IoT Core
- **analyzer.py + detector.py** : TinyML, circuit breaker, buffer JSONL

### Axe 1 — Core (Semaine 3)
- **Lambda** : AnalyzeVibration, DetectAnomaly, SQSProcessor, LogIntervention
- **EventBridge** : bus `smart-assembly-events`, règles de routage
- **SQS** : InterventionQueue + DLQ
- **Step Functions** : InterventionWorkflow (circuit breaker DynamoDB)

### Axe 2 — Data (Semaine 4)
- **DynamoDB** : machine_state (état temps réel), GSI statut-index, PITR
- **S3** : raw-data (historique réglementaire), lifecycle, chiffrement KMS
- **Kinesis** : smart-assembly-sensors (flux haute fréquence)
- **CloudWatch** : métriques custom, dashboard, alarms, composite alarm
- **SNS** : alerting email + (production) PagerDuty/Slack

### Infrastructure (Semaines 1-2)
- **VPC** : subnets public/privé, NAT Gateway, ALB
- **IAM** : rôles Lambda/IoT/Step Functions, permission boundaries, KMS
- **Terraform** : 100% IaC, environment dev

---

## 8. Ce qui reste (Semaines 6-8)

| Semaine | Contenu |
|---------|---------|
| S6 — Production | CloudTrail, CI/CD, ECS backend supervision, canary deploy |
| S7 — Architecture senior | HA multi-AZ, DR (RTO/RPO), cost optimization, multi-site 100k capteurs |
| S8 — Entretien | Examen blanc, system design oral, finalisation repo + portfolio MkDocs |

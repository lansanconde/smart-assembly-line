# Architecture multi-site — 100 000 capteurs

---

## Objectif

Faire évoluer l'architecture Smart Assembly Line d'un site unique (poste d'assemblage pilote) vers une architecture **multi-site industrielle** capable de supporter **100 000 capteurs** répartis sur plusieurs usines. C'est le passage du POC au système de production à l'échelle d'un groupe aérospatial (Airbus : 16 sites de production, Thales : 35 pays).

---

## 1. Limites de l'architecture actuelle (mono-site)

L'architecture actuelle supporte un site unique avec quelques postes :

```
Modèle actuel :
  Table DynamoDB : machine_state
  Partition key  : id_poste  (ex: "poste_1", "poste_2")
  Capteurs       : ~10 postes × 3 capteurs = 30 capteurs
  Throughput     : quelques WCU/RCU

Problèmes à l'échelle :
  ❌ Pas d'identifiant de site → impossible de distinguer
     "poste_1 de Paris" vs "poste_1 de Toulouse"
  ❌ Pas de partitionnement géographique → hot partition potentielle
  ❌ IoT Core : 1 seul Thing Registry → pas de segmentation par usine
  ❌ EventBridge : 1 seul bus → tous les events mélangés
  ❌ Pas de hiérarchie : capteur → poste → ligne → site → région
```

---

## 2. Hiérarchie industrielle cible

```
GROUPE (Airbus Group)
  └── RÉGION (Europe / Amérique du Nord / Asie)
        └── SITE (Toulouse / Hambourg / Mobile)
              └── LIGNE (Ligne A320 / Ligne A350)
                    └── POSTE (Poste assemblage fuselage #12)
                          └── CAPTEUR (vibration / température / pression)
```

**100 000 capteurs cible :**

```
16 sites × 6 lignes × 10 postes × ~100 capteurs/poste = 96 000 capteurs
Arrondi à 100 000 avec capteurs auxiliaires (environnement, énergie)
```

---

## 3. Adaptation du modèle de données DynamoDB

### 3.1 Schéma actuel (mono-site)

```
Table : machine_state
PK    : id_poste          (ex: "poste_1")

Attributs :
  statut              STRING  "EN_INTERVENTION" | "NOMINAL"
  anomalie_type       STRING  "PRESSION" | "VIBRATION" | "TEMPERATURE"
  temperature_last    NUMBER
  vibration_last      NUMBER
  pression_last       NUMBER
  timestamp_last      STRING  ISO 8601
  detect_last_timestamp STRING
```

**Problème :** `id_poste = "poste_1"` est ambigu à l'échelle multi-site.

### 3.2 Schéma multi-site — Option A : Clé composite

```
Table : machine_state
PK    : site_id#line_id#poste_id     (Partition Key — STRING)
SK    : sensor_type                  (Sort Key — STRING)

Exemple :
  PK = "TLS#A320#P12"    (Toulouse, Ligne A320, Poste 12)
  SK = "VIBRATION"

Attributs :
  site_id          STRING  "TLS"
  line_id          STRING  "A320"
  poste_id         STRING  "P12"
  sensor_type      STRING  "VIBRATION" | "TEMPERATURE" | "PRESSION"
  statut           STRING  "NOMINAL" | "EN_INTERVENTION" | "ALERTE"
  valeur_last      NUMBER  dernière mesure
  timestamp_last   STRING  ISO 8601
  anomalie_score   NUMBER  0.0 → 1.0 (ML)
  ttl              NUMBER  Unix timestamp (expiration automatique)
```

**Avantages :**
- `site_id#line_id#poste_id` distribue les écritures sur ~16 partitions différentes → pas de hot partition
- Sort key `sensor_type` permet de récupérer tous les capteurs d'un poste en 1 requête (`Query PK = "TLS#A320#P12"`)
- TTL natif DynamoDB pour expirer les anciennes données automatiquement

### 3.3 Schéma multi-site — Option B : GSI par site

```
Table : machine_state
PK    : poste_id          (ex: "TLS-A320-P12")
SK    : sensor_type

GSI 1 : site-index
  PK  : site_id           (ex: "TLS")
  SK  : timestamp_last    → permet de récupérer tous les postes d'un site triés par temps

GSI 2 : statut-index
  PK  : statut            (ex: "EN_INTERVENTION")
  SK  : site_id           → supervision globale de tous les incidents par site
```

**Usage GSI 1 :** "Donne-moi tous les postes du site Toulouse avec une alerte dans les 5 dernières minutes"

```python
response = dynamodb.query(
    TableName='machine_state',
    IndexName='site-index',
    KeyConditionExpression='site_id = :site AND timestamp_last > :t',
    ExpressionAttributeValues={
        ':site': {'S': 'TLS'},
        ':t': {'S': five_minutes_ago_iso}
    }
)
```

### 3.4 Schéma retenu pour la cible 100K capteurs

**Option A (clé composite) + GSI statut** — meilleur équilibre performance/coût :

```
Table : machine_state_v2
PK    : site_poste_id     "TLS#A320#P12"
SK    : sensor_type       "VIBRATION"

GSI   : statut-site-index
  PK  : statut            "EN_INTERVENTION"
  SK  : site_id           "TLS"

TTL   : ttl               (expiration données froides après 30 jours)
```

---

## 4. Dimensionnement à 100 000 capteurs

### 4.1 Hypothèses de charge

```
Capteurs                  : 100 000
Fréquence émission        : 1 mesure / 2 secondes par capteur
Throughput brut           : 100 000 / 2 = 50 000 mesures/seconde
```

### 4.2 IoT Core — Capacité

```
Messages MQTT entrants    : 50 000 msg/s
Taille moyenne message    : ~256 octets (JSON capteur)
Débit total               : 50 000 × 256 o = ~12.2 Mo/s

Limites IoT Core (AWS managed, eu-west-3) :
  Max messages/s          : 20 000/s par compte (soft limit — augmentable)
  → Nécessite une demande de quota augmenté AWS Support

Solution : Greengrass edge buffering
  Agrégation locale       : 100 capteurs → 1 message agrégé / 10s
  Throughput réduit       : 100 000 / 100 × 0.1 = 100 msg/s ← gérable
```

### 4.3 Lambda — Throughput

```
Invocations              : 100 msg/s (après agrégation Greengrass)
Durée moyenne            : 500ms
Concurrence nécessaire   : 100 × 0.5 = 50 invocations simultanées
Limite Lambda (default)  : 1 000 invocations concurrentes → OK
Reserved concurrency     : 100 (isoler analyze_vibration des autres fonctions)
```

### 4.4 DynamoDB — Capacité

```
Écritures :
  100 capteurs/poste × 1 000 postes × 1 update / 10s = 10 000 WCU/s
  1 item = ~500 octets = 1 WCU (arrondi à 1 Ko)
  → 10 000 WCU/s requis

Lectures :
  Dashboard de supervision : 100 queries/s × 10 items = 1 000 RCU/s
  (items < 4 Ko → 1 RCU par lecture fortement cohérente)

Mode recommandé : Provisioned + Auto Scaling (vs PAY_PER_REQUEST en dev)
  Raison : charge prévisible en prod → 3× moins cher qu'on-demand

  WCU provisioned : 12 000 (20% marge)   → ~234 €/mois
  RCU provisioned :  1 200 (20% marge)   → ~23 €/mois
  Stockage        : 100 000 × 500 o × 30 = ~1.5 Go → ~0.35 €/mois
  ───────────────────────────────────────────────────
  Total DynamoDB  :                        ~258 €/mois
```

### 4.5 S3 — Data Lake à l'échelle

```
Volume quotidien :
  50 000 msg/s × 256 o × 86 400 s = ~1 To/jour (brut)
  Après agrégation Greengrass (×100 réduc.) : ~10 Go/jour

Stockage 1 an   : 10 Go × 365 = ~3.65 To
Coût S3 Standard : 3.65 To × 0.023 $/Go = ~86 €/mois

Optimisation recommandée :
  Données > 30 jours → S3 Infrequent Access  (-45%)
  Données > 90 jours → S3 Glacier Instant    (-68%)
  → Économie potentielle : -60% sur le storage
```

### 4.6 Synthèse du dimensionnement

```
SERVICE              CHARGE              COÛT/MOIS (PROD 100K capteurs)
──────────────────────────────────────────────────────────────────────
IoT Core             50 000 msg/s        ~1 000 €
Lambda               100 invoc/s         ~150 €
DynamoDB             10K WCU / 1K RCU   ~258 €
S3 data lake         ~10 Go/jour         ~86 €
ECS Fargate (API)    4 tasks × 1 vCPU   ~175 €
ALB                  100K req/min        ~45 €
CloudWatch           Custom metrics      ~50 €
NAT / VPC Endpoints  Interface EP ×5    ~70 €
──────────────────────────────────────────────────────────────────────
TOTAL ESTIMÉ PROD    100 000 capteurs   ~1 834 €/mois (~22 000 €/an)

ROI vs arrêts ligne (16 sites × 40K €/arrêt × 2 arrêts/mois évités) :
  Économie mensuelle  : 1 280 000 €
  Coût infra          :     1 834 €
  ROI                 :    +69 700%
```

---

## 5. Partitionnement IoT Core multi-site

### Thing Groups par site

```
IoT Core Thing Hierarchy :
  / (root)
  ├── site-toulouse/
  │     ├── ligne-a320/
  │     │     ├── poste-1 (Thing)
  │     │     └── poste-2 (Thing)
  │     └── ligne-a350/
  ├── site-hambourg/
  └── site-mobile/
```

**Avantages des Thing Groups :**
- Policies IAM par groupe (un site ne peut écrire que dans son topic MQTT)
- Jobs Fleet : déployer un update Greengrass sur tous les postes d'un site en 1 opération
- Métriques Fleet Indexing : taux de connectivité par site

### Topics MQTT multi-site

```
Structure du topic :
  smart-assembly/{site_id}/{line_id}/{poste_id}/{sensor_type}

Exemples :
  smart-assembly/TLS/A320/P12/vibration
  smart-assembly/TLS/A320/P12/temperature
  smart-assembly/HAM/A350/P01/pression

IoT Rule pour capturer tous les sites :
  SELECT *, topic(2) AS site_id, topic(3) AS line_id,
           topic(4) AS poste_id, topic(5) AS sensor_type
  FROM 'smart-assembly/+/+/+/+'
```

---

## 6. Patterns d'architecture multi-site

### Pattern 1 — Hub & Spoke (actuel, adapté)

```
Sites (Spokes)                    Hub (Cloud AWS)
──────────────────                ─────────────────────────────
Toulouse  ──► Greengrass ──MQTT──► IoT Core (us region)
Hambourg  ──► Greengrass ──MQTT──►     │
Mobile    ──► Greengrass ──MQTT──►     ▼
                                   Lambda → DynamoDB central
                                   S3 data lake central
                                   API ECS → Dashboard global
```

**Adapté à :** < 5 sites, latence tolérable (50-100ms), budget optimisé.

### Pattern 2 — Multi-région active/passive (Jour 46)

```
Région primaire (eu-west-3)    Région secondaire (eu-central-1)
────────────────────────       ─────────────────────────────────
Sites Europe → IoT Core   ──►  Réplication DynamoDB Global Tables
                               Réplication S3 Cross-Region
                               Route 53 Failover automatique
```

**Adapté à :** exigences SLA > 99.99%, RTO < 5 minutes, contraintes réglementaires de résidence des données (RGPD, ITAR aérospatial).

### Pattern 3 — Edge Processing distribué (cible 100K capteurs)

```
Poste d'assemblage
  └── Greengrass v2
        ├── Composant : EdgeFilter (filtre bruit, pre-processing)
        ├── Composant : AnomalyDetector (ML local, TinyML)
        └── Composant : LocalBuffer (DynamoDB Streams local)
              │
              │ MQTT (uniquement les anomalies + agrégats)
              ▼
         IoT Core ──► Lambda ──► DynamoDB central
         (réduction 100:1 du trafic réseau)
```

**Avantage :** réduit le throughput IoT Core de 50 000 msg/s à ~500 msg/s, divise les coûts par ~100.

---

## 7. Concepts clés retenus

**Partitionnement DynamoDB** : la clé de partition `site_id#line_id#poste_id` distribue naturellement les écritures sur de nombreuses partitions, évitant le hot partition qui limiterait la capacité à 3 000 WCU par partition.

**Agrégation Greengrass** : à 100 000 capteurs, le traitement edge (local) n'est pas optionnel — c'est ce qui rend le système économiquement viable. Sans agrégation, le coût IoT Core seul dépasserait 10 000 €/mois.

**PAY_PER_REQUEST → Provisioned** : le seuil de bascule est approximativement 200 WCU/s. En dessous : PAY_PER_REQUEST. Au-dessus : Provisioned + Auto Scaling (3× moins cher à charge constante).

**Thing Groups** : la gestion de flotte (OTA updates, rotation certificats, monitoring de connectivité) est impossible sans hiérarchie Thing Groups. À 100K devices, c'est une nécessité opérationnelle.

**Topics MQTT hiérarchiques** : `smart-assembly/{site}/{ligne}/{poste}/{capteur}` permet des IoT Rules sélectives sans code supplémentaire — un wilcard `+` par niveau de hiérarchie.

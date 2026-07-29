# Architecture multi-région — Résilience géographique

---

## Objectif

Concevoir une architecture **active/passive multi-région** pour le Smart Assembly Line, garantissant une continuité de service même en cas de panne d'une région AWS complète. C'est l'étape suivante après le multi-site (Jour 45) : on passe de la résilience applicative (chaos engineering, retry storm) à la **résilience géographique**.

---

## 1. Contexte — Pourquoi le multi-région ?

### Limitations du mono-région

L'architecture actuelle tourne entièrement en `eu-west-3` (Paris) :

```
Risques d'une panne région complète :
  ❌ Panne datacenter AWS Paris (rare mais documenté : eu-west-1 Dec 2021)
  ❌ Coupure réseau régionale → 100% des capteurs déconnectés
  ❌ Incident AWS Service Health → DynamoDB, IoT Core, Lambda indisponibles
  ❌ Mise à jour Terraform échouée → infra en état incohérent

SLA AWS par service (région unique) :
  IoT Core    : 99.9%  → 8.7h d'indisponibilité/an
  DynamoDB    : 99.999% (multi-AZ dans une région)
  Lambda      : 99.95%
  ALB         : 99.99%

SLA cible Industrie 4.0 (aérospatial) : 99.99% → 52 min/an max
```

### Quand le multi-région est justifié

```
✓ SLA contractuel > 99.99% (clients Airbus/Thales)
✓ RTO (Recovery Time Objective) < 5 minutes
✓ RPO (Recovery Point Objective) < 30 secondes
✓ Contraintes réglementaires (résidence des données, ITAR)
✓ Sites géographiquement distribués sur plusieurs continents

✗ POC ou dev → mono-région suffit
✗ SLA 99.9% → multi-AZ dans une région suffit
✗ Budget < 500 €/mois → le surcoût multi-région n'est pas justifiable
```

---

## 2. Concepts fondamentaux

### RTO vs RPO

```
RPO (Recovery Point Objective) — Perte de données acceptable
  "Si on bascule vers la région secondaire maintenant,
   jusqu'à quand remontent nos données ?"

  Cible Smart Assembly Line : RPO < 30 secondes
  → DynamoDB Global Tables réplique en < 1 seconde entre régions
  → Aucune donnée capteur perdue en cas de failover

RTO (Recovery Time Objective) — Temps de reprise acceptable
  "Combien de temps entre la panne et le retour en service ?"

  Cible Smart Assembly Line : RTO < 5 minutes
  → Route 53 health check détecte la panne en ~60 secondes
  → DNS TTL 60s → clients redirigés vers région secondaire
  → ECS Fargate déjà actif en secondaire (warm standby)
```

### Active/Passive vs Active/Active

```
ACTIVE/PASSIVE (retenu pour ce projet)
  Région primaire   : eu-west-3 (Paris)    — 100% du trafic en conditions normales
  Région secondaire : eu-central-1 (Francfort) — en standby, prête à prendre le relais

  Avantages :
    ✓ Plus simple à opérer (une seule région "maître")
    ✓ Pas de conflit d'écriture entre régions
    ✓ Coût ~30% de plus (secondaire en warm standby)
    ✓ Suffisant pour RTO < 5 min

  Inconvénients :
    ✗ La région secondaire ne sert pas en production normale
    ✗ Latence légèrement supérieure si les utilisateurs sont proches de Francfort

ACTIVE/ACTIVE
  Les 2 régions servent du trafic simultanément
  → Lectures réparties géographiquement (latence réduite)
  → Écritures : nécessite une gestion de conflits (Last Write Wins en DynamoDB)

  Adapté à : applications globales (Netflix, gaming), pas au contrôle industriel
  → Non retenu : les capteurs d'une usine doivent avoir un seul "maître" d'écriture
```

---

## 3. Architecture cible — Active/Passive

```
┌─────────────────────────────────────────────────────────────────┐
│                        ROUTE 53                                  │
│  Failover Routing Policy                                         │
│  Health Check : HTTPS /health → ALB primaire (eu-west-3)        │
│  Failover : si primary DOWN → bascule vers secondary             │
└──────────────────┬─────────────────────┬────────────────────────┘
                   │                     │
        ┌──────────▼──────────┐ ┌────────▼────────────┐
        │   RÉGION PRIMAIRE   │ │  RÉGION SECONDAIRE  │
        │   eu-west-3 (Paris) │ │ eu-central-1 (FFT)  │
        │                     │ │                     │
        │  ALB ──► ECS        │ │  ALB ──► ECS        │
        │  (PRIMARY)          │ │  (WARM STANDBY)     │
        │         │           │ │         │           │
        │  IoT Core           │ │  IoT Core (replica) │
        │  Lambda             │ │  Lambda             │
        │         │           │ │         │           │
        │  DynamoDB ◄─────────┼─┼──► DynamoDB        │
        │  (MASTER)  Global   │ │    (REPLICA)        │
        │            Tables   │ │                     │
        │         │           │ │         │           │
        │  S3 ────────────────┼─┼──► S3 (CRR)        │
        │  (source)  Cross-   │ │    (replica)        │
        │            Region   │ │                     │
        └─────────────────────┘ └─────────────────────┘
```

---

## 4. DynamoDB Global Tables

### Fonctionnement

DynamoDB Global Tables réplique automatiquement les données entre régions avec une latence typique de **< 1 seconde**.

```
Principe :
  1. Table créée en eu-west-3 (région primaire)
  2. On ajoute eu-central-1 comme "replica region"
  3. Chaque écriture dans l'une est répliquée dans l'autre en < 1s
  4. En cas de failover, la région secondaire prend les écritures
     sans perte de données (RPO ≈ 0)

Gestion des conflits :
  Last Writer Wins (LWW) basé sur le timestamp de l'item
  → DynamoDB choisit l'écriture la plus récente
  → Acceptable pour notre use case (données temps réel de capteurs)
```

### Activation Terraform

```hcl
resource "aws_dynamodb_table" "machine_state_v2" {
  name             = "machine_state_v2"
  billing_mode     = "PAY_PER_REQUEST"
  hash_key         = "site_poste_id"
  range_key        = "sensor_type"

  # Activation Global Tables — réplication multi-région
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"  # requis pour Global Tables

  attribute {
    name = "site_poste_id"
    type = "S"
  }
  attribute {
    name = "sensor_type"
    type = "S"
  }
  attribute {
    name = "statut"
    type = "S"
  }
  attribute {
    name = "site_id"
    type = "S"
  }

  global_secondary_index {
    name            = "statut-site-index"
    hash_key        = "statut"
    range_key       = "site_id"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Région de réplication secondaire
  replica {
    region_name = "eu-central-1"
    # KMS optionnel : chiffrement avec une clé dans chaque région
    # kms_key_arn = aws_kms_key.dynamodb_eu_central.arn
  }

  tags = {
    Project     = "smart-assembly-line"
    Environment = "prod"
    Jour        = "46"
  }
}
```

### Coût Global Tables

```
Surcoût réplication :
  Chaque WCU écrite est facturée 2× (région primaire + région réplica)
  Trafic de réplication : 0.000105 $ / Ko répliqué

  Pour 10 000 WCU/s × 0.5 Ko moyen :
  Réplication : 10 000 × 0.5 × 0.000105 × 3600 × 24 × 30 = ~136 €/mois

  WCU primaire (provisioned) : ~234 €/mois
  WCU réplica (provisioned)  : ~234 €/mois
  Réplication data            : ~136 €/mois
  ─────────────────────────────────────────
  Total DynamoDB multi-région : ~604 €/mois (vs 258 € mono-région)
```

---

## 5. Route 53 — Failover Routing

### Principe

```
Route 53 surveille en permanence la santé du endpoint primaire.
Si la health check échoue → Route 53 bascule automatiquement le DNS
vers le endpoint secondaire (eu-central-1).

Health check frequency : 30 secondes (configurable)
DNS TTL                : 60 secondes
Temps de détection     : 30s (health check) + 60s (TTL propagation) = ~90s

RTO effectif : ~2-3 minutes (health check + TTL + connexion ECS secondaire)
```

### Terraform

```hcl
# Health check sur le ALB primaire
resource "aws_route53_health_check" "primary" {
  fqdn              = aws_lb.primary.dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = "3"
  request_interval  = "30"

  tags = {
    Name = "smart-assembly-primary-health"
  }
}

# Zone hébergée Route 53
data "aws_route53_zone" "main" {
  name = "smart-assembly.internal"
}

# Record PRIMAIRE (Failover PRIMARY)
resource "aws_route53_record" "api_primary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.smart-assembly.internal"
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier = "primary"
  health_check_id = aws_route53_health_check.primary.id

  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
}

# Record SECONDAIRE (Failover SECONDARY) — activé si primary DOWN
resource "aws_route53_record" "api_secondary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.smart-assembly.internal"
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier = "secondary"
  # Pas de health check sur le secondary — il prend tout si primary est down

  alias {
    name                   = aws_lb.secondary.dns_name
    zone_id                = aws_lb.secondary.zone_id
    evaluate_target_health = true
  }
}
```

---

## 6. S3 — Cross-Region Replication (CRR)

```hcl
# Bucket source (primaire — eu-west-3)
resource "aws_s3_bucket" "raw_data_primary" {
  bucket = "smart-assembly-raw-data-169237360990"
  # Versioning requis pour CRR
}

resource "aws_s3_bucket_versioning" "raw_data_primary" {
  bucket = aws_s3_bucket.raw_data_primary.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Bucket destination (réplica — eu-central-1)
resource "aws_s3_bucket" "raw_data_replica" {
  provider = aws.eu_central_1
  bucket   = "smart-assembly-raw-data-replica-169237360990"
}

resource "aws_s3_bucket_versioning" "raw_data_replica" {
  provider = aws.eu_central_1
  bucket   = aws_s3_bucket.raw_data_replica.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Règle de réplication
resource "aws_s3_bucket_replication_configuration" "raw_data" {
  bucket = aws_s3_bucket.raw_data_primary.id
  role   = aws_iam_role.s3_replication.arn

  rule {
    id     = "replicate-all"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.raw_data_replica.arn
      storage_class = "STANDARD_IA"  # Moins cher pour le réplica
    }
  }
}
```

**Latence de réplication S3 :** S3 Replication Time Control (RTC) garantit 99.99% des objets répliqués en < 15 minutes. Sans RTC, la réplication est asynchrone (quelques secondes à quelques minutes).

---

## 7. IoT Core — Multi-région

IoT Core **n'est pas répliqué automatiquement**. Deux stratégies existent :

### Stratégie A — Greengrass avec fallback (retenue)

```
Greengrass sur chaque site configure 2 endpoints IoT Core :
  Primary   : iot.eu-west-3.amazonaws.com
  Secondary : iot.eu-central-1.amazonaws.com

En cas de panne de eu-west-3, Greengrass bascule automatiquement
vers eu-central-1 (configuré dans greengrassv2/config.yaml).

Avantage : transparent pour les capteurs (pas de reconfiguration)
```

### Stratégie B — DNS-based routing

```
Custom domain IoT Core : iot.smart-assembly.internal
Route 53 Failover → bascule vers endpoint secondaire
Nécessite un domaine custom IoT Core (AWS IoT Custom Domain)
```

---

## 8. Contraintes réglementaires

### RGPD — Résidence des données (UE)

```
eu-west-3 (Paris) et eu-central-1 (Francfort) sont toutes deux
en territoire UE → pas de transfert hors UE → RGPD compatible.

Si on ajoutait us-east-1 : nécessiterait un Data Processing Agreement
et potentiellement des clauses contractuelles types (SCCs).
```

### ITAR — International Traffic in Arms Regulations

```
Pertinent pour la défense/aérospatial militaire (Airbus Defence, Thales).

Contraintes ITAR :
  ✓ Données accessibles uniquement à des ressortissants US ou UE habilités
  ✓ Chiffrement obligatoire (KMS CMK → ✓ déjà en place)
  ✓ Audit trail complet (CloudTrail → ✓ déjà en place)
  ✗ Hébergement hors OTAN → risque de non-conformité

Solution : AWS GovCloud (us-gov-west-1) pour les données ITAR sensibles,
ou AWS Secret Region (C2S/C2E) pour les programmes classifiés.
→ Hors scope Smart Assembly Line (usage civil aérospatial)
```

### Conformité NIS2 (Directive EU 2022/2555)

```
Applicable aux opérateurs de services essentiels (OSE) en EU,
dont les infrastructures industrielles critiques.

Exigences NIS2 :
  ✓ Chiffrement au repos et en transit (KMS + TLS → ✓)
  ✓ Journalisation et monitoring (CloudTrail + CloudWatch → ✓)
  ✓ Plan de continuité d'activité (ce document → ✓)
  ✓ Notification d'incident < 24h (SNS Alerting → ✓ partiellement)
  ✓ Tests réguliers de plan de reprise (chaos engineering → ✓)
```

---

## 9. Runbook de basculement (Failover Playbook)

### Failover automatique (nominal)

```
T+0s   : Panne détectée — ALB eu-west-3 ne répond plus
T+30s  : Route 53 health check échoue (3 checks × 10s)
T+90s  : DNS TTL expire → clients résolvent vers eu-central-1
T+120s : ECS Fargate secondaire prend le trafic (déjà chaud)
T+180s : DynamoDB Global Tables → déjà synchronisé (RPO ≈ 0)
─────────────────────────────────────────────────────────────
RTO effectif : ~3 minutes ✓ (objectif < 5 min)
RPO effectif : < 1 seconde ✓ (objectif < 30s)
```

### Failback (retour sur la région primaire)

```powershell
# 1. Vérifier que eu-west-3 est revenue
aws elbv2 describe-target-health \
  --target-group-arn <arn-tg-primary> \
  --region eu-west-3

# 2. Vérifier la santé DynamoDB
aws dynamodb describe-table \
  --table-name machine_state_v2 \
  --region eu-west-3

# 3. Route 53 re-bascule automatiquement dès que la health check repasse
# (pas d'action manuelle requise si Failover Routing est configuré)

# 4. Vérifier la résolution DNS
nslookup api.smart-assembly.internal
# Doit retourner l'IP du ALB eu-west-3
```

---

## 10. Concepts clés retenus

**RTO vs RPO** : deux métriques distinctes. RTO = temps de reprise (combien de temps on est HS). RPO = perte de données acceptée (jusqu'à quand nos données remontent). En contrôle industriel, le RPO est souvent plus critique que le RTO.

**Active/Passive vs Active/Active** : l'active/passive est adapté quand les écritures doivent avoir un seul maître (contrôle industriel, IoT). L'active/active est adapté pour les lectures géographiquement distribuées (CDN, apps web globales).

**DynamoDB Global Tables** : la réplication est automatique, sub-seconde, et basée sur Last Write Wins. Le surcoût est ~2.3× par rapport au mono-région à cause de la double facturation WCU + le trafic de réplication.

**Route 53 Failover** : le DNS ne bascule pas instantanément — il faut additionner le temps de détection (health check × threshold) + le TTL DNS. Sur l'Internet public, des caches DNS peuvent retarder la propagation.

**S3 CRR** : la réplication est asynchrone par défaut. Pour un RPO strict, utiliser S3 Replication Time Control (RTC) qui garantit < 15 minutes avec un SLA.

**Greengrass multi-endpoint** : les capteurs IoT ne parlent pas directement à IoT Core — ils passent par Greengrass qui gère le failover de connexion. C'est la couche de résilience côté edge.

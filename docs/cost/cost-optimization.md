# Cost Optimization — Smart Assembly Line

---

## Objectif

Comprendre les modèles de coût AWS, justifier les choix d'architecture sur le plan financier (CAPEX/OPEX/ROI), et identifier des leviers d'optimisation concrets pour le projet Smart Assembly Line.

---

## 1. CAPEX vs OPEX — Le changement de paradigme cloud

### Infrastructure traditionnelle (CAPEX)

**CAPEX** (Capital Expenditure) = dépenses en capital, investissements immobilisés.

```
Exemple datacenter on-premise :
  Serveurs physiques          : 50 000 €  (amortis sur 5 ans)
  Licences OS / middleware     : 15 000 €
  Réseau, câblage, baies      : 20 000 €
  Maintenance annuelle         : 10 000 €/an
  ─────────────────────────────────────────
  Coût initial                 : 85 000 €
  → Immobilisé au bilan, dépréciation comptable
  → Payé AVANT de savoir si le projet réussit
  → Capacité dimensionnée pour le pic, gaspillée 80% du temps
```

**Problèmes :**
- Risque financier élevé sur des décisions à long terme
- Sur-dimensionnement systématique (prévoir la charge de pointe x3)
- Délai d'approvisionnement : 3 à 6 mois
- Impossible de réduire la capacité si la demande baisse

### Cloud AWS (OPEX)

**OPEX** (Operational Expenditure) = dépenses opérationnelles, charges courantes.

```
Même système sur AWS :
  Pay-as-you-go               : 0 € fixe
  Facturation à la seconde     : ECS Fargate, Lambda
  Facturation à la requête     : DynamoDB PAY_PER_REQUEST
  Arrêt = 0 coût              : pas de tâche ECS = 0 €
  ─────────────────────────────────────────
  Coût initial                 : 0 €
  → Dépense opérationnelle mensuelle, pas d'immobilisation
  → Payé seulement ce qui est consommé
  → Scalé automatiquement selon la demande réelle
```

**Avantages OPEX :**

| Dimension | CAPEX (on-premise) | OPEX (AWS) |
|---|---|---|
| Investissement initial | Élevé (85 000 €+) | Zéro |
| Risque financier | Haut (amortissement 5 ans) | Faible (mensuel) |
| Délai mise en prod | 3-6 mois | Minutes |
| Capacité inutilisée | Payée quand même | Non facturée |
| Scalabilité | Manuelle, lente | Automatique, secondes |
| Comptabilité | Bilan (actif immobilisé) | Compte de résultat (charges) |

!!! tip "Argument clé en entretien"
    Le passage CAPEX → OPEX n'est pas qu'un choix technique. C'est un **choix financier** qui réduit le risque, améliore la trésorerie, et permet l'expérimentation sans immobilisation de capital.

---

## 2. Modèles de tarification AWS

### 2.1 Pay-as-you-go (à la consommation)

Principe : tu paies exactement ce que tu utilises, à la seconde ou à la requête.

```
Services du projet utilisés en pay-as-you-go :
  Lambda      → facturation par invocation + durée (ms)
  DynamoDB    → PAY_PER_REQUEST : facturation par lecture/écriture
  SQS         → par million de messages
  IoT Core    → par message MQTT transmis
  S3          → par Go stocké + par requête
  CloudWatch  → par métrique custom, par log ingéré
```

**Adapté à :** charges variables, pics imprévisibles, phases de développement.

### 2.2 Reserved Instances / Savings Plans

Principe : engagement de 1 ou 3 ans en échange d'une réduction 30-72%.

```
Exemple ECS Fargate Savings Plan :
  On-demand  : 0.04048 $/vCPU-heure
  1 an Savings Plan : 0.02658 $/vCPU-heure  → -34%
  3 ans Savings Plan : 0.01672 $/vCPU-heure  → -59%
```

**Types de Savings Plans :**

| Type | Flexibilité | Réduction |
|---|---|---|
| **Compute Savings Plan** | EC2 + Fargate + Lambda (toute région, tout OS) | Jusqu'à 66% |
| **EC2 Instance Savings Plan** | Instance family fixe, région fixe | Jusqu'à 72% |
| **Lambda Savings Plan** | Lambda uniquement | Jusqu'à 17% |

**Adapté à :** workloads stables, production rodée, baseline connue.

### 2.3 Spot Instances

Principe : utiliser la capacité EC2 non réservée d'AWS avec jusqu'à 90% de réduction. Peuvent être interrompus avec 2 minutes de préavis.

```
Usage dans notre contexte :
  ✓ Batch processing IoT (non temps-réel)
  ✓ Jobs de ML/analyse historique
  ✗ supervision-api (temps-réel, interruption inacceptable)
  ✗ ECS Fargate (Spot Fargate possible mais avec fallback on-demand)
```

### 2.4 Free Tier & Always Free

Services AWS avec tier gratuit permanent :

| Service | Free Tier |
|---|---|
| Lambda | 1M invocations/mois + 400 000 Go-secondes |
| DynamoDB | 25 Go stockage + 25 WCU + 25 RCU |
| SQS | 1M requêtes/mois |
| CloudWatch | 10 métriques custom, 5 Go logs |
| IoT Core | 250 000 messages/mois |

---

## 3. ROI — Return on Investment

### Formule

```
ROI = (Gain net / Coût de l'investissement) × 100

Gain net = Valeur générée - Coût total
```

### Application au Smart Assembly Line

```
Scénario : ligne d'assemblage aérospatiale, 50 postes

Coût AVANT (maintenance manuelle anomalies) :
  Arrêts non planifiés         : 8 h/mois × 5 000 €/h = 40 000 €/mois
  Techniciens maintenance réactive : 2 ETP × 3 500 €/mois = 7 000 €/mois
  Total coût actuel            : 47 000 €/mois

Coût APRÈS (Smart Assembly Line sur AWS) :
  Infrastructure AWS           : ~450 €/mois  (estimation ci-dessous)
  Développement (amorti 12 mois): 5 000 €/mois
  Total coût solution          : ~5 450 €/mois

Gain net mensuel             : 47 000 - 5 450 = 41 550 €/mois
ROI annuel                   : (41 550 × 12) / (5 450 × 12) × 100 = +762%
Payback period               : ~2 mois
```

!!! warning "ROI en entretien"
    Ne jamais citer un ROI sans expliquer les hypothèses. Un recruteur Airbus/Thales demandera toujours "sur quelle base ?". Savoir défendre ses chiffres est aussi important que le chiffre lui-même.

---

## 4. Estimation du coût mensuel — Smart Assembly Line

Hypothèses : environnement dev, eu-west-3 (Paris), usage modéré.

### Calcul détaillé

```
SERVICE              USAGE                        COÛT ESTIMÉ/MOIS
─────────────────────────────────────────────────────────────────────
ECS Fargate
  supervision-api    0.25 vCPU × 0.5 Go × 730h   ~11 €
  (1 task permanente)

Lambda
  analyze_vibration  ~100K invocations × 500ms    ~0.50 €
  detect_anomaly     ~50K invocations × 300ms     ~0.20 €
  → dans Free Tier (< 1M invocations)              ~0 €

DynamoDB
  machine_state      PAY_PER_REQUEST               < 1 €
  → dans Free Tier (25 Go, 25 RCU/WCU)            ~0 €

S3 (raw-data lake)
  Stockage           ~1 Go/mois (IoT events)      ~0.02 €
  Requêtes           ~10K PUT + 5K GET            ~0.01 €

IoT Core
  Messages MQTT      ~500K messages/mois          ~0.75 €
  → dans Free Tier (250K/mois gratuits)

EventBridge
  Events             ~200K events/mois            ~0.02 €
  → dans Free Tier (premier million gratuit)       ~0 €

SQS (DLQ + queues)
  Messages           ~50K/mois                    ~0 €
  → dans Free Tier (1M/mois)

Step Functions
  State transitions  ~5K transitions/mois         ~0.01 €
  → dans Free Tier (4K gratuits/mois)

CloudWatch
  Métriques custom   ~15 métriques                ~4.50 €
  Logs               ~500 Mo ingérés/mois         ~0.25 €
  Dashboard          1 dashboard                  ~3.00 €

ALB
  Fixe               0.008 $/h × 730h            ~6.50 €
  LCU                usage modéré                ~1.00 €

ECR
  Stockage image     ~500 Mo                     ~0.05 €

CloudFront (Portfolio)
  Données            ~1 Go/mois                  ~0.08 €
  Requêtes           ~10K requêtes               ~0.01 €

S3 (Portfolio)
  Stockage           ~5 Mo                       ~0.00 €

KMS CMK
  Clé               1 clé                        ~1.00 €
  Requêtes API      ~10K requêtes               ~0.03 €

VPC (NAT Gateway)
  Fixe               0.045 $/h × 730h            ~36 €  ← poste principal
  Trafic             ~1 Go/mois                  ~0.05 €

─────────────────────────────────────────────────────────────────────
TOTAL ESTIMÉ (dev, usage modéré)                  ~65 €/mois
─────────────────────────────────────────────────────────────────────
```

!!! note "Poste de coût principal"
    Le **NAT Gateway** représente ~55% du budget (~36 €/mois). C'est le levier n°1 d'optimisation en dev.

---

## 5. Leviers d'optimisation identifiés

### Levier 1 — Supprimer le NAT Gateway en dev (-36 €/mois, -55%)

**Problème :** Le NAT Gateway est nécessaire pour que les tâches ECS dans le subnet privé accèdent à ECR, DynamoDB, et CloudWatch. En production c'est justifié (sécurité). En dev, c'est le coût dominant.

**Solution :** Remplacer le NAT Gateway par des **VPC Endpoints** (Interface Endpoints) pour les services AWS utilisés.

```hcl
# VPC Endpoints — accès privé sans NAT Gateway
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.eu-west-3.ecr.api"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [aws_subnet.private.id]
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.eu-west-3.ecr.dkr"
  vpc_endpoint_type = "Interface"
  # ...
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.eu-west-3.dynamodb"
  vpc_endpoint_type = "Gateway"  # Gateway endpoint = GRATUIT
  route_table_ids   = [aws_route_table.private.id]
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.eu-west-3.s3"
  vpc_endpoint_type = "Gateway"  # Gateway endpoint = GRATUIT
  route_table_ids   = [aws_route_table.private.id]
}
```

**Économie :**

| Approche | Coût/mois |
|---|---|
| NAT Gateway (actuel) | ~36 € |
| VPC Endpoints Interface (ECR×2 + CW + STS) | ~14 € |
| VPC Endpoints Gateway (DynamoDB + S3) | 0 € |
| **Économie nette** | **~22 €/mois (-33% du total)** |

### Levier 2 — Fargate Spot pour les tâches non critiques (-50% sur Fargate)

**Problème :** La tâche `supervision-api` tourne en Fargate on-demand 24/7. Pour l'environnement de dev, une interruption de 2 minutes est acceptable.

**Solution :** Utiliser **FARGATE_SPOT** comme stratégie de capacity provider avec fallback on-demand.

```hcl
resource "aws_ecs_service" "supervision_api" {
  # ...
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
    base              = 0
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 0
    base              = 1   # au moins 1 task on-demand garantie
  }
}
```

**Économie :**

| Approche | Coût/mois |
|---|---|
| Fargate on-demand (actuel) | ~11 € |
| Fargate Spot (70% du temps) | ~5 € |
| **Économie nette** | **~6 €/mois** |

!!! warning "Ne pas utiliser Spot en production"
    En production, l'interruption Spot est inacceptable pour une API temps-réel. Ce levier ne s'applique qu'au développement et aux tests.

### Résumé des optimisations

```
ÉTAT ACTUEL         : ~65 €/mois
Levier 1 (VPC EP)  : -22 €/mois
Levier 2 (Spot)    : - 6 €/mois
─────────────────────────────────
APRÈS OPTIMISATION  : ~37 €/mois  (-43%)
```

---

## 6. Outils de gestion des coûts AWS

### AWS Cost Explorer

Interface web pour analyser les coûts historiques et faire des prévisions.

```powershell
# Coût du mois en cours par service
aws ce get-cost-and-usage `
  --time-period Start=2026-07-01,End=2026-07-31 `
  --granularity MONTHLY `
  --metrics BlendedCost `
  --group-by Type=DIMENSION,Key=SERVICE `
  --region eu-west-3
```

### AWS Budgets — Alerte si dépassement

```hcl
resource "aws_budgets_budget" "monthly" {
  name         = "smart-assembly-monthly-budget"
  budget_type  = "COST"
  limit_amount = "100"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["lansana.conde.pro@gmail.com"]
  }
}
```

### AWS Pricing Calculator

Outil en ligne : [calculator.aws](https://calculator.aws)  
Permet d'estimer avant de déployer, de comparer régions, et d'exporter en PDF pour justifier un budget.

---

## 7. Concepts clés retenus

**CAPEX vs OPEX** : le cloud transforme des investissements immobilisés (CAPEX) en charges opérationnelles (OPEX). Cela réduit le risque financier et améliore la trésorerie, particulièrement critique en aérospatial où les cycles projet sont longs.

**Pay-as-you-go** : DynamoDB PAY_PER_REQUEST est le modèle idéal pour des workloads imprévisibles. En production stable, passer à Provisioned + Auto Scaling peut diviser le coût par 3.

**Savings Plans vs Reserved Instances** : les Savings Plans sont plus flexibles (s'appliquent à Fargate + Lambda + EC2) et recommandés pour les architectures modernes conteneurisées.

**NAT Gateway = coût caché dominant** : en dev, c'est systématiquement le premier poste à optimiser via VPC Endpoints Gateway (gratuits pour S3 et DynamoDB).

**ROI industriel** : en Industrie 4.0, le ROI se mesure principalement par la réduction des arrêts non planifiés. Un arrêt de ligne coûte 5 000 à 50 000 €/heure selon le contexte aérospatial. La détection précoce d'anomalie a un ROI mesurable en heures.

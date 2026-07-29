# Runbook — Jour 44 : Cost Optimization

---

## Objectif

Analyser et optimiser le coût mensuel de l'architecture Smart Assembly Line.
Maîtriser les modèles CAPEX/OPEX/ROI pour les justifier en entretien.

---

## 1. Coût mensuel estimé (état actuel — dev, eu-west-3)

| Service | Usage | Coût/mois |
|---|---|---|
| **NAT Gateway** | 730h fixe + trafic | **~36 €** |
| CloudWatch | 15 métriques + 500 Mo logs + 1 dashboard | ~8 € |
| ALB | 730h + LCU | ~7 € |
| ECS Fargate | 0.25 vCPU / 0.5 Go × 730h | ~11 € |
| KMS CMK | 1 clé + requêtes | ~1 € |
| IoT Core | ~500K messages/mois | ~0.75 € |
| Lambda | < 1M invocations → Free Tier | ~0 € |
| DynamoDB | < 25 Go → Free Tier | ~0 € |
| SQS | < 1M messages → Free Tier | ~0 € |
| EventBridge | < 1M events → Free Tier | ~0 € |
| S3 raw-data | ~1 Go | ~0.03 € |
| CloudFront + S3 portfolio | ~1 Go trafic | ~0.09 € |
| **TOTAL** | | **~65 €/mois** |

---

## 2. Leviers d'optimisation

### Levier 1 — VPC Endpoints (remplacer NAT Gateway en dev)

**Économie : -22 €/mois (-34%)**

```powershell
# Vérifier le coût actuel du NAT Gateway
aws ce get-cost-and-usage `
  --time-period Start=2026-07-01,End=2026-07-31 `
  --granularity MONTHLY `
  --metrics BlendedCost `
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Virtual Private Cloud"]}}' `
  --region eu-west-3
```

VPC Endpoints à créer :
- `ecr.api` (Interface) — pull images ECR
- `ecr.dkr` (Interface) — authentification Docker
- `logs` (Interface) — CloudWatch Logs
- `monitoring` (Interface) — CloudWatch Metrics
- `sts` (Interface) — assume role ECS
- `dynamodb` (Gateway) — **gratuit**
- `s3` (Gateway) — **gratuit**

### Levier 2 — Fargate Spot en dev

**Économie : -6 €/mois (-9%)**

Activation : modifier `capacity_provider_strategy` dans `ecs.tf`
(voir `docs/cost/cost-optimization.md` pour le code Terraform)

---

## 3. Résumé ROI

```
Coût actuel (dev)         :  ~65 €/mois
Après optimisations       :  ~37 €/mois  (-43%)

ROI projet (production, 50 postes) :
  Économie arrêts non planifiés  : ~41 550 €/mois
  Coût infra prod AWS (×5)       :    ~325 €/mois
  ROI annuel                     :     +762%
  Payback period                 :     ~2 mois
```

---

## 4. Commandes de suivi des coûts

```powershell
# Coût total du mois en cours
aws ce get-cost-and-usage `
  --time-period Start=2026-07-01,End=2026-07-31 `
  --granularity MONTHLY `
  --metrics BlendedCost `
  --region eu-west-3

# Coût par service
aws ce get-cost-and-usage `
  --time-period Start=2026-07-01,End=2026-07-31 `
  --granularity MONTHLY `
  --metrics BlendedCost `
  --group-by Type=DIMENSION,Key=SERVICE `
  --region eu-west-3

# Vérifier les budgets actifs
aws budgets describe-budgets `
  --account-id 169237360990 `
  --region eu-west-3
```

---

## 5. Concepts clés retenus

| Concept | Définition courte |
|---|---|
| **CAPEX** | Dépense en capital, immobilisée au bilan (serveurs on-premise) |
| **OPEX** | Charge opérationnelle mensuelle (AWS pay-as-you-go) |
| **ROI** | (Gain net / Coût) × 100 |
| **Savings Plan** | Engagement 1-3 ans → -34% à -66% vs on-demand |
| **Spot** | Capacité excédentaire AWS → -70-90%, interruptible 2 min préavis |
| **NAT Gateway** | Poste dominant en dev → remplacer par VPC Endpoints |
| **Free Tier** | Lambda, DynamoDB, SQS, EventBridge → 0 € en usage dev |

---

## Commit

```powershell
git add docs/cost/cost-optimization.md
git add docs/runbooks/jour-44-cost-optimization.md

git commit -m "feat(jour-44): Cost Optimization — CAPEX/OPEX/ROI

- docs/cost/cost-optimization.md :
  CAPEX vs OPEX, modèles tarifaires AWS (pay-as-you-go/savings/spot)
  Estimation coût mensuel : ~65 €/mois (dev, eu-west-3)
  Levier 1 : VPC Endpoints → -22 €/mois (-34%)
  Levier 2 : Fargate Spot → -6 €/mois
  ROI industriel : +762% / payback 2 mois (50 postes)
  Budget AWS Terraform + Cost Explorer CLI

Closes #jour-44"

git push
```

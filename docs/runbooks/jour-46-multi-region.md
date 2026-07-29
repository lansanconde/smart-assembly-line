# Runbook — Jour 46 : Architecture multi-région (Active/Passive)

---

## Objectif

Concevoir l'architecture de résilience géographique active/passive entre eu-west-3 (Paris) et eu-central-1 (Francfort), avec failover automatique via Route 53 et réplication des données via DynamoDB Global Tables et S3 Cross-Region Replication.

---

## 1. Documents produits

| Document | Chemin | Contenu |
|---|---|---|
| Théorie multi-région | `docs/architecture/multi-region.md` | Active/passive vs active/active, RTO/RPO, Global Tables, Route 53 failover, S3 CRR, IoT Core multi-région, RGPD/ITAR/NIS2, failover playbook |
| Terraform multi-région | `docs/architecture/multi-region-terraform.md` | providers.tf, dynamodb-global.tf, route53.tf, s3-replication.tf, iam-replication.tf, outputs.tf, analyse de coût |

---

## 2. Décisions d'architecture

| Décision | Choix | Raison |
|---|---|---|
| Modèle de résilience | Active/Passive | Cohérence IoT (un seul maître d'écriture) |
| Régions | eu-west-3 + eu-central-1 | Toutes deux en UE → RGPD compatible |
| DynamoDB | Global Tables | RPO < 1 seconde, réplication automatique sub-seconde |
| Failover DNS | Route 53 Failover Routing | Bascule automatique sans intervention humaine |
| IoT Core | Greengrass multi-endpoint | Fallback transparent pour les capteurs |
| S3 | Cross-Region Replication | Asynchrone, storage_class STANDARD_IA sur replica |

---

## 3. SLA et métriques cibles

| Métrique | Cible | Mécanisme |
|---|---|---|
| RTO | < 5 minutes | Route 53 health check (30s × 3) + TTL DNS 60s |
| RPO | < 1 seconde | DynamoDB Global Tables sub-seconde |
| Disponibilité | 99.99% | Multi-région + multi-AZ dans chaque région |
| Détection panne | ~90 secondes | 3 health checks de 30s + propagation DNS |

---

## 4. Surcoût multi-région

```
Mono-région (actuel)     : ~65 €/mois (dev)
Multi-région (prod)      : ~379 €/mois de surcoût
ROI : 1h d'arrêt évité  = 40 000 €
      Surcoût annuel     = ~4 548 €
      Amorti en          : 7 minutes de production récupérée
```

---

## 5. Commandes de vérification

```powershell
# Vérifier l'état du health check Route 53
aws route53 get-health-check-status \
  --health-check-id <health-check-id> \
  --region us-east-1

# Vérifier la réplication DynamoDB Global Tables
aws dynamodb describe-table \
  --table-name machine_state_v2 \
  --region eu-west-3 \
  --query 'Table.Replicas'

# Vérifier la réplication S3
aws s3api get-bucket-replication \
  --bucket smart-assembly-raw-data-169237360990 \
  --region eu-west-3

# Tester la résolution DNS failover
nslookup api.smart-assembly.internal
```

---

## Commit

```powershell
git add docs/architecture/multi-region.md
git add docs/architecture/multi-region-terraform.md
git add docs/runbooks/jour-46-multi-region.md
git add mkdocs.yml

git commit -m "feat(jour-46): Architecture multi-région active/passive

- docs/architecture/multi-region.md :
  RTO < 5min / RPO < 1s — métriques et mécanismes
  Active/Passive retenu (vs active/active) — raison IoT
  DynamoDB Global Tables eu-west-3 → eu-central-1 (sub-seconde)
  Route 53 Failover Routing + health check HTTPS /health
  S3 Cross-Region Replication (CRR) + lifecycle STANDARD_IA → Glacier
  Greengrass multi-endpoint pour IoT Core failover transparent
  Contraintes réglementaires : RGPD (données en UE), ITAR, NIS2
  Failover playbook : T+0s → T+180s, RTO effectif ~3 min

- docs/architecture/multi-region-terraform.md :
  providers.tf : multi-provider aws.primary + aws.secondary + aws.global
  dynamodb-global.tf : Global Tables + streams + réplica eu-central-1
  route53.tf : health check + zone privée + records PRIMARY/SECONDARY + alarme CloudWatch
  s3-replication.tf : versioning + CRR + lifecycle replica
  iam-replication.tf : rôle + policy S3 CRR
  Analyse de coût : surcoût +379 €/mois, ROI amorti en 7 min de prod récupérée

Closes #jour-46"

git push
```

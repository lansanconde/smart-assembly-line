# Runbook — Jour 47 : Sécurité avancée (GuardDuty · Security Hub · AWS Config)

---

## Objectif

Passer d'une sécurité réactive (CloudTrail + alertes manuelles) à une sécurité proactive : détection de menaces temps réel (GuardDuty), scoring de conformité continu (Security Hub), drift detection (AWS Config), et remediation automatisée via Lambda.

---

## 1. Documents produits

| Document | Chemin | Contenu |
|---|---|---|
| Théorie sécurité avancée | `docs/security/advanced-security.md` | GuardDuty, Security Hub, AWS Config, Zero Trust, NIS2/RGPD |
| Terraform sécurité | `docs/security/advanced-security-terraform.md` | guardduty.tf, securityhub.tf, config.tf, security-alerts.tf, Lambda remediation Python |

---

## 2. Services activés

| Service | Standard/Configuration | Coût/mois |
|---|---|---|
| GuardDuty | CloudTrail + VPC Flow Logs + S3 | ~5 € |
| Security Hub | AWS FSBP + CIS Benchmark v1.4 | ~1 € |
| AWS Config | 7 règles managed | ~4.50 € |
| Lambda remediation | AUTO-REMEDIATION findings HIGH | ~0 € |
| **Total** | | **~10 €/mois** |

---

## 3. Règles AWS Config déployées

| Règle | Contrôle |
|---|---|
| `dynamodb-pitr-enabled` | PITR activé sur toutes les tables |
| `kms-key-rotation-enabled` | Rotation annuelle des clés CMK |
| `vpc-flow-logs-enabled` | Flow Logs actifs sur le VPC |
| `ecs-task-definition-no-environment-variables` | Pas de secrets en clair dans ECS |
| `s3-account-level-public-access-blocks` | S3 Block Public Access |
| `mfa-enabled-for-iam-console-access` | MFA obligatoire console |
| `iam-root-access-key-check` | Pas de clé d'accès root |

---

## 4. Flux de remediation automatique

```
GuardDuty Finding (severity >= 7 = HIGH)
      │
      ▼
EventBridge Rule : smart-assembly-guardduty-high
      │
      ▼
Lambda : smart-assembly-security-remediation
      │
      ├── CryptoCurrency → Stop ECS tasks
      ├── UnauthorizedAccess:IAMUser → Disable IAM key
      └── Toujours → SNS notification avec actions prises
```

---

## 5. Commandes de vérification

```powershell
# Statut GuardDuty
aws guardduty list-detectors --region eu-west-3
aws guardduty get-findings-statistics \
  --detector-id <detector-id> \
  --finding-criteria '{"Criterion":{"severity":{"Gte":4}}}' \
  --region eu-west-3

# Score Security Hub
aws securityhub get-findings \
  --filters '{"WorkflowStatus":[{"Value":"NEW","Comparison":"EQUALS"}],"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}' \
  --region eu-west-3

# Conformité AWS Config
aws configservice get-compliance-summary-by-config-rule \
  --region eu-west-3

# Ressources non conformes
aws configservice describe-compliance-by-config-rule \
  --compliance-types NON_COMPLIANT \
  --region eu-west-3
```

---

## Commit

```powershell
git add docs/security/advanced-security.md
git add docs/security/advanced-security-terraform.md
git add docs/runbooks/jour-47-advanced-security.md
git add mkdocs.yml

git commit -m "feat(jour-47): Sécurité avancée — GuardDuty + Security Hub + AWS Config

- docs/security/advanced-security.md :
  GuardDuty : sources (CloudTrail, VPC Flow Logs, DNS), findings types,
  remediation automatique via EventBridge + Lambda
  Security Hub : FSBP + CIS Benchmark, score de sécurité, 11 contrôles mappés
  AWS Config : drift detection, 7 règles managed, remediation SSM
  Zero Trust : IAM, réseau, données, détection — appliqué au projet
  Lien NIS2 art.21 + RGPD art.32 → conformité documentée

- docs/security/advanced-security-terraform.md :
  guardduty.tf : activation + datasources + EventBridge MEDIUM/HIGH
  securityhub.tf : standards FSBP + CIS + intégrations GuardDuty/Config
  config.tf : recorder + delivery channel + 7 règles managed
  security-alerts.tf : SNS + Lambda remediation (CryptoCurrency, UnauthorizedAccess)
  Code Python Lambda : stop ECS tasks, disable IAM key, SNS notify
  Coût : ~10 €/mois (dev) — ROI vs incident de sécurité

Closes #jour-47"

git push
```

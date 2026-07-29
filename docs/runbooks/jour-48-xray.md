# Runbook — Jour 48 : AWS X-Ray (Distributed Tracing)

---

## Objectif

Compléter le triptyque observabilité avec le distributed tracing : métriques (CloudWatch) + logs (CloudWatch Logs) + **traces (X-Ray)**. Instrumenter Lambda et ECS Fargate, configurer des sampling rules intelligentes, et activer X-Ray Insights pour la détection automatique d'anomalies de performance.

---

## 1. Documents produits

| Document | Chemin | Contenu |
|---|---|---|
| Théorie X-Ray | `docs/observability/xray.md` | Trace/Segment/Subsegment, Annotations vs Metadata, Sampling, Service Map, Insights, ServiceLens, cas d'usage concrets |
| Terraform X-Ray | `docs/observability/xray-terraform.md` | xray.tf (sampling rules + groupes), lambda-xray.tf, ecs-xray.tf (sidecar daemon), iam-xray.tf, code Python instrumenté |

---

## 2. Ce qui est instrumenté

| Service | Méthode | Annotations |
|---|---|---|
| Lambda `analyze_vibration` | `patch_all()` + `@capture` | `site_id`, `sensor_type`, `statut`, `anomalie_score` |
| Lambda `detect_anomaly` | `patch_all()` | Héritage du trace context parent |
| ECS `supervision-api` | Sidecar `xray-daemon` + middleware FastAPI | `site_poste_id`, `endpoint`, `items_returned` |
| DynamoDB (tous appels) | Automatique via `patch_all()` | Table, opération, durée |
| SNS (tous publish) | Automatique via `patch_all()` | TopicArn, durée |

---

## 3. Sampling Rules configurées

| Règle | Priorité | Cible | Taux |
|---|---|---|---|
| `smart-assembly-errors` | 50 (haute) | Erreurs 5xx `supervision-api` | 100% |
| `smart-assembly-anomalies` | 100 | Lambda `analyze_vibration` | 100% |
| `smart-assembly-nominal` | 9000 (basse) | Tout le reste | 5% |

---

## 4. Groupes X-Ray + Insights

| Groupe | Filtre | Insights |
|---|---|---|
| `smart-assembly-anomalies` | `annotation.statut = "EN_INTERVENTION" AND duration > 0.5` | Activé + notifications EventBridge |
| `smart-assembly-errors` | `fault = true OR error = true OR throttle = true` | Activé + notifications EventBridge |

---

## 5. Triptyque observabilité — couverture finale

```
MÉTRIQUES (CloudWatch)
  ✓ Lambda : Invocations, Errors, Duration, Throttles
  ✓ ECS    : CPUUtilization, MemoryUtilization
  ✓ DynamoDB : ConsumedWCU/RCU, ThrottledRequests
  ✓ ALB    : RequestCount, TargetResponseTime, HTTPCode_ELB_5XX

LOGS (CloudWatch Logs)
  ✓ Lambda : /aws/lambda/analyze_vibration, detect_anomaly
  ✓ ECS    : /ecs/supervision-api
  ✓ CloudTrail : aws-cloudtrail-logs-*

TRACES (X-Ray)
  ✓ Lambda : analyze_vibration (Active tracing)
  ✓ ECS    : supervision-api (sidecar daemon)
  ✓ DynamoDB : subsegments automatiques
  ✓ SNS/EventBridge : subsegments automatiques
  ✓ Service Map : visualisation architecture temps réel
  ✓ Insights : détection automatique d'anomalies de performance
```

---

## 6. Commandes de vérification

```powershell
# Vérifier que X-Ray reçoit des traces
aws xray get-trace-summaries \
  --start-time $(date -d '10 minutes ago' +%s) \
  --end-time $(date +%s) \
  --region eu-west-3

# Service Map
aws xray get-service-graph \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --region eu-west-3

# Sampling Rules actives
aws xray get-sampling-rules --region eu-west-3

# Groupes X-Ray
aws xray get-groups --region eu-west-3
```

---

## Commit

```powershell
git add docs/observability/xray.md
git add docs/observability/xray-terraform.md
git add docs/runbooks/jour-48-xray.md
git add mkdocs.yml

git commit -m "feat(jour-48): AWS X-Ray — Distributed Tracing complet

- docs/observability/xray.md :
  Triptyque observabilité : métriques + logs + traces
  Concepts : Trace / Segment / Subsegment, Annotations (indexées) vs Metadata
  Sampling rules : 100% anomalies/erreurs, 5% nominal
  Service Map : visualisation architecture générée automatiquement
  X-Ray Insights : détection automatique d'anomalies de performance
  CloudWatch ServiceLens : corrélation métriques + logs + traces
  3 cas d'usage : cold start Lambda, throttling DynamoDB, trace end-to-end IoT→alerte

- docs/observability/xray-terraform.md :
  xray.tf : 3 sampling rules (errors/anomalies/nominal) + 2 groupes Insights
  lambda-xray.tf : tracing Active + Layer SDK Python + code analyze_vibration instrumenté
  ecs-xray.tf : sidecar xray-daemon dans task definition + code FastAPI instrumenté
  iam-xray.tf : AWSXRayDaemonWriteAccess + politique inline minimale
  Coût : ~0 €/mois en dev (Free Tier 100K traces), ~25 €/mois prod (100K capteurs)

Closes #jour-48"

git push
```

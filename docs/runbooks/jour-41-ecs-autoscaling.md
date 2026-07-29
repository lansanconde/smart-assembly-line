# ECS Auto Scaling — supervision-api

---

## Objectif

Configurer la mise à l'échelle automatique du service ECS Fargate `supervision-api` via Application Auto Scaling :
- Scale out automatique si CPU > 60% (jusqu'à 4 tasks)
- Scale in automatique si CPU << 60% après 300s (minimum 1 task)
- Policy mémoire secondaire : scale out si mémoire > 75%

---

## Architecture

```
CloudWatch (CPU/Mémoire ECS) → Application Auto Scaling
                                        │
                              ┌─────────▼──────────┐
                              │  Scalable Target    │
                              │  min=1 / max=4      │
                              └─────────┬───────────┘
                                        │
                         ┌──────────────┴──────────────┐
                         ▼                             ▼
               Policy CPU (60%)           Policy Mémoire (75%)
               cooldown: 60s/300s         cooldown: 60s/300s
                         │                             │
                         └──────────────┬──────────────┘
                                        ▼
                            ECS Service desiredCount
                              1 task → 2 → 3 → 4
```

---

## 1. Ressources Terraform créées

**Fichier :** `terraform/environments/dev/autoscaling.tf`

| Ressource | Nom | Rôle |
|-----------|-----|------|
| `aws_appautoscaling_target` | `supervision_api` | Enregistre le service ECS comme ressource scalable |
| `aws_appautoscaling_policy` | `supervision_api_cpu` | Target Tracking CPU à 60% |
| `aws_appautoscaling_policy` | `supervision_api_memory` | Target Tracking mémoire à 75% |

**Choix techniques :**

| Choix | Justification |
|-------|---------------|
| Target Tracking (vs Step Scaling) | AWS gère les alarmes CloudWatch automatiquement, pas de configuration manuelle |
| CPU cible 60% | Laisse 40% de marge pour absorber les pics avant que le nouveau container soit prêt (~60s) |
| Mémoire cible 75% | Seuil conservateur : 512 MB alloués → scale out à ~384 MB |
| min_capacity = 1 | L'API est toujours disponible (pas de scale-to-zero) |
| max_capacity = 4 | Plafond de coût : 4 tasks Fargate (256 CPU / 512 MB chacune) |
| scale_in_cooldown 300s | Plus conservateur que scale_out (60s) : évite l'oscillation |

---

## 2. Commandes Terraform

```powershell
cd terraform/environments/dev

# Plan ciblé
terraform plan `
  -target="aws_appautoscaling_target.supervision_api" `
  -target="aws_appautoscaling_policy.supervision_api_cpu" `
  -target="aws_appautoscaling_policy.supervision_api_memory"

# Apply ciblé
terraform apply `
  -target="aws_appautoscaling_target.supervision_api" `
  -target="aws_appautoscaling_policy.supervision_api_cpu" `
  -target="aws_appautoscaling_policy.supervision_api_memory"
```

**Résultat obtenu :**
```
Apply complete! Resources: 3 added, 0 changed, 0 destroyed.
autoscaling_max_capacity       = 4
autoscaling_min_capacity       = 1
autoscaling_target_resource_id = "service/smart-assembly-cluster/supervision-api"
```

---

## 3. Validation

### 3.1 Vérifier le scalable target

```powershell
aws application-autoscaling describe-scalable-targets `
  --service-namespace ecs `
  --region eu-west-3 `
  --query "ScalableTargets[?ResourceId=='service/smart-assembly-cluster/supervision-api']"
```

Résultat attendu : 1 target avec `MinCapacity=1`, `MaxCapacity=4`.

### 3.2 Vérifier les policies

```powershell
aws application-autoscaling describe-scaling-policies `
  --service-namespace ecs `
  --region eu-west-3 `
  --query "ScalingPolicies[?ResourceId=='service/smart-assembly-cluster/supervision-api'].{Name:PolicyName,Type:PolicyType,Target:TargetTrackingScalingPolicyConfiguration.TargetValue}"
```

Résultat attendu : 2 policies (`cpu-tracking` à 60, `memory-tracking` à 75).

### 3.3 Vérifier les alarmes CloudWatch auto-créées

```powershell
aws cloudwatch describe-alarms `
  --alarm-name-prefix "TargetTracking-service/smart-assembly-cluster/supervision-api" `
  --region eu-west-3 `
  --query "MetricAlarms[].{Name:AlarmName,State:StateValue}"
```

AWS crée 2 alarmes par policy (scale-out + scale-in) = **4 alarmes au total**.

### 3.4 Console AWS

```
Console AWS → ECS → Clusters → smart-assembly-cluster
→ Services → supervision-api → Auto Scaling
```

Les deux policies doivent apparaître dans l'onglet "Auto Scaling".

---

## 4. Concepts clés retenus

**Application Auto Scaling vs EC2 Auto Scaling** : Application Auto Scaling gère les ressources managées (ECS, DynamoDB, RDS Aurora...). Pour ECS Fargate, c'est toujours Application Auto Scaling qui pilote le `desiredCount`.

**Alarmes CloudWatch auto-créées** : Target Tracking crée et gère ses propres alarmes CloudWatch. Ne pas les modifier manuellement — elles seraient écrasées à la prochaine mise à jour de la policy.

**`resource_id` ECS** : format imposé `service/<cluster_name>/<service_name>`. Si le format est incorrect, l'API retourne une erreur `ValidationException`.

**Deux policies sur un même target** : ECS prend la décision de scaling la plus agressive. Si CPU dit "scale out +1" et mémoire dit "scale out +2", le service scale de +2.

**`disable_scale_in = false`** : le scale-in est activé. Pour un service de traitement de jobs longs, on mettrait `true` + scale-in protection applicative via SDK.

---

## Commit

```powershell
git add terraform/environments/dev/autoscaling.tf
git add docs/ecs/autoscaling.md
git add docs/runbooks/jour-41-ecs-autoscaling.md

git commit -m "feat(jour-41): ECS Auto Scaling — Target Tracking CPU/Mémoire

- autoscaling.tf: aws_appautoscaling_target (min=1/max=4)
  Policy CPU : Target Tracking 60% — cooldown 60s/300s
  Policy mémoire : Target Tracking 75% — cooldown 60s/300s
  Alarmes CloudWatch créées automatiquement par AWS (4 alarmes)
- docs: théorie Application Auto Scaling + runbook Jour 41

Closes #jour-41"

git push
```

# Canary Deployment — supervision-api

---

## Objectif

Déployer une nouvelle version de `supervision-api` sur 10% du trafic via ALB Weighted Target Groups, valider les métriques, puis basculer à 100% ou effectuer un rollback.

---

## Architecture

```
ALB Listener (port 80)
  └── Listener Rule priority=10 : path=/*
        ├── 90% → TG Blue  (smart-assembly-supervision-tg) → ECS service stable (v1)
        └── 10% → TG Green (smart-assembly-canary-tg)     → ECS service canary (v2)

En mode normal (canary_active=false) :
  └── Default Action → 100% TG Blue
```

---

## 1. Ressources Terraform créées

**Fichier :** `terraform/environments/dev/canary.tf`

| Ressource | Condition | Rôle |
|-----------|-----------|------|
| `aws_lb_target_group.canary` | `canary_active=true` | TG Green pour le service canary |
| `aws_ecs_task_definition.supervision_api_canary` | `canary_active=true` | Task def avec image canary |
| `aws_ecs_service.supervision_api_canary` | `canary_active=true` | 1 task ECS canary |
| `aws_lb_listener_rule.canary` | `canary_active=true` | Règle pondérée 90/10 |
| `aws_cloudwatch_log_group.ecs_canary` | `canary_active=true` | Logs isolés canary |

**Choix techniques :**

| Choix | Justification |
|-------|---------------|
| `count = canary_active ? 1 : 0` | Toutes les ressources canary sont conditionnelles — zéro infra en mode normal |
| `variable canary_weight` | Poids configurable (1-99%) — permet une bascule progressive : 10 → 25 → 50 → 100 |
| Logs séparés `/ecs/supervision-api-canary` | Isoler les erreurs canary des logs stables pour le diagnostic |
| `stickiness = false` | Distribution aléatoire pure — évite que les mêmes utilisateurs soient toujours sur le canary |
| `priority = 10` | La listener rule canary s'applique avant la default_action — rollback = supprimer la règle |
| `CANARY_VERSION` env var | Identifiable dans les logs et headers de debug |

---

## 2. Variables

| Variable | Défaut | Description |
|----------|--------|-------------|
| `canary_active` | `false` | Active/désactive toutes les ressources canary |
| `canary_image_tag` | `"canary"` | Tag ECR de l'image à déployer (ex: `v2`, `abc1234`) |
| `canary_weight` | `10` | % de trafic vers le canary (1-99) |

---

## 3. Procédure complète

### Étape 0 — Préparer l'image v2

```powershell
# Builder la nouvelle version
cd src/supervision-api
mvn package -DskipTests

# Authentification ECR
aws ecr get-login-password --region eu-west-3 | `
  docker login --username AWS --password-stdin `
  169237360990.dkr.ecr.eu-west-3.amazonaws.com

# Build + push avec tag v2
docker build -t supervision-api:v2 .
docker tag supervision-api:v2 `
  169237360990.dkr.ecr.eu-west-3.amazonaws.com/supervision-api:v2
docker push `
  169237360990.dkr.ecr.eu-west-3.amazonaws.com/supervision-api:v2
```

### Étape 1 — Activer le canary (10%)

```powershell
cd terraform/environments/dev

terraform apply `
  -var="canary_active=true" `
  -var="canary_image_tag=v2" `
  -var="canary_weight=10"
```

**Résultat attendu :**
```
aws_cloudwatch_log_group.ecs_canary[0]: created
aws_lb_target_group.canary[0]: created
aws_ecs_task_definition.supervision_api_canary[0]: created
aws_lb_listener_rule.canary[0]: created
aws_ecs_service.supervision_api_canary[0]: created

Outputs:
canary_status = "ACTIF — 10% trafic → v2"
```

Attendre ~90 secondes que le container canary soit `HEALTHY` dans le TG.

```powershell
# Vérifier que le task canary est healthy
aws elbv2 describe-target-health `
  --target-group-arn <canary_target_group_arn> `
  --region eu-west-3
# → State: "healthy"
```

### Étape 2 — Valider les métriques (10-30 min)

```powershell
# Taux d'erreur sur le TG canary
aws cloudwatch get-metric-statistics `
  --namespace AWS/ApplicationELB `
  --metric-name HTTPCode_Target_5XX_Count `
  --dimensions `
    Name=LoadBalancer,Value=<alb_arn_suffix> `
    Name=TargetGroup,Value=<canary_tg_arn_suffix> `
  --start-time (Get-Date).AddMinutes(-15).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --end-time (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --period 60 `
  --statistics Sum `
  --region eu-west-3

# Latence p99 sur le TG canary
aws cloudwatch get-metric-statistics `
  --namespace AWS/ApplicationELB `
  --metric-name TargetResponseTime `
  --dimensions `
    Name=LoadBalancer,Value=<alb_arn_suffix> `
    Name=TargetGroup,Value=<canary_tg_arn_suffix> `
  --start-time (Get-Date).AddMinutes(-15).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --end-time (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --period 60 `
  --statistics p99 `
  --region eu-west-3
```

**Critères GO / NO-GO :**

| Métrique | GO | NO-GO |
|----------|-----|-------|
| `HTTPCode_Target_5XX_Count` | 0 ou identique au Blue | > 1% des requêtes |
| `TargetResponseTime p99` | ≤ baseline Blue | > 2× baseline |
| `HealthyHostCount` canary | ≥ 1 | = 0 |
| Logs canary `/ecs/supervision-api-canary` | Pas d'exception | Stack traces, erreurs |

### Étape 3a — Bascule progressive (si GO)

```powershell
# 25% canary
terraform apply -var="canary_active=true" -var="canary_image_tag=v2" -var="canary_weight=25"

# Valider à nouveau (5-10 min)...

# 50% canary
terraform apply -var="canary_active=true" -var="canary_image_tag=v2" -var="canary_weight=50"

# Valider...

# 100% canary — bascule complète
terraform apply -var="canary_active=true" -var="canary_image_tag=v2" -var="canary_weight=99"
```

**Finalisation :**
```powershell
# 1. Mettre à jour l'image stable (Blue) vers v2 dans ecs.tf
# → modifier supervision_api_image ou faire un force-new-deployment

# 2. Supprimer les ressources canary
terraform apply -var="canary_active=false"
```

### Étape 3b — Rollback (si NO-GO)

```powershell
# Rollback immédiat : supprime la listener rule → 100% Blue en secondes
terraform apply -var="canary_active=false"
```

**Résultat :** la listener rule est supprimée, la `default_action` du listener reprend (100% TG Blue). Aucun impact sur le service stable.

---

## 4. Validation de l'infrastructure canary

```powershell
# Vérifier la listener rule pondérée
aws elbv2 describe-rules `
  --listener-arn <listener_arn> `
  --region eu-west-3 `
  --query "Rules[?Priority=='10']"

# Vérifier le service canary ECS
aws ecs describe-services `
  --cluster smart-assembly-cluster `
  --services supervision-api-canary `
  --region eu-west-3 `
  --query "services[0].{desired:desiredCount,running:runningCount,status:status}"

# Tester manuellement que les deux versions répondent
# (en répétant les requêtes, ~10% arrivent sur v2)
for ($i=1; $i -le 20; $i++) {
  curl -s http://smart-assembly-alb-522870733.eu-west-3.elb.amazonaws.com/api/machines | `
    Select-String "CANARY_VERSION"
}
```

---

## 5. Concepts clés retenus

**`count = condition ? 1 : 0` en Terraform** : pattern standard pour les ressources conditionnelles. `count = 0` → ressource supprimée. `count = 1` → ressource créée. Les références à une ressource conditionnelle utilisent `resource[0]`.

**ALB Listener Rule priority** : les règles sont évaluées par ordre croissant de priorité (1 = le plus prioritaire). La `default_action` a la priorité la plus basse (évaluée en dernier). Mettre priority=10 garantit que la règle canary s'applique avant tout.

**Weighted forwarding stickiness=false** : sans stickiness, l'ALB distribue chaque requête aléatoirement selon les poids. Avec stickiness, l'ALB envoie toujours le même utilisateur (cookie) sur le même TG — moins aléatoire pour un canary.

**Isolation des métriques** : en ayant deux target groups distincts (Blue et Green), CloudWatch expose des métriques séparées par TG. C'est ce qui permet de comparer le taux d'erreur Blue vs Green pendant le canary.

**Rollback = suppression de la règle** : la `default_action` du listener pointe toujours sur le TG Blue. Supprimer la listener rule canary (`canary_active=false`) suffit pour un rollback complet — sans toucher au service stable.

---

## Commit

```powershell
git add terraform/environments/dev/canary.tf
git add docs/deployment/canary.md
git add docs/runbooks/jour-42-canary-deployment.md

git commit -m "feat(jour-42): Canary Deployment — ALB Weighted Target Groups

- canary.tf: déploiement canary conditionnel (canary_active=false par défaut)
  Variables : canary_active, canary_image_tag, canary_weight (1-99%)
  Ressources : TG canary + ECS service canary + Listener Rule priority=10
  Rollback : terraform apply -var=canary_active=false (secondes)
- docs: théorie Blue/Green/Canary/Shadow + procédure complète

Closes #jour-42"

git push
```

# ECS Auto Scaling : Mise à l'échelle automatique

## Positionnement dans le projet

```
CloudWatch Dashboard (Jour 40) → CPU > 60% détecté
                                        │
                               Application Auto Scaling
                                        │
                            ECS Service : desired count 1 → N
                                        │
                        Fargate alloue de nouveaux containers
```

L'Auto Scaling transforme le dashboard passif (on *voit* le CPU monter) en système réactif (le service *réagit* automatiquement).

---

## 1. Concepts fondamentaux

### 1.1 Application Auto Scaling vs EC2 Auto Scaling

AWS propose deux services de scaling distincts :

| Service | Pour quoi | Ressource scalée |
|---------|-----------|-----------------|
| **EC2 Auto Scaling** | Groupes d'instances EC2 | Nombre d'instances |
| **Application Auto Scaling** | ECS, DynamoDB, RDS Aurora, Lambda... | Capacité de la ressource cible |

Pour ECS Fargate on utilise **Application Auto Scaling** — c'est lui qui contrôle le `desiredCount` du service ECS.

### 1.2 Les trois composants

```
┌─────────────────────────────────────────────────────┐
│  1. Scalable Target                                  │
│     Quoi ? → ECS service supervision-api             │
│     Min : 1 task / Max : 4 tasks                    │
├─────────────────────────────────────────────────────┤
│  2. Scaling Policy                                   │
│     Comment ? → Target Tracking sur ECSServiceAverageCPUUtilization │
│     Cible : 60% CPU                                 │
├─────────────────────────────────────────────────────┤
│  3. CloudWatch Alarm (généré automatiquement)        │
│     Quand ? → CPU > 60% → scale out                 │
│              CPU << 60% → scale in                  │
└─────────────────────────────────────────────────────┘
```

### 1.3 Scalable Target

Le **scalable target** enregistre la ressource auprès d'Application Auto Scaling :

```hcl
resource "aws_appautoscaling_target" "ecs_service" {
  service_namespace  = "ecs"
  resource_id        = "service/${cluster_name}/${service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 1
  max_capacity       = 4
}
```

- `service_namespace` : toujours `"ecs"` pour ECS
- `resource_id` : format imposé `service/<cluster>/<service>`
- `scalable_dimension` : `"ecs:service:DesiredCount"` — c'est le paramètre qui sera modifié
- `min_capacity` / `max_capacity` : bornes du scaling

### 1.4 Types de Scaling Policy

#### Target Tracking Policy (recommandé)

Fonctionne comme un thermostat : tu définis une **cible** et AWS ajuste automatiquement la capacité pour l'atteindre.

```
CPU cible = 60%
  CPU actuel = 80% → scale out (ajoute des tasks)
  CPU actuel = 30% → scale in  (retire des tasks)
```

AWS crée **automatiquement** les alarmes CloudWatch en scale-out et scale-in. Tu n'as pas à les gérer.

**Métriques prédéfinies disponibles pour ECS :**
- `ECSServiceAverageCPUUtilization` — CPU moyen du service ✓ (on utilise celle-là)
- `ECSServiceAverageMemoryUtilization` — mémoire moyenne
- `ALBRequestCountPerTarget` — requêtes ALB par task (nécessite le ARN du target group)

#### Step Scaling Policy (avancé)

Scaling par paliers selon l'ampleur de l'écart :
- CPU 60–70% → +1 task
- CPU 70–85% → +2 tasks
- CPU > 85%  → +3 tasks

Plus précis mais plus complexe à configurer. Target Tracking suffit dans la plupart des cas.

### 1.5 Cooldown

Le cooldown évite l'oscillation (scale-out → scale-in en boucle rapide) :

| Type | Valeur recommandée | Rôle |
|------|-------------------|------|
| `scale_out_cooldown` | 60s | Délai minimum entre deux scale-out |
| `scale_in_cooldown` | 300s | Délai avant scale-in (plus conservateur) |

Le scale-in est intentionnellement plus lent que le scale-out : on préfère payer quelques minutes de plus plutôt que de supprimer un task qui était encore utile.

---

## 2. Comportement attendu

### 2.1 Cycle de vie d'un scale-out

```
1. CloudWatch : CPU > 60% sur 2 périodes consécutives (1 min each)
2. Application Auto Scaling reçoit l'alarme
3. Calcul : desiredCount_new = ceil(current_cpu / target_cpu) × current_tasks
4. ECS : desiredCount passe de 1 → 2
5. Fargate provisionne un nouveau container (~60s pour Spring Boot)
6. ALB : le nouveau container devient "healthy", reçoit du trafic
7. CPU se redistribue → 40% par task → l'alarme scale-out se résout
```

### 2.2 Cycle de vie d'un scale-in

```
1. CloudWatch : CPU << 60% pendant 300s (cooldown scale-in)
2. Application Auto Scaling : desiredCount passe de 2 → 1
3. ECS : draining de la connexion sur le task supprimé (deregistration_delay)
4. ALB arrête d'envoyer du trafic → task se termine proprement
```

### 2.3 Protection scale-in

Pour les tasks qui traitent des jobs longs (ex: batch), on peut activer la **scale-in protection** :

```python
# Dans le code de l'application (SDK AWS)
ecs_client.update_task_protection(
    cluster=cluster_name,
    tasks=[task_arn],
    protectionEnabled=True,
    expiresInMinutes=60
)
```

Non utilisé ici (supervision-api est stateless), mais important à connaître.

---

## 3. IAM requis

Application Auto Scaling nécessite un rôle de service pour modifier le `desiredCount` ECS :

```hcl
# Terraform crée implicitement le service-linked role
# arn:aws:iam::ACCOUNT_ID:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService
```

Ce rôle est créé automatiquement par AWS à la première utilisation — pas besoin de le provisionner manuellement.

---

## 4. Terraform — ressources utilisées

```hcl
# 1. Enregistrer la ressource scalable
resource "aws_appautoscaling_target" "ecs_service" {
  service_namespace  = "ecs"
  resource_id        = "service/${cluster}/${service}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 1
  max_capacity       = 4
}

# 2. Politique Target Tracking sur CPU
resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "smart-assembly-ecs-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_out_cooldown = 60
    scale_in_cooldown  = 300
  }
}
```

---

## 5. Bonnes pratiques niveau Senior

**Choisir la bonne métrique cible** : CPU est le plus courant. Mais pour une API HTTP, `ALBRequestCountPerTarget` est souvent plus précis — il scale avant que le CPU ne sature (réactif vs proactif).

**min_capacity ≥ 1 en prod** : ne jamais descendre à 0 tasks pour un service HTTP (le premier request après un scale-to-zero attend le cold start complet).

**max_capacity raisonnée** : fixer un plafond pour éviter les coûts incontrôlés en cas de bug (boucle infinie de requêtes). Ici : 4 tasks max.

**Cooldown scale-in conservateur (≥ 300s)** : ECS met ~60s à démarrer un container Spring Boot. Si on scale-in trop vite après un pic, on peut se retrouver à scale-out à nouveau immédiatement (oscillation).

**Monitorer les événements de scaling** : CloudWatch Events (EventBridge) capture chaque décision de scaling → utile pour le post-mortem.

**Distinction `desired` vs `running`** : pendant un scale-out, `desiredCount` > `runningCount` temporairement. L'ALB ne dirige du trafic que vers les tasks `RUNNING` + `HEALTHY`.

---

## 6. Commandes de validation

```powershell
# Voir les scalable targets enregistrés
aws application-autoscaling describe-scalable-targets `
  --service-namespace ecs `
  --region eu-west-3

# Voir les policies de scaling
aws application-autoscaling describe-scaling-policies `
  --service-namespace ecs `
  --region eu-west-3

# Voir les activités de scaling (historique)
aws application-autoscaling describe-scaling-activities `
  --service-namespace ecs `
  --resource-id "service/smart-assembly-cluster/supervision-api" `
  --region eu-west-3

# Voir l'état actuel du service ECS
aws ecs describe-services `
  --cluster smart-assembly-cluster `
  --services supervision-api `
  --region eu-west-3 `
  --query "services[0].{desired:desiredCount,running:runningCount,pending:pendingCount}"
```

---

## Résumé

| Concept | Valeur |
|---------|--------|
| Type de scaling | Application Auto Scaling — Target Tracking |
| Métrique cible | `ECSServiceAverageCPUUtilization` |
| Seuil | 60% CPU |
| Min tasks | 1 |
| Max tasks | 4 |
| Cooldown scale-out | 60s |
| Cooldown scale-in | 300s |
| Alarmes CloudWatch | Créées automatiquement par AWS |
| IAM | Service-linked role créé automatiquement |

# Canary Deployment : Déploiement Progressif

## Positionnement dans le projet

```
Nouvelle version supervision-api (v2)
              │
              ▼
    ┌─────────────────────┐
    │   ALB Listener      │
    │  Règle pondérée     │
    │  90% → TG Blue (v1) │
    │  10% → TG Green (v2)│
    └─────────────────────┘
              │
    ┌─────────┴──────────┐
    ▼                    ▼
TG Blue (v1)        TG Green (v2)
ECS task stable     ECS task canary
```

Le canary deployment permet de valider une nouvelle version sur une fraction du trafic réel **avant** de la généraliser. Si des erreurs apparaissent sur les 10%, on rollback — seuls 10% des utilisateurs ont été impactés.

---

## 1. Stratégies de déploiement — comparatif

### 1.1 Rolling Update (défaut ECS)

```
v1 v1 v1 v1
      ↓
v1 v1 v2 v1   ← un task remplacé
      ↓
v1 v2 v2 v1
      ↓
v2 v2 v2 v2   ← déploiement terminé
```

- **Avantage** : simple, aucune infra supplémentaire
- **Inconvénient** : si v2 est cassée, elle reçoit du trafic immédiatement — rollback lent (re-déploiement de v1)
- **Quand** : environnements non-critiques, changements mineurs

### 1.2 Blue/Green

```
ALB → 100% → Blue (v1)  ← en production
                              +
              Green (v2) ← stack complète prête, 0% trafic

              TEST Green OK ?
                    │
              ┌─────▼──────┐
         OUI  │ ALB bascule│  NON → supprimer Green, pas d'impact
              │ 100% Green │
              └────────────┘
```

- **Avantage** : rollback instantané (rebascule ALB vers Blue)
- **Inconvénient** : double la facture infrastructure pendant le déploiement
- **Quand** : changements majeurs, zero-downtime impératif

### 1.3 Canary ← *ce qu'on implémente*

```
ALB → 90% → Blue (v1)
     → 10% → Green (v2) canary

Métriques OK après X minutes ?
  OUI → augmenter progressivement : 50/50 → 0/100 → supprimer Blue
  NON → remettre 100% sur Blue → supprimer Green
```

- **Avantage** : risque limité (seul 10% des utilisateurs touchés), validation sur trafic réel
- **Inconvénient** : plus complexe que rolling, nécessite deux target groups
- **Quand** : changements comportementaux (nouvelle logique métier, nouvelle dépendance)

### 1.4 Shadow / Traffic Mirroring

```
ALB → 100% → Blue (v1)  ← répond au client
          └→ Green (v2)  ← reçoit une copie du trafic, réponse ignorée
```

- **Avantage** : test de charge réelle sans risque
- **Inconvénient** : double la charge sur les backends
- **Quand** : validation de performance avant canary

---

## 2. Canary sur AWS ECS — deux approches

### 2.1 ALB Weighted Target Groups (ce projet)

L'ALB supporte des **règles de forwarding pondérées** : un listener peut distribuer le trafic entre plusieurs target groups selon un poids.

```
Listener HTTP :443
  └── Rule : path=/*
        ├── Forward 90% → TG Blue  (supervision-api v1)
        └── Forward 10% → TG Green (supervision-api v2 canary)
```

**Avantages** :
- Aucun outil supplémentaire
- Contrôle granulaire (1% à 100%)
- Rollback = modifier les poids (secondes)

**Limites** :
- Pas de rollback automatique basé sur les métriques
- La bascule progressive doit être faite manuellement (ou via un script)

### 2.2 AWS CodeDeploy + ECS (production)

CodeDeploy gère le canary ECS en natif avec des stratégies prédéfinies :

| Stratégie | Comportement |
|-----------|-------------|
| `Canary10Percent5Minutes` | 10% d'abord → attendre 5 min → 100% |
| `Linear10PercentEvery1Minute` | +10% toutes les minutes |
| `AllAtOnce` | 100% d'un coup (blue/green sans canary) |

CodeDeploy peut déclencher un **rollback automatique** si une alarme CloudWatch se déclenche pendant la bascule.

```hcl
resource "aws_codedeploy_deployment_group" "ecs_canary" {
  deployment_config_name = "CodeDeployDefault.ECSCanary10Percent5Minutes"
  
  alarm_configuration {
    alarms  = ["smart-assembly-ecs-errors"]
    enabled = true
  }
  
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }
}
```

**Avantage** : rollback automatique sur alarme, intégration CI/CD native
**Complexité** : nécessite CodeDeploy App + Deployment Group + AppSpec file

---

## 3. Implémentation ALB Weighted Target Groups

### 3.1 Architecture Terraform

```
aws_lb_target_group "backend"      ← TG Blue (existant, v1)
aws_lb_target_group "canary"       ← TG Green (nouveau, v2)
aws_lb_listener_rule "canary"      ← Règle pondérée 90/10
aws_ecs_service "supervision_api_canary" ← Service ECS canary (0 ou 1 task)
```

### 3.2 Listener Rule avec poids

```hcl
resource "aws_lb_listener_rule" "canary" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10  # priorité haute (avant la règle par défaut)

  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.backend.arn  # Blue
        weight = 90
      }
      target_group {
        arn    = aws_lb_target_group.canary.arn   # Green
        weight = 10
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}
```

### 3.3 ECS Service canary

Le service canary tourne en parallèle du service principal :
- **1 task** (vs N tasks pour le service principal)
- **Même task definition** mais avec l'image v2
- **Target group dédié** (`canary`) pour isolation des métriques

---

## 4. Procédure de déploiement canary

### Phase 1 — Préparation (avant le déploiement)

```powershell
# 1. Builder et pusher la nouvelle image v2
docker build -t supervision-api:v2 src/supervision-api/
docker tag supervision-api:v2 169237360990.dkr.ecr.eu-west-3.amazonaws.com/supervision-api:v2
docker push 169237360990.dkr.ecr.eu-west-3.amazonaws.com/supervision-api:v2

# 2. Vérifier les métriques baseline (avant déploiement)
# → CloudWatch Dashboard : noter les taux d'erreur, latence p99
```

### Phase 2 — Déploiement canary (10%)

```powershell
# Terraform apply : crée TG canary + service ECS canary + listener rule 90/10
terraform apply -target=aws_lb_target_group.canary `
                -target=aws_ecs_service.supervision_api_canary `
                -target=aws_lb_listener_rule.canary
```

### Phase 3 — Validation (10-30 minutes)

```powershell
# Métriques à surveiller sur le TG canary :
aws cloudwatch get-metric-statistics `
  --namespace AWS/ApplicationELB `
  --metric-name HTTPCode_Target_5XX_Count `
  --dimensions Name=TargetGroup,Value=<canary_tg_arn_suffix> `
  --start-time ... --end-time ... --period 60 --statistics Sum `
  --region eu-west-3

# Taux d'erreur sur le TG canary < 1% → GO pour bascule complète
# Taux d'erreur > 1% ou latence p99 dégradée → ROLLBACK
```

### Phase 4a — Bascule complète (si OK)

```powershell
# Modifier la listener rule : 0% Blue, 100% Green
# Puis : supprimer le service Blue, supprimer TG Blue
# Renommer Green → Blue pour le prochain cycle
```

### Phase 4b — Rollback (si problème)

```powershell
# Remettre 100% sur Blue : modifier listener rule weight=100/0
# Puis supprimer le service canary et TG canary
terraform destroy -target=aws_ecs_service.supervision_api_canary `
                  -target=aws_lb_target_group.canary `
                  -target=aws_lb_listener_rule.canary
```

---

## 5. Métriques à surveiller pendant le canary

| Métrique | Namespace | Seuil d'alerte | Action |
|----------|-----------|----------------|--------|
| `HTTPCode_Target_5XX_Count` | `AWS/ApplicationELB` | > 1% des requêtes | Rollback |
| `TargetResponseTime` p99 | `AWS/ApplicationELB` | > 2x la baseline | Rollback |
| `HealthyHostCount` | `AWS/ApplicationELB` | = 0 | Rollback immédiat |
| `Errors` Lambda | `AWS/Lambda` | Augmentation > 10% | Investiguer |

---

## 6. Bonnes pratiques niveau Senior

**Canary ≠ test** : le canary n'est pas un test fonctionnel — il valide le comportement sur le trafic réel. Les tests fonctionnels (unitaires, intégration) doivent passer AVANT le canary.

**Sticky sessions et canary** : si l'ALB a des sticky sessions activées, les 10% de trafic canary ne seront pas aléatoires — les mêmes utilisateurs iront toujours sur le canary. Désactiver les sticky sessions pour un canary neutre.

**Feature flags plutôt que canary pour la logique métier** : si la v2 change la logique métier (pas seulement le comportement technique), combiner canary (infrastructure) + feature flag (logique) pour contrôler l'activation indépendamment du déploiement.

**Automatiser la bascule progressive** : en production, un script ou CodeDeploy bascule le trafic par paliers (10% → 25% → 50% → 100%) avec validation automatique à chaque étape.

**Canary headers** : certaines équipes ajoutent un header HTTP (`X-Canary: true`) pour identifier les requêtes canary dans les logs — facilite le debug et l'analyse post-déploiement.

---

## Résumé

| Concept | Valeur |
|---------|--------|
| Stratégie | ALB Weighted Target Groups |
| Trafic canary | 10% (TG Green) |
| Trafic stable | 90% (TG Blue) |
| Rollback | Modifier les poids ALB (secondes) |
| Rollback automatique | Non (nécessiterait CodeDeploy) |
| Durée validation | 10-30 minutes selon le trafic |
| Métriques surveillées | 5xx, latence p99, HealthyHostCount |

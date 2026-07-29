# CloudWatch Dashboard : Observabilité Unifiée

## Positionnement dans le projet

```
IoT Sensors → Greengrass → IoT Core → EventBridge
                                           │
                                     Lambda (analyze_vibration)
                                           │
                                       DynamoDB (machine_state)
                                           │
                               ECS Fargate (supervision-api)
                                           │
                                          ALB
                                           │
                              ┌────────────▼────────────┐
                              │  CloudWatch Dashboard    │
                              │  (vue unifiée Jour 40)  │
                              └─────────────────────────┘
```

Le dashboard CloudWatch est la **fenêtre unique sur la santé du système**. Il agrège les métriques de toutes les couches (IoT, Lambda, DynamoDB, ECS, ALB) en un seul endroit, sans code supplémentaire — tout est déjà instrumenté par AWS.

---

## 1. Concepts CloudWatch

### 1.1 Namespace et Metric

CloudWatch organise les métriques en **namespaces** (espaces de noms) :

| Namespace | Service | Exemples de métriques |
|-----------|---------|----------------------|
| `AWS/Lambda` | Lambda | Invocations, Errors, Duration, Throttles |
| `AWS/ECS` | ECS Fargate | CPUUtilization, MemoryUtilization |
| `AWS/DynamoDB` | DynamoDB | ConsumedReadCapacityUnits, SystemErrors |
| `AWS/ApplicationELB` | ALB | RequestCount, TargetResponseTime, HTTPCode_ELB_5XX |
| `AWS/IoTCore` | IoT Core | Connect.Success, PublishIn.Success |
| `AWS/SQS` | SQS | NumberOfMessagesSent, ApproximateAgeOfOldestMessage |
| `ECS/ContainerInsights` | Container Insights | task_cpu_utilization, task_memory_utilization |

Chaque métrique est identifiée par : namespace + nom + dimensions.

**Exemple** : `AWS/Lambda` → `Errors` → dimension `FunctionName=smart-assembly-analyze-vibration`

### 1.2 Période et Statistique

- **Période** : fenêtre de temps sur laquelle la statistique est calculée (60s, 300s, 3600s)
- **Statistique** : `Sum`, `Average`, `Maximum`, `Minimum`, `SampleCount`, `p99`, `p95`

Exemples :
- Erreurs Lambda → `Sum` sur 60s (on veut le total, pas la moyenne)
- Latence ALB → `p99` sur 60s (on veut le pire cas, pas la moyenne)
- CPU ECS → `Average` sur 60s

### 1.3 Dashboard

Un dashboard est une **collection de widgets** disposés sur une grille (colonnes × hauteur). Il peut contenir :

- **Line** : courbe temporelle (ex: CPU ECS dans le temps)
- **Number** : valeur instantanée (ex: nombre d'erreurs Lambda)
- **Alarm status** : état des alarmes CloudWatch
- **Log insights** : résultat d'une query sur les logs (ex: top 10 erreurs)
- **Text** : markdown pour titres et séparateurs

Chaque dashboard est défini en JSON — c'est ce qu'on va provisionner avec Terraform.

---

## 2. Métriques clés par service

### 2.1 Lambda — analyze_vibration

| Métrique | Statistique | Période | Signification |
|----------|-------------|---------|---------------|
| `Invocations` | Sum | 5 min | Volume de traitements IoT |
| `Errors` | Sum | 5 min | Erreurs fonctionnelles |
| `Duration` | p99 | 5 min | Latence maximale (SLA) |
| `Throttles` | Sum | 5 min | Limite de concurrence atteinte |
| `ConcurrentExecutions` | Maximum | 5 min | Pic de parallélisme |

**Seuil d'alerte recommandé** : `Errors > 0` sur 5 min consécutives.

### 2.2 ECS Fargate — supervision-api

| Métrique | Statistique | Période | Signification |
|----------|-------------|---------|---------------|
| `CPUUtilization` | Average | 1 min | Charge CPU du container |
| `MemoryUtilization` | Average | 1 min | Charge mémoire (512 MB alloués) |
| `RunningTaskCount` | Average | 1 min | Nombre de tasks actifs |

**Source** : namespace `ECS/ContainerInsights` (activé via `containerInsights = enabled` sur le cluster).

**Seuil d'alerte** : `CPUUtilization > 80%` ou `MemoryUtilization > 85%` → scale-out à prévoir.

### 2.3 DynamoDB — machine_state

| Métrique | Statistique | Période | Signification |
|----------|-------------|---------|---------------|
| `ConsumedReadCapacityUnits` | Sum | 5 min | Volume de lectures |
| `ConsumedWriteCapacityUnits` | Sum | 5 min | Volume d'écritures |
| `SystemErrors` | Sum | 5 min | Erreurs internes DynamoDB |
| `SuccessfulRequestLatency` | p99 | 5 min | Latence des requêtes |

### 2.4 ALB — smart-assembly-alb

| Métrique | Statistique | Période | Signification |
|----------|-------------|---------|---------------|
| `RequestCount` | Sum | 1 min | Volume de requêtes HTTP |
| `TargetResponseTime` | p99 | 1 min | Latence end-to-end |
| `HTTPCode_Target_5XX_Count` | Sum | 1 min | Erreurs 5xx (ECS) |
| `HTTPCode_ELB_5XX_Count` | Sum | 1 min | Erreurs 5xx (ALB lui-même) |
| `HealthyHostCount` | Minimum | 1 min | Tasks ECS saines |

**Seuil critique** : `HealthyHostCount = 0` → plus aucun container sain, l'API est hors service.

---

## 3. Structure du dashboard

Le dashboard est organisé en **4 lignes** :

```
┌─────────────────────────────────────────────────────────┐
│  TITRE : Smart Assembly Line — Tableau de bord          │
├───────────────────────┬─────────────────────────────────┤
│  Lambda Invocations   │  Lambda Errors   │ Lambda p99   │
├───────────────────────┼──────────────────┴──────────────┤
│  ECS CPU              │  ECS Memory      │ Healthy Tasks │
├───────────────────────┼──────────────────┴──────────────┤
│  ALB Request Count    │  ALB p99 Latency │ ALB 5xx      │
├───────────────────────┼──────────────────┴──────────────┤
│  DynamoDB Read CU     │  DynamoDB Write CU              │
└───────────────────────┴─────────────────────────────────┘
```

---

## 4. Terraform — ressource aws_cloudwatch_dashboard

CloudWatch Dashboard en Terraform utilise la ressource `aws_cloudwatch_dashboard` avec un body JSON encodé en HCL :

```hcl
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "smart-assembly-overview"
  dashboard_body = jsonencode({
    widgets = [
      # Chaque widget est un objet avec : type, x, y, width, height, properties
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "Lambda — Invocations"
          view   = "timeSeries"
          region = "eu-west-3"
          metrics = [[
            "AWS/Lambda", "Invocations",
            "FunctionName", "smart-assembly-analyze-vibration",
            { stat = "Sum", period = 300 }
          ]]
        }
      }
      # ... autres widgets
    ]
  })
}
```

### Grille CloudWatch

La grille est de **24 colonnes** de large. Hauteur libre. Règles :
- `width` : 1–24 (total = 24 par ligne)
- `height` : 1–1000 (recommandé : 6 pour les graphes)
- `x + width ≤ 24` (sinon le widget déborde)

Exemple de mise en page 3 colonnes (8+8+8 = 24) :
```
widget 1 : x=0,  width=8
widget 2 : x=8,  width=8
widget 3 : x=16, width=8
```

---

## 5. Alarmes CloudWatch (complémentaires)

Les alarmes existantes (Jour 3x) sont intégrées dans le dashboard via un widget `alarm` :

```hcl
{
  type   = "alarm"
  x      = 0
  y      = 24
  width  = 24
  height = 4
  properties = {
    title  = "État des Alarmes"
    alarms = [
      "arn:aws:cloudwatch:eu-west-3:169237360990:alarm:lambda-errors-critical",
      "arn:aws:cloudwatch:eu-west-3:169237360990:alarm:ecs-cpu-high"
    ]
  }
}
```

---

## 6. Bonnes pratiques niveau Senior

**Séparer les vues par audience** : un dashboard "Ops" (CPU, mémoire, erreurs) et un "Business" (invocations, throughput, latence) sont plus utiles qu'un dashboard unique surchargé.

**Préférer p99 à Average pour la latence** : la moyenne masque les outliers. En prod, 1% des requêtes à 10s est un problème même si la moyenne est à 200ms.

**Alarmes composites** : combiner plusieurs alarmes (`ALARM(err) AND ALARM(latency)`) pour réduire le bruit. AWS CloudWatch Composite Alarms permet ça nativement.

**Annotations sur les graphes** : CloudWatch permet d'ajouter des lignes horizontales (seuils) et verticales (événements) pour contextualiser les pics.

**Period override** : en Terraform, le `period` du widget peut être différent du `period` de l'alarme — utile pour avoir une vue "1 minute" en direct et une alarme sur "5 minutes" (plus stable).

**Tags sur le dashboard** : pas de support natif via Terraform `aws_cloudwatch_dashboard`, mais les coûts CloudWatch Dashboard sont négligeables (3$/mois par dashboard).

---

## 7. Commandes utiles

```bash
# Lister les dashboards existants
aws cloudwatch list-dashboards --region eu-west-3

# Voir le JSON d'un dashboard
aws cloudwatch get-dashboard \
  --dashboard-name smart-assembly-overview \
  --region eu-west-3 \
  --query DashboardBody --output text | python3 -m json.tool

# URL console directe
# https://eu-west-3.console.aws.amazon.com/cloudwatch/home?region=eu-west-3#dashboards:name=smart-assembly-overview
```

---

## Résumé

| Concept | Valeur |
|---------|--------|
| Dashboard | `smart-assembly-overview` |
| Région | `eu-west-3` |
| Services couverts | Lambda, ECS, DynamoDB, ALB |
| Widgets | ~10 (métriques + alarmes) |
| Provisioning | Terraform `aws_cloudwatch_dashboard` |
| Namespace Container Insights | `ECS/ContainerInsights` |
| Latence : statistique recommandée | `p99` |

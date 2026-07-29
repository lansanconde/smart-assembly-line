# CloudWatch Dashboard Observabilité Unifiée

---

## Objectif

Provisionner un CloudWatch Dashboard unifié (`smart-assembly-overview`) agrégeant les métriques de toutes les couches du projet :
- Lambda (3 fonctions : analyze_vibration, detect_anomaly, store_metrics)
- ECS Fargate (supervision-api)
- ALB (smart-assembly-alb)
- DynamoDB (machine_state)
- Widget alarmes (5 alarmes existantes)

---

## Architecture observabilité

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
                          ┌────────────────▼────────────────┐
                          │  CloudWatch Dashboard            │
                          │  smart-assembly-overview         │
                          │  11 widgets — vue unifiée        │
                          └─────────────────────────────────┘
```

---

## 1. Ressource Terraform créée

**Fichier :** `terraform/environments/dev/cloudwatch.tf`

```hcl
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "smart-assembly-overview"
  dashboard_body = jsonencode({ widgets = [...] })
}
```

**Choix techniques :**

| Choix | Justification |
|-------|---------------|
| `jsonencode()` dans HCL | Dashboard entièrement versionné dans Git, pas de JSON séparé |
| `locals` pour les noms | Références dynamiques aux ressources Terraform (`aws_lb.main.arn_suffix`) — pas de hardcoding |
| `arn_suffix` pour ALB | CloudWatch exige le suffixe ARN (`app/smart-assembly-alb/xxxx`), pas le nom |
| `ECS/ContainerInsights` | Nécessite `containerInsights = enabled` sur le cluster (déjà configuré Jour 39) |
| `p99` pour les latences | Révèle les outliers que la moyenne masque |

---

## 2. Structure du dashboard (11 widgets)

### Ligne 0 — Titre (1 widget texte, width=24)
Widget markdown pleine largeur : titre + description.

### Ligne 1 — Lambda (3 widgets, y=2)

| Widget | Métrique | Stat | Période |
|--------|----------|------|---------|
| Invocations | `AWS/Lambda / Invocations` | Sum | 5 min |
| Erreurs | `AWS/Lambda / Errors` | Sum | 5 min |
| Durée p99 | `AWS/Lambda / Duration` (3 fonctions) | p99 | 5 min |

Annotation sur les erreurs : ligne orange à `value=1` (seuil d'alerte visuel).

### Ligne 2 — ECS Fargate (3 widgets, y=8)

| Widget | Métrique | Stat | Période |
|--------|----------|------|---------|
| CPU | `ECS/ContainerInsights / CpuUtilized` | Average | 1 min |
| Mémoire | `ECS/ContainerInsights / MemoryUtilized` | Average | 1 min |
| Running Tasks | `ECS/ContainerInsights / RunningTaskCount` | Average | 1 min |

Annotations : ligne rouge à 80% CPU (seuil scale-out), 85% mémoire.

### Ligne 3 — ALB (3 widgets, y=14)

| Widget | Métrique | Stat | Période |
|--------|----------|------|---------|
| Requêtes/min | `AWS/ApplicationELB / RequestCount` | Sum | 1 min |
| Latence p99 | `AWS/ApplicationELB / TargetResponseTime` | p99 | 1 min |
| 5xx + Healthy Hosts | `HTTPCode_Target_5XX_Count` + `HealthyHostCount` | Sum / Min | 1 min |

Le widget 5xx utilise **dual Y-axis** : erreurs à gauche, hosts sains à droite.

### Ligne 4 — DynamoDB (3 widgets, y=20)

| Widget | Métrique | Stat | Période |
|--------|----------|------|---------|
| Lectures | `AWS/DynamoDB / ConsumedReadCapacityUnits` | Sum | 5 min |
| Écritures | `AWS/DynamoDB / ConsumedWriteCapacityUnits` | Sum | 5 min |
| Latence p99 | `AWS/DynamoDB / SuccessfulRequestLatency` (GetItem + Scan) | p99 | 5 min |

### Ligne 5 — Alarmes (1 widget alarm, y=26, width=24)

5 alarmes intégrées :
- `smart-assembly-vibration-critical`
- `smart-assembly-temperature-critical`
- `smart-assembly-anomaly-ml`
- `smart-assembly-message-critical-burst`
- `smart-assembly-vibration-ml-escalade` (composite)

---

## 3. Commandes Terraform

```powershell
cd terraform/environments/dev

# Plan ciblé sur le dashboard uniquement
terraform plan -target=aws_cloudwatch_dashboard.main

# Apply ciblé
terraform apply -target=aws_cloudwatch_dashboard.main

# Vérifier le dashboard créé
aws cloudwatch list-dashboards --region eu-west-3

# URL console
# https://eu-west-3.console.aws.amazon.com/cloudwatch/home?region=eu-west-3#dashboards:name=smart-assembly-overview
```

---

## 4. Validation

### 4.1 Dashboard visible dans la console AWS

```
Console AWS → CloudWatch → Dashboards → smart-assembly-overview
```

11 widgets présents, organisés sur 5 lignes.

### 4.2 Données Lambda visibles

Démarrer le simulateur IoT :

```powershell
cd src/iot-simulator
python publish_vibration_edge.py
```

Attendre ~5 minutes (période des widgets Lambda = 300s). Les courbes d'invocations apparaissent.

**Résultat obtenu :** données visibles après démarrage du simulateur ✅

### 4.3 Données ECS/ALB

Les métriques ECS et ALB se mettent à jour toutes les minutes (période = 60s). Elles apparaissent immédiatement si le service tourne.

```powershell
# Vérifier que le service ECS tourne
aws ecs describe-services `
  --cluster smart-assembly-cluster `
  --services supervision-api `
  --region eu-west-3 `
  --query "services[0].{running:runningCount,desired:desiredCount}"
```

### 4.4 Vérification CLI des métriques Lambda

```powershell
aws cloudwatch get-metric-statistics `
  --namespace AWS/Lambda `
  --metric-name Invocations `
  --dimensions Name=FunctionName,Value=smart-assembly-analyze-vibration `
  --start-time (Get-Date).AddMinutes(-15).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --end-time (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") `
  --period 60 `
  --statistics Sum `
  --region eu-west-3
```

---

## 5. Backend S3 — Fix CI/CD (bonus Jour 40)

Problème découvert et résolu ce jour : le pipeline CI échouait avec `ResourceAlreadyExistsException` sur le `terraform apply` car **aucun backend S3 n'était configuré**. Chaque run CI démarrait avec un state vide et tentait de recréer toutes les ressources.

**Fix :**

```powershell
# 1. Créer le bucket S3 dédié au state
aws s3api create-bucket `
  --bucket smart-assembly-tfstate-169237360990 `
  --region eu-west-3 `
  --create-bucket-configuration LocationConstraint=eu-west-3

aws s3api put-bucket-versioning `
  --bucket smart-assembly-tfstate-169237360990 `
  --versioning-configuration Status=Enabled

# 2. Ajouter le backend dans main.tf
# backend "s3" { bucket = "smart-assembly-tfstate-169237360990" ... }

# 3. Migrer le state local vers S3
terraform init -migrate-state
# → "yes" pour confirmer la migration
```

**Résultat :** CI pipeline 100% vert — plus de `ResourceAlreadyExistsException`. Le state est maintenant partagé entre local et CI.

---

## 6. Concepts clés retenus

**`arn_suffix` vs nom pour ALB** : CloudWatch identifie les load balancers via leur ARN suffix (`app/smart-assembly-alb/e32676bd...`), pas leur nom. Terraform expose `aws_lb.main.arn_suffix` pour ça.

**`ECS/ContainerInsights` vs `AWS/ECS`** : Le namespace standard `AWS/ECS` expose seulement `CPUUtilization` et `MemoryUtilization` en pourcentage. Container Insights (`ECS/ContainerInsights`) expose des métriques plus riches : `CpuUtilized` (millicores), `MemoryUtilized` (MB), `RunningTaskCount`, `NetworkRxBytes`, etc. Mais il faut avoir activé `containerInsights = enabled` sur le cluster.

**Dual Y-axis** : CloudWatch supporte deux axes Y sur un même widget via `yAxis = "right"` sur certaines métriques. Utile pour combiner une métrique de comptage (erreurs 5xx) et une métrique de jauge (healthy hosts) sans que les échelles se chevauchent.

**Période minimum CloudWatch** : 60 secondes pour les métriques standard. Certaines métriques haute résolution permettent 1 seconde (Lambda avec `--function-event-invoke-config`), mais le coût CloudWatch augmente.

**`jsonencode()` en Terraform** : Convertit un objet HCL en JSON valide. Permet d'écrire le body du dashboard en HCL natif (avec `locals`, références aux ressources, commentaires) plutôt qu'en JSON brut — bien plus maintenable.

---

## Commit

```powershell
git add terraform/environments/dev/cloudwatch.tf
git add terraform/environments/dev/main.tf
git add docs/cloudwatch/dashboard.md
git add docs/runbooks/jour-40-cloudwatch-dashboard.md

git commit -m "feat(jour-40): CloudWatch Dashboard + S3 backend CI fix

- cloudwatch.tf: aws_cloudwatch_dashboard smart-assembly-overview
  11 widgets : Lambda (invocations/erreurs/p99) · ECS (CPU/mémoire/tasks)
  ALB (requêtes/latence p99/5xx+healthy hosts) · DynamoDB (RCU/WCU/latence)
  Widget alarmes : 5 alarmes existantes intégrées
- main.tf: backend S3 (smart-assembly-tfstate-169237360990)
  State migré local → S3, résout ResourceAlreadyExists en CI
- docs: théorie namespaces CloudWatch + runbook Jour 40

Closes #jour-40"
```

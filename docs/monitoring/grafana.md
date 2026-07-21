# Amazon Managed Grafana — Dashboards Monitoring (Pratique)

> Implémentation réelle déployée en eu-west-3 (Paris).
> Remplace IoT SiteWise Monitor (non disponible en eu-west-3).
> Datasources : Amazon CloudWatch (métriques custom Lambda + IoT Core).

---

## 1. Positionnement dans la stack

```
Capteurs → Mosquitto → analyzer.py → IoT Core
                                          │
                              ┌───────────┴───────────┐
                              ▼                       ▼
                         Lambda processor        CloudWatch
                              │                  (métriques custom)
                              ▼                       │
                         DynamoDB               Amazon Managed
                         EventBridge      →      Grafana
                         Step Functions    (dashboards temps réel)
```

Amazon Managed Grafana lit les métriques CloudWatch publiées par le Lambda
à chaque mesure traitée. Aucune infrastructure Grafana à gérer.

---

## 2. Amazon Managed Grafana

### 2.1 Qu'est-ce que c'est ?

Service managé AWS basé sur Grafana OSS. AWS gère :
- Les serveurs, la haute disponibilité, les mises à jour
- L'authentification (SSO via IAM Identity Center)
- Les permissions datasource via IAM (pas de credentials à gérer)

**Avantages vs Grafana self-hosted :**
- Zéro ops : pas d'EC2, pas de RDS pour le storage Grafana
- Intégration IAM native : le workspace Grafana a un rôle IAM qui lit CloudWatch
- Facturation à l'utilisateur actif (pas à la ressource)

### 2.2 Coût

- **Free tier** : aucun
- **Tarif** : ~$9/mois par utilisateur actif (éditeur)
- Pour ce projet : 1 utilisateur → ~$9/mois

---

## 3. CloudWatch Custom Metrics

Avant de déployer Grafana, il faut que les données capteurs soient disponibles
dans CloudWatch sous forme de métriques (pas seulement des logs).

### 3.1 Métriques publiées par Lambda

Le Lambda `smart-assembly-processor` publie des métriques custom à chaque message :

```python
import boto3

cloudwatch = boto3.client("cloudwatch", region_name="eu-west-3")

def publish_metrics(payload: dict, statut: str):
    cloudwatch.put_metric_data(
        Namespace="SmartAssemblyLine",
        MetricData=[
            {
                "MetricName": "Vibration",
                "Dimensions": [{"Name": "Poste", "Value": payload["id_poste"]}],
                "Value": payload["vibration"],
                "Unit": "None",
            },
            {
                "MetricName": "Temperature",
                "Dimensions": [{"Name": "Poste", "Value": payload["id_poste"]}],
                "Value": payload["temperature"],
                "Unit": "None",
            },
            {
                "MetricName": "MessageCount",
                "Dimensions": [
                    {"Name": "Poste", "Value": payload["id_poste"]},
                    {"Name": "Statut", "Value": statut},
                ],
                "Value": 1,
                "Unit": "Count",
            },
        ],
    )
```

### 3.2 Namespace et dimensions

```
Namespace : SmartAssemblyLine
  Métriques :
    ├── Vibration
    │     Dimension : Poste = poste_1
    ├── Temperature
    │     Dimension : Poste = poste_1
    ├── MessageCount
    │     Dimensions : Poste = poste_1, Statut = CRITICAL
    │     Dimensions : Poste = poste_1, Statut = WARN
    │     Dimensions : Poste = poste_1, Statut = OK
    └── AnomalyScore   (Jour 32 — ML)
          Dimension : Poste = poste_1
```

---

## 4. Architecture Terraform (Jour 33)

### 4.1 Fichiers créés

```
terraform/environments/dev/
  grafana.tf          ← workspace Managed Grafana + IAM
  lambda_metrics.tf   ← permission CloudWatch put_metric_data pour Lambda
```

### 4.2 `grafana.tf`

```hcl
# IAM Role pour Grafana → CloudWatch
resource "aws_iam_role" "grafana" {
  name = "smart-assembly-grafana-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "grafana.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "grafana_cloudwatch" {
  name = "grafana-cloudwatch-read"
  role = aws_iam_role.grafana.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "cloudwatch:GetMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics",
        "logs:DescribeLogGroups",
        "logs:GetLogGroupFields",
        "logs:StartQuery",
        "logs:GetQueryResults",
      ]
      Resource = "*"
    }]
  })
}

# Workspace Managed Grafana
resource "aws_grafana_workspace" "smart_assembly" {
  name                     = "smart-assembly-monitoring"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn
  data_sources             = ["CLOUDWATCH"]
  notification_destinations = ["SNS"]
}

output "grafana_endpoint" {
  value = "https://${aws_grafana_workspace.smart_assembly.endpoint}"
}
```

### 4.3 Permission Lambda → CloudWatch

Ajouter dans le rôle Lambda existant :

```hcl
resource "aws_iam_role_policy" "lambda_cloudwatch_metrics" {
  name = "lambda-put-metrics"
  role = aws_iam_role.lambda_processor.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cloudwatch:PutMetricData"]
      Resource = "*"
    }]
  })
}
```

---

## 5. Dashboards Grafana

### 5.1 Dashboard : Vue temps réel capteurs

```
Panel 1 : Vibration poste_1 (Time series)
  Datasource : CloudWatch
  Namespace  : SmartAssemblyLine
  Metric     : Vibration
  Dimension  : Poste = poste_1
  Period     : 10s
  Stat       : Average
  Thresholds : vert < 2.0 | orange 2.0-2.5 | rouge > 2.5

Panel 2 : Température poste_1 (Time series)
  Metric     : Temperature
  Thresholds : vert < 80 | rouge > 80

Panel 3 : Comptage par statut (Bar gauge)
  Metric     : MessageCount
  Dimensions : Statut = CRITICAL / WARN / OK
  Stat       : Sum
  Period     : 5min

Panel 4 : Taux CRITICAL (Stat)
  Formule    : MessageCount{CRITICAL} / MessageCount{all} * 100
  Unit       : percent (0-100)
  Thresholds : vert < 5% | rouge > 5%
```

### 5.2 Dashboard : Anomalies ML (Jour 32)

```
Panel 1 : Anomaly Score (Time series)
  Metric     : AnomalyScore
  Dimension  : Poste = poste_1
  Stat       : Minimum
  Thresholds : rouge < -0.1 (anomalie détectée)

Panel 2 : Comptage anomalies ML (Stat)
  Metric     : MessageCount
  Dimension  : Statut = ANOMALY
  Stat       : Sum, Period 1h
```

### 5.3 Dashboard : Vue industrielle (équivalent SiteWise Monitor)

```
Row 1 : KPIs Temps Réel
  ├── Vibration instantanée (Gauge)
  ├── Température instantanée (Gauge)
  └── Statut global (State timeline)

Row 2 : Tendances 24h
  ├── Vibration moyenne/heure (Time series)
  └── Taux CRITICAL/heure (Time series)

Row 3 : Alertes
  └── Table : 10 derniers events CRITICAL (CloudWatch Logs Insights)
```

---

## 6. Alertes Grafana → SNS

Grafana Managed permet de déclencher des alertes natives vers SNS → Email/SMS.

```yaml
# Exemple règle d'alerte Grafana (format JSON simplifié)
alert:
  name: "Vibration critique poste_1"
  condition: avg(Vibration, 5min) > 2.5
  for: 2min   # doit durer 2 min pour éviter les faux positifs
  notify: SNS topic smart-assembly-alerts
```

---

## 7. Comparaison avec l'approche SiteWise

| Fonctionnalité | SiteWise Monitor | Managed Grafana + CW |
|---------------|-----------------|----------------------|
| Modèle asset structuré | ✅ | ❌ (CW dimensions) |
| OEE natif | ✅ | Manuel (formules) |
| Hiérarchie équipements | ✅ | ❌ |
| Flexibilité dashboards | Limitée | ✅ |
| Multi-datasources | ❌ | ✅ |
| Alertes | Via IoT Events | ✅ Natif |
| Disponibilité eu-west-3 | ❌ | ✅ |
| Coût | Par asset/mois | Par user actif |

**En production (eu-west-1)** : SiteWise pour la modélisation IIoT
\+ Managed Grafana avec datasource SiteWise native pour les dashboards.

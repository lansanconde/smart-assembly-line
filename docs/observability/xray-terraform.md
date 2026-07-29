# Terraform — AWS X-Ray (Lambda · ECS · Sampling Rules)

---

## Structure des fichiers

```
terraform/
├── xray.tf              ← Sampling rules + groupe X-Ray
├── lambda-xray.tf       ← Activation tracing Lambda
├── ecs-xray.tf          ← Sidecar daemon ECS
└── iam-xray.tf          ← Permissions IAM X-Ray
```

---

## xray.tf — Sampling Rules et Groupes

```hcl
# ── Sampling Rule : Anomalies → 100% tracées ─────────────────────

resource "aws_xray_sampling_rule" "anomalies" {
  rule_name      = "smart-assembly-anomalies"
  priority       = 100  # Plus bas = priorité plus haute
  reservoir_size = 10   # 10 traces/s garanties
  fixed_rate     = 1.0  # 100% des requêtes

  # Filtre : uniquement les invocations Lambda avec annotation statut=EN_INTERVENTION
  # (X-Ray filtre sur URL path et host — annotation = filtrage post-capture)
  host         = "*"
  http_method  = "*"
  url_path     = "*"
  service_name = "analyze_vibration"
  service_type = "AWS::Lambda::Function"
  resource_arn = aws_lambda_function.analyze_vibration.arn

  attributes = {}
}

# ── Sampling Rule : Trafic nominal → 5% ──────────────────────────

resource "aws_xray_sampling_rule" "nominal" {
  rule_name      = "smart-assembly-nominal"
  priority       = 9000  # Règle par défaut (priorité basse)
  reservoir_size = 1     # 1 trace/s garantie
  fixed_rate     = 0.05  # 5% du reste

  host         = "*"
  http_method  = "*"
  url_path     = "*"
  service_name = "*"
  service_type = "*"
  resource_arn = "*"

  attributes = {}
}

# ── Sampling Rule : Erreurs → 100% ───────────────────────────────

resource "aws_xray_sampling_rule" "errors" {
  rule_name      = "smart-assembly-errors"
  priority       = 50
  reservoir_size = 50
  fixed_rate     = 1.0

  host         = "*"
  http_method  = "*"
  url_path     = "/api/*"
  service_name = "supervision-api"
  service_type = "AWS::ECS::Container"
  resource_arn = "*"

  attributes = {}
}

# ── Groupe X-Ray : Anomalies uniquement ──────────────────────────

resource "aws_xray_group" "anomalies" {
  group_name        = "smart-assembly-anomalies"
  filter_expression = "annotation.statut = \"EN_INTERVENTION\" AND duration > 0.5"

  insights_configuration {
    insights_enabled      = true
    notifications_enabled = true  # → EventBridge quand anomalie détectée
  }
}

# ── Groupe X-Ray : Erreurs et timeouts ───────────────────────────

resource "aws_xray_group" "errors" {
  group_name        = "smart-assembly-errors"
  filter_expression = "fault = true OR error = true OR throttle = true"

  insights_configuration {
    insights_enabled      = true
    notifications_enabled = true
  }
}
```

---

## lambda-xray.tf — Activation tracing Lambda

```hcl
# Activation X-Ray sur les Lambdas existantes

resource "aws_lambda_function" "analyze_vibration" {
  # ... (config existante)

  # Activation X-Ray — mode Active = trace toutes les invocations éligibles
  tracing_config {
    mode = "Active"  # Active | PassThrough
  }

  # Layer aws-xray-sdk pour Python
  layers = [
    "arn:aws:lambda:eu-west-3::layer/AWSXRaySDKPython:1"
  ]

  environment {
    variables = {
      # Désactive le sampling côté SDK (géré par les Sampling Rules ci-dessus)
      AWS_XRAY_CONTEXT_MISSING = "LOG_ERROR"
    }
  }
}

resource "aws_lambda_function" "detect_anomaly" {
  # ... (config existante)

  tracing_config {
    mode = "Active"
  }

  layers = [
    "arn:aws:lambda::layer/AWSXRaySDKPython:1"
  ]
}
```

### Code Python — analyze_vibration instrumenté

```python
import time
import boto3
import os
from aws_xray_sdk.core import xray_recorder, patch_all

# Patche boto3 automatiquement → DynamoDB, SNS, EventBridge tracés
patch_all()

dynamodb = boto3.client('dynamodb', region_name='eu-west-3')
sns = boto3.client('sns', region_name='eu-west-3')

SEUILS = {
    'VIBRATION':   10.0,
    'TEMPERATURE': 80.0,
    'PRESSION':    6.0
}

def lambda_handler(event, context):
    site_id     = event.get('site_id', 'TLS')
    line_id     = event.get('line_id', 'A320')
    poste_id    = event.get('poste_id', 'P01')
    sensor_type = event.get('sensor_type', 'VIBRATION').upper()
    valeur      = float(event.get('valeur', 0))

    # Annotations indexées — filtrables dans X-Ray console et groupes
    xray_recorder.put_annotation('site_id', site_id)
    xray_recorder.put_annotation('sensor_type', sensor_type)
    xray_recorder.put_annotation('valeur', valeur)

    with xray_recorder.in_subsegment('threshold_check') as sub:
        seuil  = SEUILS.get(sensor_type, 10.0)
        statut = 'EN_INTERVENTION' if valeur > seuil else 'NOMINAL'
        anomalie_score = round(min(valeur / (seuil * 1.5), 1.0), 3)

        sub.put_annotation('statut', statut)
        sub.put_annotation('anomalie_score', anomalie_score)

        # Metadata (non indexée — contexte riche pour le debug)
        sub.put_metadata('threshold_context', {
            'seuil': seuil,
            'valeur': valeur,
            'ratio': round(valeur / seuil, 2)
        })

    site_poste_id = f"{site_id}#{line_id}#{poste_id}"

    # DynamoDB tracé automatiquement par patch_all()
    dynamodb.update_item(
        TableName='machine_state_v2',
        Key={
            'site_poste_id': {'S': site_poste_id},
            'sensor_type':   {'S': sensor_type}
        },
        UpdateExpression='SET statut = :s, valeur_last = :v, '
                         'timestamp_last = :t, anomalie_score = :a, '
                         'ttl = :ttl',
        ExpressionAttributeValues={
            ':s':   {'S': statut},
            ':v':   {'N': str(valeur)},
            ':t':   {'S': event.get('timestamp', '')},
            ':a':   {'N': str(anomalie_score)},
            ':ttl': {'N': str(int(time.time()) + 30 * 86400)}
        }
    )

    if statut == 'EN_INTERVENTION':
        # SNS tracé automatiquement par patch_all()
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f'ALERTE {sensor_type} — {site_poste_id}',
            Message=f'Valeur: {valeur} (seuil: {seuil}) | Score: {anomalie_score}'
        )

    return {
        'statusCode': 200,
        'site_poste_id': site_poste_id,
        'statut': statut,
        'anomalie_score': anomalie_score
    }
```

---

## ecs-xray.tf — Sidecar Daemon ECS

```hcl
# Task Definition supervision-api avec sidecar X-Ray

resource "aws_ecs_task_definition" "supervision_api" {
  family                   = "supervision-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    # ── Container principal ───────────────────────────────────────
    {
      name      = "supervision-api"
      image     = "${aws_ecr_repository.supervision_api.repository_url}:latest"
      essential = true

      portMappings = [{
        containerPort = 8080
        protocol      = "tcp"
      }]

      environment = [
        { name = "AWS_XRAY_DAEMON_ADDRESS", value = "127.0.0.1:2000" },
        { name = "AWS_XRAY_CONTEXT_MISSING", value = "LOG_ERROR" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/supervision-api"
          "awslogs-region"        = "eu-west-3"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    },

    # ── Sidecar X-Ray Daemon ──────────────────────────────────────
    {
      name      = "xray-daemon"
      image     = "amazon/aws-xray-daemon:latest"
      essential = false  # Ne bloque pas le démarrage si le daemon fail

      portMappings = [{
        containerPort = 2000
        protocol      = "udp"
      }]

      # Limite les ressources du sidecar
      cpu    = 32
      memory = 256

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/xray-daemon"
          "awslogs-region"        = "eu-west-3"
          "awslogs-stream-prefix" = "xray"
        }
      }

      environment = [
        { name = "AWS_REGION", value = "eu-west-3" }
      ]
    }
  ])
}
```

### Code Python — supervision-api instrumenté (Flask/FastAPI)

```python
# app.py — FastAPI avec X-Ray middleware

from fastapi import FastAPI
from aws_xray_sdk.core import xray_recorder, patch_all
from aws_xray_sdk.ext.aiohttp.middleware import middleware as xray_middleware
import boto3

patch_all()

xray_recorder.configure(
    service='supervision-api',
    daemon_address='127.0.0.1:2000',
    plugins=('ECSPlugin',)  # Ajoute le contexte ECS (task ID, cluster) aux traces
)

app = FastAPI()
dynamodb = boto3.resource('dynamodb', region_name='eu-west-3')

@app.get('/api/postes/{site_poste_id}')
async def get_poste_state(site_poste_id: str):
    # Annotations sur la requête courante
    xray_recorder.put_annotation('site_poste_id', site_poste_id)
    xray_recorder.put_annotation('endpoint', 'get_poste_state')

    # DynamoDB tracé automatiquement par patch_all()
    table = dynamodb.Table('machine_state_v2')
    response = table.query(
        KeyConditionExpression='site_poste_id = :pk',
        ExpressionAttributeValues={':pk': site_poste_id}
    )

    items = response.get('Items', [])
    xray_recorder.put_annotation('items_returned', len(items))

    return {'site_poste_id': site_poste_id, 'capteurs': items}

@app.get('/health')
async def health():
    # Route de health check → exclure du tracing (bruit)
    return {'status': 'ok'}
```

---

## iam-xray.tf — Permissions IAM

```hcl
# Politique IAM pour Lambda — écriture dans X-Ray
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Politique IAM pour ECS Task Role — écriture dans X-Ray
resource "aws_iam_role_policy_attachment" "ecs_task_xray" {
  role       = aws_iam_role.ecs_task.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Politique inline minimale si on veut restreindre plus finement
resource "aws_iam_role_policy" "xray_write" {
  name = "smart-assembly-xray-write"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords",
        "xray:GetSamplingRules",
        "xray:GetSamplingTargets",
        "xray:GetSamplingStatisticSummaries"
      ]
      Resource = "*"
    }]
  })
}
```

---

## Coût estimé X-Ray

```
COMPOSANT              USAGE (DEV)              COÛT/MOIS
──────────────────────────────────────────────────────────
Traces enregistrées    100K traces/mois          ~0.50 €
                       (Free tier : 100K/mois)   ~0 € ✓

Traces scannées        Requêtes console X-Ray    ~0 €
                       (Free tier : 1M scans)    ~0 € ✓

X-Ray Insights         Activé sur 2 groupes      ~0 €
                       (inclus dans le service)

──────────────────────────────────────────────────────────
TOTAL X-RAY (dev)                               ~0 €/mois
(dans le Free Tier — 100K traces gratuites/mois)

En production (100K capteurs) :
  ~5M traces/mois → ~25 €/mois
  Rapport valeur/coût : excellent (debug = économie de temps ingénieur)
```

---

## Requêtes X-Ray utiles (console / CLI)

```powershell
# Lister les traces avec erreurs des 30 dernières minutes
aws xray get-trace-summaries \
  --start-time $(date -d '30 minutes ago' +%s) \
  --end-time $(date +%s) \
  --filter-expression 'fault = true OR error = true' \
  --region eu-west-3

# Traces d'anomalies par site
aws xray get-trace-summaries \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --filter-expression 'annotation.statut = "EN_INTERVENTION"' \
  --region eu-west-3

# Service Map des 5 dernières minutes
aws xray get-service-graph \
  --start-time $(date -d '5 minutes ago' +%s) \
  --end-time $(date +%s) \
  --region eu-west-3
```

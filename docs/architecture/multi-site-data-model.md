# Modèle de données multi-site — DynamoDB

> Adaptation du schéma `machine_state` pour supporter 100 000 capteurs répartis sur plusieurs sites industriels.

---

## 1. Schéma de la table principale

### `machine_state_v2`

| Attribut | Type | Rôle |
|---|---|---|
| `site_poste_id` | STRING (PK) | `"{site}#{ligne}#{poste}"` — ex: `"TLS#A320#P12"` |
| `sensor_type` | STRING (SK) | `"VIBRATION"` / `"TEMPERATURE"` / `"PRESSION"` |
| `site_id` | STRING | Code site — `"TLS"`, `"HAM"`, `"MOB"` |
| `line_id` | STRING | Code ligne — `"A320"`, `"A350"` |
| `poste_id` | STRING | Identifiant poste — `"P12"` |
| `statut` | STRING | `"NOMINAL"` / `"EN_INTERVENTION"` / `"ALERTE"` |
| `valeur_last` | NUMBER | Dernière mesure du capteur |
| `timestamp_last` | STRING | ISO 8601 — `"2026-07-29T14:23:11Z"` |
| `anomalie_score` | NUMBER | Score ML 0.0 → 1.0 (0 = normal, 1 = critique) |
| `ttl` | NUMBER | Unix timestamp — expiration automatique après 30 jours |

### GSI — `statut-site-index`

| Attribut | Type | Rôle |
|---|---|---|
| `statut` | STRING (PK) | Filtrer par statut global |
| `site_id` | STRING (SK) | Sous-filtrer par site |

**Projection :** `ALL` (tous les attributs projetés dans le GSI)

**Usage :** tableau de bord superviseur — "tous les postes EN_INTERVENTION, triés par site"

---

## 2. Exemples d'items

```json
// Poste 12, Ligne A320, Site Toulouse — capteur vibration
{
  "site_poste_id": "TLS#A320#P12",
  "sensor_type": "VIBRATION",
  "site_id": "TLS",
  "line_id": "A320",
  "poste_id": "P12",
  "statut": "EN_INTERVENTION",
  "valeur_last": 12.7,
  "timestamp_last": "2026-07-29T14:23:11Z",
  "anomalie_score": 0.92,
  "ttl": 1753747391
}

// Poste 01, Ligne A350, Site Hambourg — capteur température
{
  "site_poste_id": "HAM#A350#P01",
  "sensor_type": "TEMPERATURE",
  "site_id": "HAM",
  "line_id": "A350",
  "poste_id": "P01",
  "statut": "NOMINAL",
  "valeur_last": 67.3,
  "timestamp_last": "2026-07-29T14:23:09Z",
  "anomalie_score": 0.05,
  "ttl": 1753747389
}
```

---

## 3. Patterns d'accès (Access Patterns)

### AP1 — État de tous les capteurs d'un poste

```python
# "Donne-moi tous les capteurs du poste P12, ligne A320, site Toulouse"
response = dynamodb.query(
    TableName='machine_state_v2',
    KeyConditionExpression='site_poste_id = :pk',
    ExpressionAttributeValues={
        ':pk': {'S': 'TLS#A320#P12'}
    }
)
# Retourne les 3 items : VIBRATION + TEMPERATURE + PRESSION pour ce poste
```

### AP2 — Tous les incidents actifs d'un site

```python
# "Tous les postes EN_INTERVENTION du site Toulouse"
response = dynamodb.query(
    TableName='machine_state_v2',
    IndexName='statut-site-index',
    KeyConditionExpression='statut = :s AND site_id = :site',
    ExpressionAttributeValues={
        ':s':    {'S': 'EN_INTERVENTION'},
        ':site': {'S': 'TLS'}
    }
)
```

### AP3 — Dashboard global — tous les incidents, tous les sites

```python
# "Tous les postes EN_INTERVENTION sur tous les sites"
response = dynamodb.query(
    TableName='machine_state_v2',
    IndexName='statut-site-index',
    KeyConditionExpression='statut = :s',
    ExpressionAttributeValues={
        ':s': {'S': 'EN_INTERVENTION'}
    }
)
```

### AP4 — Mise à jour d'un capteur (IoT → Lambda)

```python
# Lambda analyze_vibration met à jour l'état d'un capteur
dynamodb.update_item(
    TableName='machine_state_v2',
    Key={
        'site_poste_id': {'S': 'TLS#A320#P12'},
        'sensor_type':   {'S': 'VIBRATION'}
    },
    UpdateExpression='SET statut = :s, valeur_last = :v, '
                     'timestamp_last = :t, anomalie_score = :a, '
                     'ttl = :ttl',
    ExpressionAttributeValues={
        ':s':   {'S': 'EN_INTERVENTION'},
        ':v':   {'N': '12.7'},
        ':t':   {'S': '2026-07-29T14:23:11Z'},
        ':a':   {'N': '0.92'},
        ':ttl': {'N': str(int(time.time()) + 30 * 86400)}  # +30 jours
    }
)
```

---

## 4. Migration depuis le schéma mono-site

### Script de migration (Python/Boto3)

```python
import boto3
import time

dynamodb = boto3.resource('dynamodb', region_name='eu-west-3')

old_table = dynamodb.Table('machine_state')
new_table = dynamodb.Table('machine_state_v2')

# Mapping des anciens IDs vers la nouvelle structure
MIGRATION_MAP = {
    'poste_1': {'site_id': 'TLS', 'line_id': 'A320', 'poste_id': 'P01'},
    'poste_2': {'site_id': 'TLS', 'line_id': 'A320', 'poste_id': 'P02'},
    # ... compléter pour chaque poste existant
}

def migrate_item(old_item):
    """Convertit un item mono-site vers le schéma multi-site."""
    poste = old_item['id_poste']
    mapping = MIGRATION_MAP.get(poste, {
        'site_id': 'TLS',
        'line_id': 'A320',
        'poste_id': poste
    })
    
    site_poste_id = f"{mapping['site_id']}#{mapping['line_id']}#{mapping['poste_id']}"
    
    # Déterminer le type de capteur depuis l'anomalie_type existant
    sensor_type = old_item.get('anomalie_type', 'VIBRATION')
    
    new_item = {
        'site_poste_id': site_poste_id,
        'sensor_type':   sensor_type,
        'site_id':       mapping['site_id'],
        'line_id':       mapping['line_id'],
        'poste_id':      mapping['poste_id'],
        'statut':        old_item.get('statut', 'NOMINAL'),
        'valeur_last':   old_item.get('temperature_last', 0),
        'timestamp_last': old_item.get('timestamp_last', ''),
        'anomalie_score': 0.0,
        'ttl': int(time.time()) + 30 * 86400
    }
    return new_item

# Scan complet de l'ancienne table et insertion dans la nouvelle
scan = old_table.scan()
for item in scan['Items']:
    new_item = migrate_item(item)
    new_table.put_item(Item=new_item)
    print(f"Migré: {new_item['site_poste_id']} / {new_item['sensor_type']}")

print("Migration terminée.")
```

---

## 5. Terraform — Définition de la table multi-site

```hcl
resource "aws_dynamodb_table" "machine_state_v2" {
  name         = "machine_state_v2"
  billing_mode = "PAY_PER_REQUEST"  # En dev — passer à PROVISIONED en prod

  # Clé primaire composite
  hash_key  = "site_poste_id"
  range_key = "sensor_type"

  attribute {
    name = "site_poste_id"
    type = "S"
  }

  attribute {
    name = "sensor_type"
    type = "S"
  }

  attribute {
    name = "statut"
    type = "S"
  }

  attribute {
    name = "site_id"
    type = "S"
  }

  # GSI pour la supervision globale par statut + site
  global_secondary_index {
    name               = "statut-site-index"
    hash_key           = "statut"
    range_key          = "site_id"
    projection_type    = "ALL"
  }

  # TTL automatique — expiration des données froides
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }

  # Chiffrement avec KMS CMK (cohérent avec l'existant)
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb_key.arn
  }

  tags = {
    Project     = "smart-assembly-line"
    Environment = "dev"
    Jour        = "45"
  }
}

# Auto Scaling pour la production (100K capteurs)
resource "aws_appautoscaling_target" "dynamodb_write" {
  count              = var.environment == "prod" ? 1 : 0
  max_capacity       = 15000
  min_capacity       = 5000
  resource_id        = "table/${aws_dynamodb_table.machine_state_v2.name}"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  service_namespace  = "dynamodb"
}

resource "aws_appautoscaling_policy" "dynamodb_write_policy" {
  count              = var.environment == "prod" ? 1 : 0
  name               = "machine-state-v2-write-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dynamodb_write[0].resource_id
  scalable_dimension = aws_appautoscaling_target.dynamodb_write[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.dynamodb_write[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }
    target_value = 70.0  # Maintenir l'utilisation à 70%
  }
}
```

---

## 6. Dimensionnement justifié — 100 000 capteurs

### Calcul des WCU

```
Hypothèses :
  Capteurs              : 100 000
  Fréquence             : 1 update / 10s par capteur (après agrégation Greengrass)
  Taille item           : ~500 octets = 1 WCU (arrondi au Ko supérieur)

Calcul :
  WCU/s = 100 000 capteurs / 10 s = 10 000 WCU/s

  Avec 20% de marge :  10 000 × 1.2 = 12 000 WCU provisioned
```

### Calcul des RCU

```
Hypothèses :
  Dashboards actifs     : 100 requêtes/s (opérateurs supervision)
  Items par requête     : 10 postes en moyenne (Query PK par poste)
  Taille item           : ~500 octets < 4 Ko → 1 RCU par item

Calcul :
  RCU/s = 100 requêtes/s × 10 items = 1 000 RCU/s

  Avec 20% de marge :  1 000 × 1.2 = 1 200 RCU provisioned
```

### Seuil PAY_PER_REQUEST vs Provisioned

```
PAY_PER_REQUEST :
  WCU    : 1.4132 € / million d'unités
  RCU    : 0.2832 € / million d'unités

  10 000 WCU/s × 86 400 s/j × 30 j = 25.9 milliards WCU/mois
  Coût   : 25 900 × 1.4132 = ~36 600 €/mois  ← INACCEPTABLE

Provisioned + Auto Scaling :
  12 000 WCU × 0.000765 €/h × 720h = ~6 628 €/mois
   1 200 RCU × 0.000153 €/h × 720h = ~132 €/mois
  ──────────────────────────────────────────────────────
  Total DynamoDB (prod) :             ~6 760 €/mois

  → Passage PAY_PER_REQUEST → Provisioned = économie de ~82%

Seuil de bascule :
  ~200 WCU/s continus = point d'équilibre → au-delà, Provisioned est plus économique
```

### Estimation stockage

```
Items en table :
  100 000 capteurs × 3 types = 300 000 items
  Taille moyenne : 500 octets
  Stockage total : 300 000 × 500 o = ~150 Mo → ~0.03 €/mois (négligeable)

Items GSI (projection ALL) :
  Même volume, dupliqué pour le GSI statut-site-index
  Stockage GSI   : ~150 Mo → ~0.03 €/mois

TTL — rotation automatique :
  30 jours de données max en table
  Anciennes données → S3 data lake via DynamoDB Streams (si activé)
```

---

## 7. Évolution — Topics MQTT adaptés

Adaptation du code Lambda `analyze_vibration` pour extraire `site_id` depuis le topic MQTT :

```python
# IoT Rule SQL — extraction automatique du contexte site depuis le topic
# FROM 'smart-assembly/+/+/+/+'
# SELECT *, topic(2) AS site_id, topic(3) AS line_id,
#          topic(4) AS poste_id, topic(5) AS sensor_type

def lambda_handler(event, context):
    # Le topic MQTT injecte automatiquement site_id, line_id, poste_id
    site_id    = event.get('site_id', 'TLS')     # fourni par IoT Rule
    line_id    = event.get('line_id', 'A320')
    poste_id   = event.get('poste_id', 'P01')
    sensor_type = event.get('sensor_type', 'VIBRATION').upper()
    
    # Construction de la clé composite
    site_poste_id = f"{site_id}#{line_id}#{poste_id}"
    
    valeur = float(event.get('valeur', 0))
    seuil  = SEUILS.get(sensor_type, 10.0)
    
    statut = 'EN_INTERVENTION' if valeur > seuil else 'NOMINAL'
    anomalie_score = min(valeur / (seuil * 1.5), 1.0)
    
    # Écriture dans machine_state_v2
    dynamodb.update_item(
        TableName='machine_state_v2',
        Key={
            'site_poste_id': {'S': site_poste_id},
            'sensor_type':   {'S': sensor_type}
        },
        UpdateExpression='SET statut = :s, valeur_last = :v, '
                         'site_id = :sid, line_id = :lid, poste_id = :pid, '
                         'timestamp_last = :t, anomalie_score = :a, ttl = :ttl',
        ExpressionAttributeValues={
            ':s':   {'S': statut},
            ':v':   {'N': str(valeur)},
            ':sid': {'S': site_id},
            ':lid': {'S': line_id},
            ':pid': {'S': poste_id},
            ':t':   {'S': datetime.utcnow().isoformat() + 'Z'},
            ':a':   {'N': str(round(anomalie_score, 3))},
            ':ttl': {'N': str(int(time.time()) + 30 * 86400)}
        }
    )
    
    return {'statusCode': 200, 'site_poste_id': site_poste_id, 'statut': statut}
```

# AWS CloudTrail — Audit & Traçabilité 

> Implémentation déployée en eu-west-3 (Paris).
> Trail multi-région, stockage S3 chiffré KMS, alertes IAM via CloudWatch.

---

## 1. Positionnement dans la stack

```
Toute action AWS (console, CLI, SDK, Terraform)
    │ API call
    ▼
CloudTrail
    ├── Event History (90 jours, gratuit, console)
    └── Trail (persistance longue durée)
            ├── S3 : smart-assembly-cloudtrail-logs/
            │       └── Athena (requêtes SQL sur les logs)
            └── CloudWatch Logs : /aws/cloudtrail/smart-assembly
                    └── Metric Filter → Alarm → SNS (alerte IAM)
```

**CloudWatch** répond à la question "que fait mon système en ce moment ?"
**CloudTrail** répond à "qui a fait quoi sur mon infrastructure, et quand ?"

---

## 2. Concepts fondamentaux

### 2.1 Types d'événements

| Type | Contenu | Coût | Cas d'usage |
|------|---------|------|-------------|
| **Management events** | Actions sur les ressources AWS (CreateBucket, PutRolePolicy, InvokeFunction...) | Gratuit (1 trail) | Audit IAM, changements infra |
| **Data events** | Opérations sur les données (S3 GetObject, DynamoDB GetItem, Lambda Invoke) | Payant (~$0.10/100k) | Traçabilité accès données |
| **Insights events** | Détection d'activité anormale (pic d'appels API inhabituels) | Payant | Détection intrusion |

**Pour SmartAssemblyLine** : Management events suffisent — on veut tracer les changements
d'infrastructure (IAM, Lambda, IoT Core) pas chaque accès DynamoDB.

### 2.2 Structure d'un événement CloudTrail

```json
{
  "eventTime":       "2026-07-24T10:15:30Z",
  "eventSource":     "iam.amazonaws.com",
  "eventName":       "PutRolePolicy",
  "userIdentity": {
    "type":          "IAMUser",
    "userName":      "lansana-admin",
    "arn":           "arn:aws:iam::169237360990:user/lansana-admin"
  },
  "sourceIPAddress": "90.x.x.x",
  "requestParameters": {
    "roleName":      "smart-assembly-lambda-role",
    "policyName":    "smart-assembly-lambda-dynamodb"
  },
  "responseElements": null,
  "awsRegion":       "eu-west-3"
}
```

Chaque événement contient : **qui** (userIdentity), **quoi** (eventName),
**sur quoi** (requestParameters), **depuis où** (sourceIPAddress), **quand** (eventTime).

### 2.3 Trail — portée et configuration

**Single-region vs Multi-region** :

```
Single-region : enregistre uniquement les events de eu-west-3
Multi-region  : enregistre tous les events de toutes les régions
                + events globaux (IAM, STS, CloudFront — toujours us-east-1)
```

**Pour un projet prod** : toujours multi-région. Un attaquant qui crée un rôle IAM
en us-east-1 pour accéder à tes ressources en eu-west-3 ne serait pas tracé
par un trail single-region.

### 2.4 Validation de l'intégrité des logs

CloudTrail peut signer chaque fichier de log avec un digest SHA-256.
Si un log est modifié ou supprimé, la validation détecte la falsification.

```bash
aws cloudtrail validate-logs \
  --trail-arn arn:aws:cloudtrail:eu-west-3:169237360990:trail/smart-assembly-trail \
  --start-time 2026-07-01T00:00:00Z
```

Obligatoire dans les contextes réglementaires (aérospatial, finance, santé).

---

## 3. Intégration CloudWatch Logs

### 3.1 Pourquoi envoyer CloudTrail dans CloudWatch Logs ?

S3 = stockage froid (Athena pour requêtes batch).
CloudWatch Logs = temps réel → **Metric Filters → Alarms → SNS**.

On peut alerter en temps réel sur :
- Modification d'une policy IAM critique
- Suppression d'un bucket S3
- Désactivation de CloudTrail lui-même
- Connexion root account

### 3.2 Metric Filter — syntaxe

```
{ ($.eventName = "PutRolePolicy") || ($.eventName = "DeleteRolePolicy")
  || ($.eventName = "AttachRolePolicy") || ($.eventName = "DetachRolePolicy") }
```

Ce filtre capture toute modification de policy IAM → métrique CloudWatch
→ alarm → email SNS si déclenché hors heures ouvrées ou par un utilisateur inattendu.

---

## 4. Architecture Terraform (Jour 37)

### 4.1 Fichier créé

```
terraform/environments/dev/
  cloudtrail.tf   ← Trail + S3 bucket dédié + CW Logs + metric filter + alarm
```

### 4.2 Ressources déployées

```
aws_s3_bucket.cloudtrail_logs
  ├── aws_s3_bucket_policy.cloudtrail_logs   ← autorise CloudTrail à écrire
  └── aws_s3_bucket_server_side_encryption_configuration (KMS)

aws_cloudwatch_log_group.cloudtrail
aws_iam_role.cloudtrail_cw                  ← CloudTrail → CW Logs
aws_iam_role_policy.cloudtrail_cw

aws_cloudtrail.main
  ├── is_multi_region_trail = true
  ├── include_global_service_events = true
  ├── enable_log_file_validation = true
  └── cloud_watch_logs_group_arn = aws_cloudwatch_log_group.cloudtrail.arn

aws_cloudwatch_log_metric_filter.iam_changes
aws_cloudwatch_metric_alarm.iam_changes     → aws_sns_topic.alerts (existant)
```

---

## 5. Athena — requêtes SQL sur CloudTrail

Pour des investigations post-incident, Athena permet d'interroger les logs S3
directement en SQL.

```sql
-- Qui a modifié les policies IAM aujourd'hui ?
SELECT eventTime, userIdentity.userName, eventName, requestParameters
FROM cloudtrail_logs
WHERE eventSource = 'iam.amazonaws.com'
  AND eventName IN ('PutRolePolicy', 'AttachRolePolicy', 'DeleteRolePolicy')
  AND eventTime > '2026-07-24'
ORDER BY eventTime DESC
LIMIT 20;

-- Toutes les invocations Lambda des 24 dernières heures
SELECT eventTime, userIdentity.arn, requestParameters
FROM cloudtrail_logs
WHERE eventSource = 'lambda.amazonaws.com'
  AND eventName = 'Invoke'
  AND eventTime > '2026-07-23'
ORDER BY eventTime DESC;

-- Connexions root (critique — ne devrait jamais apparaître)
SELECT eventTime, sourceIPAddress, eventName
FROM cloudtrail_logs
WHERE userIdentity.type = 'Root'
ORDER BY eventTime DESC;
```

---

## 6. Bonnes pratiques production

**Bucket CloudTrail séparé** : ne jamais stocker les logs CloudTrail dans le même
bucket que les données métier — un attaquant qui compromet le bucket data
ne doit pas pouvoir effacer ses traces.

**Chiffrement KMS CMK** : utiliser une clé gérée par le client (pas SSE-S3)
pour pouvoir auditer les accès aux logs eux-mêmes via CloudTrail (oui, CloudTrail
loggue l'accès à ses propres logs si chiffré en CMK).

**Protection contre la suppression** : activer `enable_log_file_validation = true`
+ S3 Object Lock sur le bucket → les logs deviennent immuables.

**Alertes minimum en production** :
- Connexion root
- Modification CloudTrail (désactivation du trail)
- Modification des policies IAM admin
- Suppression de ressources critiques (bucket S3, table DynamoDB)

**Rétention** : 90 jours dans CloudWatch Logs (coût maîtrisé),
1 an dans S3 Standard, puis Glacier pour conformité réglementaire.

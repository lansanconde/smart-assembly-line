# Runbook — Administration du projet

Document opérationnel vivant. Mis à jour à chaque nouveau composant déployé.

!!! tip "Récupérer les IDs de vos ressources"
    Les placeholders `<VPC_ID>`, `<SUBNET_*_ID>` etc. sont à remplacer par vos IDs réels.
    Pour les retrouver rapidement :
    ```bash
    # VPC
    aws ec2 describe-vpcs --filters "Name=tag:Name,Values=smart-assembly-vpc" --query "Vpcs[0].VpcId"

    # Subnets
    aws ec2 describe-subnets --filters "Name=tag:Name,Values=smart-assembly-subnet-*" --query "Subnets[*].{Nom:Tags[0].Value,ID:SubnetId}"

    # Internet Gateway
    aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=smart-assembly-igw" --query "InternetGateways[0].InternetGatewayId"
    ```

---

## Terraform

### Voir ce qui va être créé / modifié avant d'appliquer
```powershell
cd C:\Users\conde\smart-assembly-line\infra
terraform plan
```

### Déployer les changements
```powershell
terraform apply
```

### Voir l'état actuel de l'infrastructure
```powershell
terraform show
```

### Lister toutes les ressources gérées par Terraform
```powershell
terraform state list
```

### Inspecter une ressource spécifique
```powershell
terraform state show aws_vpc.main
```

### Détruire une ressource spécifique (attention)
```powershell
terraform destroy -target=aws_subnet.public
```

---

## IAM

### Lister les rôles du projet
```powershell
aws iam list-roles --query "Roles[?contains(RoleName, 'smart-assembly')].{Nom:RoleName,ARN:Arn}"
```

### Voir les policies attachées à un rôle
```powershell
aws iam list-attached-role-policies --role-name smart-assembly-lambda-role
```

### Vérifier l'identité courante (quel user/role est actif)
```powershell
aws sts get-caller-identity
```

### Révoquer les access keys d'un utilisateur compromis
```powershell
aws iam delete-access-key --user-name NOM_USER --access-key-id AKIAXXXXXXXX
```

---

## VPC

### Vérifier l'état du VPC
```powershell
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=smart-assembly-vpc" \
  --query "Vpcs[0].{ID:VpcId,CIDR:CidrBlock}"
```

### Vérifier les subnets
```powershell
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<VPC_ID>" \
  --query "Subnets[*].{Nom:Tags[0].Value,CIDR:CidrBlock,Public:MapPublicIpOnLaunch}"
```

### Vérifier les route tables et leurs associations
```powershell
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<VPC_ID>" \
  --query "RouteTables[*].{Nom:Tags[0].Value,Routes:Routes[*].DestinationCidrBlock,Subnets:Associations[*].SubnetId}"
```

### Vérifier l'Internet Gateway
```powershell
aws ec2 describe-internet-gateways --filters "Name=tag:Name,Values=smart-assembly-igw" \
  --query "InternetGateways[0].{ID:InternetGatewayId,VPC:Attachments[0].VpcId}"
```

---

## Git

### Workflow standard
```powershell
git add .
git status                   # vérifier ce qui part
git commit -m "feat(scope): description"
git push origin main
```

### Vérifier qu'aucun secret ne part dans le commit
```powershell
git diff --cached            # voir exactement ce qui est stagé
```

### Annuler le dernier commit sans perdre les fichiers
```powershell
git reset --soft HEAD~1
```

---

## S3

### Vérifier le versioning du bucket
```bash
aws s3api get-bucket-versioning --bucket smart-assembly-raw-data-<ACCOUNT_ID>
```
Réponse attendue : `{ "Status": "Enabled" }`

### Vérifier le chiffrement
```bash
aws s3api get-bucket-encryption --bucket smart-assembly-raw-data-<ACCOUNT_ID>
```

### Vérifier le block public access
```bash
aws s3api get-public-access-block --bucket smart-assembly-raw-data-<ACCOUNT_ID>
```
Les 4 valeurs doivent être `true`.

### Lister les objets d'une partition
```bash
aws s3 ls s3://smart-assembly-raw-data-<ACCOUNT_ID>/YYYY/MM/DD/HH/
```

### Uploader un objet de test
```bash
echo '{"id_poste":"poste-1","vibration":1.24,"timestamp":"2026-07-08T10:00:00Z"}' > test.json
aws s3 cp test.json s3://smart-assembly-raw-data-<ACCOUNT_ID>/2026/07/08/10/poste-1_test.json
```

### Supprimer un objet de test
```bash
aws s3 rm s3://smart-assembly-raw-data-<ACCOUNT_ID>/2026/07/08/10/poste-1_test.json
```

### Lister toutes les versions d'un objet (versioning)
```bash
aws s3api list-object-versions   --bucket smart-assembly-raw-data-<ACCOUNT_ID>   --prefix 2026/07/08/10/poste-1_test.json
```

---

## DynamoDB

!!! tip "JSON sous PowerShell"
    Utilise `[System.IO.File]::WriteAllText` pour créer les fichiers JSON sans BOM,
    puis passe-les à AWS CLI via `file://fichier.json`.

### Vérifier que la table existe
```bash
aws dynamodb describe-table --table-name machine_state   --query "Table.{Nom:TableName,Statut:TableStatus,Billing:BillingModeSummary.BillingMode}"
```

### Insérer un item (PowerShell)
```powershell
[System.IO.File]::WriteAllText("$PWD\item.json", '{"id_poste":{"S":"poste-1"},"statut":{"S":"OK"},"vibration_last":{"N":"1.24"},"temperature_last":{"N":"72.3"},"timestamp_last":{"S":"2026-07-08T10:00:00Z"}}')
aws dynamodb put-item --table-name machine_state --item file://item.json
```

### Lire un item par clé
```powershell
[System.IO.File]::WriteAllText("$PWD\key.json", '{"id_poste":{"S":"poste-1"}}')
aws dynamodb get-item --table-name machine_state --key file://key.json
```

### Supprimer un item
```bash
aws dynamodb delete-item --table-name machine_state --key file://key.json
```

### Scanner tous les items de la table (attention — coûteux en production)
```bash
aws dynamodb scan --table-name machine_state
```

### Vérifier le mode de facturation de la table
```powershell
aws dynamodb describe-table --table-name machine_state `
  --query "Table.BillingModeSummary.BillingMode"
```

### Observer les événements de throttling (CloudWatch)
```powershell
aws cloudwatch get-metric-statistics `
  --namespace AWS/DynamoDB `
  --metric-name WriteThrottleEvents `
  --dimensions Name=TableName,Value=machine_state `
  --start-time 1784000000 `
  --end-time 1784010000 `
  --period 60 `
  --statistics Sum
```

### Passer en provisionné (lab chaos uniquement — à remettre en on-demand après)
```hcl
# Dans dynamodb.tf — temporaire pour tester le throttling
billing_mode   = "PROVISIONED"
read_capacity  = 1
write_capacity = 1
```

!!! warning "Toujours remettre en PAY_PER_REQUEST après le lab"
    Le mode provisionné avec `write_capacity = 1` est volontairement sous-dimensionné.
    Après le test, remettre `billing_mode = "PAY_PER_REQUEST"` et supprimer `read_capacity` / `write_capacity`.

### Requêter par statut via le GSI statut-index
```powershell
[System.IO.File]::WriteAllText("$PWD\expr_gsi.json", '{":s":{"S":"EN_INTERVENTION"}}')
aws dynamodb query `
  --table-name machine_state `
  --index-name statut-index `
  --key-condition-expression "statut = :s" `
  --expression-attribute-values file://expr_gsi.json `
  --query "Items[*].id_poste"
```

Remplace `EN_INTERVENTION` par `OK`, `WARN` ou `CRITICAL` selon le besoin.

!!! tip "GSI — consistance éventuelle"
    Le GSI `statut-index` est mis à jour de façon asynchrone après chaque écriture sur la table principale.
    Un poste passé `EN_INTERVENTION` dans la dernière seconde peut ne pas encore apparaître dans le résultat.
    Pour une lecture forte consistance, utiliser `GetItem` sur la table principale avec `id_poste`.

### Vérifier le PITR (Point-in-Time Recovery)
```bash
aws dynamodb describe-continuous-backups --table-name machine_state   --query "ContinuousBackupsDescription.PointInTimeRecoveryDescription"
```

---

## EventBridge

### Envoyer un événement de test sur le bus custom
```powershell
# Créer le fichier event
@'
[{"Source":"smart-assembly.iot","DetailType":"anomalie.critique","EventBusName":"smart-assembly-events","Detail":"{\"id_poste\":\"poste_1\",\"statut\":\"CRITICAL\",\"regle\":\"vibration.critique\",\"mesures\":{\"vibration\":3.1,\"temperature\":72,\"pression\":4.2}}"}]
'@ | Out-File -FilePath event_test.json -Encoding utf8

# Envoyer
aws events put-events --entries file://event_test.json
```

### Vérifier les règles de routage sur le bus
```bash
aws events list-rules --event-bus-name smart-assembly-events \
  --query "Rules[*].{Nom:Name,Statut:State,Pattern:EventPattern}"
```

### Vérifier les targets d'une règle
```bash
aws events list-targets-by-rule \
  --rule smart-assembly-critical-to-sqs \
  --event-bus-name smart-assembly-events
```

---

## SQS

### Lire un message dans la queue d'intervention (sans le supprimer)
```bash
aws sqs receive-message \
  --queue-url https://sqs.eu-west-3.amazonaws.com/169237360990/smart-assembly-intervention \
  --max-number-of-messages 1
```

### Voir le nombre de messages en attente
```bash
aws sqs get-queue-attributes \
  --queue-url https://sqs.eu-west-3.amazonaws.com/169237360990/smart-assembly-intervention \
  --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible
```

### Vérifier la DLQ (messages en échec)
```bash
aws sqs get-queue-attributes \
  --queue-url https://sqs.eu-west-3.amazonaws.com/169237360990/smart-assembly-intervention-dlq \
  --attribute-names ApproximateNumberOfMessages
```

### Purger la queue (vider tous les messages — attention)
```bash
aws sqs purge-queue \
  --queue-url https://sqs.eu-west-3.amazonaws.com/169237360990/smart-assembly-intervention
```

### Vérifier la queue policy (qui peut envoyer des messages)
```bash
aws sqs get-queue-attributes \
  --queue-url https://sqs.eu-west-3.amazonaws.com/169237360990/smart-assembly-intervention \
  --attribute-names Policy
```

!!! warning "Piège aws:SourceArn"
    La condition `aws:SourceArn` dans la SQS queue policy doit pointer vers l'**ARN de la règle EventBridge**,
    pas l'ARN du bus. Une erreur sur ce point fait échouer silencieusement les livraisons sans aucune erreur visible.

---

## Step Functions

### Lister les exécutions récentes de la state machine
```bash
aws stepfunctions list-executions \
  --state-machine-arn arn:aws:states:eu-west-3:169237360990:stateMachine:smart-assembly-intervention-workflow \
  --max-results 10
```

!!! warning "Express Workflows — affichage console"
    Les Express Workflows n'affichent pas toujours les exécutions en temps réel dans la console AWS.
    La source de vérité est **DynamoDB** (`statut = EN_INTERVENTION`) et **CloudWatch Logs** (`/aws/lambda/smart-assembly-log-intervention`).

### Vérifier qu'une intervention a bien été loguée
```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/smart-assembly-log-intervention \
  --start-time 1783900000 \
  --limit 5 \
  --query "events[*].message"
```

### Vérifier les logs d'exécution Step Functions (CloudWatch)
```bash
aws logs filter-log-events \
  --log-group-name /aws/states/smart-assembly-intervention-workflow \
  --start-time 1783900000 \
  --limit 10 \
  --query "events[*].message"
```

### Réinitialiser le circuit breaker manuellement (après intervention)
```powershell
# Remet le poste en statut CRITICAL pour permettre une nouvelle intervention
[System.IO.File]::WriteAllText("$PWD\key.json", '{"id_poste":{"S":"poste_1"}}')
[System.IO.File]::WriteAllText("$PWD\expr.json", '{":s":{"S":"CRITICAL"}}')
aws dynamodb update-item --table-name machine_state --key file://key.json --update-expression "SET statut = :s" --expression-attribute-values file://expr.json
```

!!! tip "Circuit Breaker"
    Tant que `statut = EN_INTERVENTION` dans DynamoDB, toute nouvelle anomalie critique est bloquée (CircuitOpen).
    En production, ce reset serait déclenché par le technicien via l'API après confirmation de l'intervention.

### Test pipeline complet (un seul event)
```powershell
# 1. Vérifier l'état du circuit
[System.IO.File]::WriteAllText("$PWD\key.json", '{"id_poste":{"S":"poste_1"}}')
aws dynamodb get-item --table-name machine_state --key file://key.json --query "Item.statut"

# 2. Si EN_INTERVENTION, réinitialiser d'abord (voir ci-dessus)

# 3. Purger la queue SQS pour éviter les messages stale
aws sqs purge-queue --queue-url https://sqs.eu-west-3.amazonaws.com/169237360990/smart-assembly-intervention

# 4. Envoyer un event depuis EventBridge console (anomalie.critique)
# EventBridge → smart-assembly-events → Send events
# Source: smart-assembly.iot | DetailType: anomalie.critique

# 5. Vérifier le résultat dans DynamoDB (doit passer à EN_INTERVENTION)
aws dynamodb get-item --table-name machine_state --key file://key.json --query "Item.statut"

# 6. Vérifier le log d'intervention dans CloudWatch
# /aws/lambda/smart-assembly-log-intervention
```

---

## Kinesis

### Vérifier l'état du stream
```powershell
aws kinesis describe-stream-summary --stream-name smart-assembly-sensors `
  --query "StreamDescriptionSummary.{Statut:StreamStatus,Shards:OpenShardCount,Retention:RetentionPeriodHours}"
```

### Publier un enregistrement de test
```powershell
[System.IO.File]::WriteAllText("$PWD\kinesis_record.json", '{"id_poste":"poste_1","vibration":2.5,"temperature":85.0,"pression":4.1,"timestamp":"2026-07-14T10:00:00Z"}')
aws kinesis put-record `
  --stream-name smart-assembly-sensors `
  --partition-key poste_1 `
  --data fileb://kinesis_record.json
```

### Lire les enregistrements d'un shard
```powershell
# 1. Obtenir l'iterator du shard (TRIM_HORIZON = depuis le début)
$ITER = (aws kinesis get-shard-iterator `
  --stream-name smart-assembly-sensors `
  --shard-id shardId-000000000000 `
  --shard-iterator-type TRIM_HORIZON `
  --query ShardIterator --output text)

# 2. Lire les enregistrements
aws kinesis get-records --shard-iterator $ITER --limit 10
```

### Voir les métriques de débit (CloudWatch)
```powershell
aws cloudwatch get-metric-statistics `
  --namespace AWS/Kinesis `
  --metric-name IncomingRecords `
  --dimensions Name=StreamName,Value=smart-assembly-sensors `
  --start-time 1784000000000 `
  --end-time 1784010000000 `
  --period 60 `
  --statistics Sum
```

!!! tip "Dimensionnement des shards"
    1 shard = 1 000 enregistrements/seconde en écriture.
    Pour N capteurs à 1 mesure/seconde : `shard_count = ceil(N / 1000)`.
    À 1 000 capteurs → 1 shard. À 5 000 capteurs → 5 shards.

!!! warning "Throttling Kinesis"
    Si le stream est saturé, Kinesis retourne `ProvisionedThroughputExceededException`.
    Solution : augmenter `shard_count` ou passer en mode `ON_DEMAND` (Kinesis scale automatiquement).

---

## Chaos Day

### Test 2 — Forcer l'échec Lambda → DLQ

**Prérequis** : ajouter temporairement `FORCE_ERROR = true` dans les variables d'environnement de `smart-assembly-sqs-processor` (console Lambda → Configuration → Environment variables).

```powershell
# 1. Envoyer un event anomalie.critique
[System.IO.File]::WriteAllText("$PWD\event_test.json", '[{"Source":"smart-assembly.iot","DetailType":"anomalie.critique","EventBusName":"smart-assembly-events","Detail":"{\"id_poste\":\"poste_1\",\"statut\":\"CRITICAL\",\"regle\":\"vibration.critique\",\"mesures\":{\"vibration\":3.1}}"}]')
aws events put-events --entries file://event_test.json

# 2. Attendre ~90s (3 retries × visibility_timeout 30s), puis vérifier la DLQ
aws sqs get-queue-attributes `
  --queue-url https://sqs.eu-west-3.amazonaws.com/169237360990/smart-assembly-intervention-dlq `
  --attribute-names ApproximateNumberOfMessages

# 3. Purger la DLQ après validation
aws sqs purge-queue `
  --queue-url https://sqs.eu-west-3.amazonaws.com/169237360990/smart-assembly-intervention-dlq
```

!!! warning "Terraform écrase les variables manuelles"
    Toute variable ajoutée manuellement dans la console est supprimée au prochain `terraform apply`.
    En production, définir `FORCE_ERROR = false` dans le `.tf` et le passer à `true` uniquement pour les tests.

### Test 3 — Payload malformé (sans id_poste)

```powershell
# Envoyer un event sans id_poste
[System.IO.File]::WriteAllText("$PWD\event_malformed.json", '[{"Source":"smart-assembly.iot","DetailType":"anomalie.critique","EventBusName":"smart-assembly-events","Detail":"{\"statut\":\"CRITICAL\",\"regle\":\"vibration.critique\",\"mesures\":{\"vibration\":3.1}}"}]')
aws events put-events --entries file://event_malformed.json
```

Résultat attendu : `States.Runtime` dans CloudWatch Logs `/aws/states/smart-assembly-intervention-workflow` sur l'accès JSONPath `$.id_poste`.

### Test 4 — Circuit breaker sous charge (5 events simultanés)

```powershell
# 1. Réinitialiser le circuit
[System.IO.File]::WriteAllText("$PWD\key.json", '{"id_poste":{"S":"poste_1"}}')
[System.IO.File]::WriteAllText("$PWD\expr.json", '{":s":{"S":"CRITICAL"}}')
aws dynamodb update-item --table-name machine_state --key file://key.json --update-expression "SET statut = :s" --expression-attribute-values file://expr.json

# 2. Envoyer 5 events d'un coup
[System.IO.File]::WriteAllText("$PWD\events_load.json", '[{"Source":"smart-assembly.iot","DetailType":"anomalie.critique","EventBusName":"smart-assembly-events","Detail":"{\"id_poste\":\"poste_1\",\"statut\":\"CRITICAL\",\"regle\":\"vibration.critique\",\"mesures\":{\"vibration\":3.1}}"},{"Source":"smart-assembly.iot","DetailType":"anomalie.critique","EventBusName":"smart-assembly-events","Detail":"{\"id_poste\":\"poste_1\",\"statut\":\"CRITICAL\",\"regle\":\"vibration.critique\",\"mesures\":{\"vibration\":3.2}}"},{"Source":"smart-assembly.iot","DetailType":"anomalie.critique","EventBusName":"smart-assembly-events","Detail":"{\"id_poste\":\"poste_1\",\"statut\":\"CRITICAL\",\"regle\":\"vibration.critique\",\"mesures\":{\"vibration\":3.3}}"},{"Source":"smart-assembly.iot","DetailType":"anomalie.critique","EventBusName":"smart-assembly-events","Detail":"{\"id_poste\":\"poste_1\",\"statut\":\"CRITICAL\",\"regle\":\"vibration.critique\",\"mesures\":{\"vibration\":3.4}}"},{"Source":"smart-assembly.iot","DetailType":"anomalie.critique","EventBusName":"smart-assembly-events","Detail":"{\"id_poste\":\"poste_1\",\"statut\":\"CRITICAL\",\"regle\":\"vibration.critique\",\"mesures\":{\"vibration\":3.5}}"}]')
aws events put-events --entries file://events_load.json

# 3. Vérifier : LogIntervention doit apparaître UNE seule fois
aws logs filter-log-events `
  --log-group-name /aws/lambda/smart-assembly-log-intervention `
  --start-time 1783969000000 `
  --limit 10 `
  --query "events[*].message"
```

Résultat attendu : 1 log `LogIntervention`, les 4 autres exécutions Step Functions terminent sur `CircuitOpen`.

---

## IoT Core — Device Shadow (Jour 29)

### Lire le Shadow d'un poste (état courant reported + desired)
```powershell
aws iot-data get-thing-shadow `
  --thing-name poste_1 `
  --region eu-west-3 `
  shadow.json
Get-Content shadow.json | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

### Vérifier uniquement le reported (ce que le capteur a envoyé)
```powershell
aws iot-data get-thing-shadow `
  --thing-name poste_1 `
  --region eu-west-3 `
  shadow.json
(Get-Content shadow.json | ConvertFrom-Json).state.reported
```

### Modifier les seuils à chaud via le desired (test delta)
```powershell
# Abaisser le seuil vibration à 1.5 → le simulateur doit basculer plus d'events en WARN
$desired = '{"state":{"desired":{"seuil_vibration":1.5}}}'
$enc = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText("$env:TEMP\shadow_desired.json", $desired, $enc)
aws iot-data update-thing-shadow `
  --thing-name poste_1 `
  --region eu-west-3 `
  --payload "file://$env:TEMP\shadow_desired.json" `
  shadow_response.json
```

Le simulateur affiche : `[SHADOW] Seuil vibration mis à jour → 1.5 m/s²`

### Remettre les seuils par défaut
```powershell
$reset = '{"state":{"desired":{"seuil_vibration":2.0,"seuil_temperature":80.0}}}'
$enc = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText("$env:TEMP\shadow_reset.json", $reset, $enc)
aws iot-data update-thing-shadow `
  --thing-name poste_1 `
  --region eu-west-3 `
  --payload "file://$env:TEMP\shadow_reset.json" `
  shadow_response.json
```

### Vérifier la règle EventBridge CRITICAL (Jour 29)
```powershell
aws events describe-rule `
  --name smart-assembly-iot-direct-critical `
  --event-bus-name smart-assembly-events `
  --region eu-west-3 `
  --query "{Nom:Name,Statut:State,Pattern:EventPattern}"
```

!!! note "Limitation — IoT → EventBridge direct"
    L'action `eventBridge` n'est pas disponible dans `aws_iot_topic_rule` en eu-west-3 (juillet 2026).
    Le routing IoT → EventBridge passe par Lambda (flux existant : IoT → Lambda → EventBridge via PutEvents).

---

## Coûts AWS

### Voir une estimation des coûts du mois en cours
```powershell
aws ce get-cost-and-usage \
  --time-period Start=2026-07-01,End=2026-07-31 \
  --granularity MONTHLY \
  --metrics "UnblendedCost"
```

!!! tip "Free Tier"
    VPC, subnets, route tables et Internet Gateway sont **gratuits**.
    Les coûts commenceront avec S3 (stockage), Lambda (invocations) et IoT Core (messages).
    Tout reste dans le Free Tier tant que le volume reste faible.

---

## Edge Computing — Mosquitto + Analyzer (Jour 30)

### Démarrer l'edge device (Docker)
```bash
cd src/greengrass
docker compose up
```

Deux conteneurs démarrent :
- `smart-assembly-broker` — Mosquitto MQTT local (port 1885 sur host, 1883 interne)
- `smart-assembly-analyzer` — component edge : filtre + transfère WARN/CRITICAL vers IoT Core

### Lancer le simulateur capteur (host)
```bash
cd src/iot-simulator
python publish_vibration_edge.py
```

Le simulateur publie vers `localhost:1885` → Mosquitto → Analyzer → IoT Core (WARN/CRITICAL seulement).

### Vérifier la réception dans le cloud
IoT Core Console → **MQTT Test Client** → Subscribe → `assembly-line/poste_1/alerts`

Ou via CLI (surveiller les logs CloudWatch si une règle IoT est configurée sur ce topic).

### Valider le filtrage edge (logs Docker)
```bash
docker logs smart-assembly-analyzer --follow
```

Résultat attendu :
- `[EDGE ✓] OK filtré` → mesures normales ignorées localement
- `[CLOUD ↑] WARN/CRITICAL` → alertes transmises vers IoT Core
- `[STATS]` toutes les 10 mesures → taux de filtrage local

### Arrêter l'edge device
```bash
cd src/greengrass
docker compose down
```

### Vérifier l'état des conteneurs
```bash
docker ps -a | grep smart-assembly
```

### Rebuilder après modification du code analyzer
```bash
cd src/greengrass
docker compose down
docker compose up --build
```

!!! note "Ports"
    Port `1885` côté host (Windows) → port `1883` interne Docker.
    `serre-mosquitto` occupe le port `1883` sur le host — ne pas modifier.

!!! note "Limitation Greengrass"
    Greengrass v2 n'est pas disponible en eu-west-3 et l'image Docker officielle
    n'est pas sur Docker Hub. L'architecture Mosquitto + analyzer.py reproduit
    le même pattern edge (filtrage local → cloud sélectif) sans le runtime Greengrass.

!!! warning "PYTHONUNBUFFERED"
    Sans `PYTHONUNBUFFERED=1` dans docker-compose.yml, les logs Python
    n'apparaissent pas dans `docker logs`. Toujours inclure cette variable.

---

## Circuit Breaker IoT Core (Jour 31)

### Démarrer la stack avec circuit breaker
```powershell
cd src/greengrass
docker compose down
docker compose up --build -d   # rebuild obligatoire (nouveau analyzer.py)
docker logs smart-assembly-analyzer --follow
```

### Simuler une coupure IoT Core

1. Laisser le simulateur tourner (`publish_vibration_edge.py`)
2. Couper la connectivité IoT Core (désactiver l'interface réseau OU supprimer temporairement la policy IoT dans la console)
3. Observer dans les logs :

```
[CLOUD] Echec (1/3) :
[BUFFER] Bufferisé (statut=CRITICAL) — 1 en attente
[CLOUD] Echec (2/3) :
[BUFFER] Bufferisé (statut=CRITICAL) — 2 en attente
[CLOUD] Echec (3/3) :
[CB] 3 échecs → OPEN (retry dans 30s)
[BUFFER] Bufferisé (statut=WARN) — 4 en attente
...
[STATS] 50 mesures | 46 cloud | 11 buffer | 8% filtrées | CB:OPEN
```

### Valider le flush sur reconnexion

Rétablir la connectivité. Après ≤ 30 secondes :

```
[CB] OPEN → HALF_OPEN (test connexion IoT Core...)
[CLOUD] [HALF_OPEN] CRITICAL — vib=3.16 temp=95.8
[CB] HALF_OPEN → CLOSED ✅
[BUFFER] Flush de 57 événements vers IoT Core...
[BUFFER] Flush complet : 57 événements envoyés, buffer vidé
```

### Inspecter le buffer JSONL pendant une coupure
```bash
# Depuis le host (buffer monté en volume dans src/greengrass/buffer/)
cat src/greengrass/buffer/events_buffer.jsonl | head -5
```

Chaque ligne = 1 événement JSON avec le champ `buffered_at` (timestamp UTC de bufférisation).

### Vider le buffer manuellement (si nécessaire)
```bash
rm src/greengrass/buffer/events_buffer.jsonl
```

!!! warning "Buffer et redémarrages Docker"
    Le dossier `buffer/` doit être monté en volume dans `docker-compose.yml` pour
    survivre aux redémarrages du conteneur. Sans ce volume, le buffer est perdu.
    Ajouter dans `docker-compose.yml` sous `analyzer.volumes` :
    ```yaml
    - ./buffer:/app/buffer
    ```

!!! note "Paramètres Circuit Breaker"
    Modifiables dans `analyzer.py` :
    - `failure_threshold=3` : nombre d'échecs consécutifs pour ouvrir le circuit
    - `recovery_timeout=30` : secondes avant de passer en HALF_OPEN et tenter une reconnexion

### Résultats du test Jour 31 (référence)

| Phase | Durée | Mesures | Cloud | Buffer |
|-------|-------|---------|-------|--------|
| CLOSED (normal) | ~3min | 39 | 36 | 0 |
| OPEN (coupure) | ~1min45 | 57 | 0 | 57 |
| HALF_OPEN → CLOSED | ~2s | flush | +57 | 0 |
| CLOSED (rétabli) | en cours | normal | normal | 0 |

Flush complet de 57 événements en **2 secondes** à la reconnexion.

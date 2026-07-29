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

## TinyML — Isolation Forest Edge (Jour 32)

### Démarrer la stack avec ML actif
```powershell
cd src\greengrass
docker compose down
docker compose up --build -d   # rebuild obligatoire (detector.py + scikit-learn)
docker logs smart-assembly-analyzer --follow
```

### Phase warm-up (200 mesures requises)

Le modèle s'entraîne automatiquement après 200 mesures. Pendant cette phase :
- Les seuils statiques (WARN/CRITICAL) fonctionnent normalement
- Le ML est inactif (`[ML warm-up X/200]` visible dans les logs OK filtrés)
- Durée : ~7 minutes à 2s/mesure

Logs attendus :
```
[ML] Warm-up : 50/200 mesures collectées...
[ML] Warm-up : 100/200 mesures collectées...
[ML] Warm-up : 150/200 mesures collectées...
[ML] Warm-up : 200/200 mesures collectées...
[ML] Entraînement Isolation Forest sur 200 mesures...
[ML] Modèle prêt. Taux faux positifs (train) : 5.0% (cible < 5%)
[ML] Seuil décision : -0.1 | Features : 10
```

### Injecter une anomalie synthétique pour tester le ML

```powershell
# 1. Créer le payload anomalie (sans BOM)
$enc = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
    "$env:TEMP\anomaly.json",
    '{"id_poste":"poste_1","vibration":5.5,"temperature":75.0,"pression":4.0,"timestamp":"2026-07-19T19:50:00Z"}',
    $enc
)

# 2. Copier dans le conteneur Mosquitto
docker cp "$env:TEMP\anomaly.json" smart-assembly-broker:/tmp/anomaly.json

# 3. Envoyer 12 fois (pour remplir la fenêtre glissante de 10)
1..12 | ForEach-Object {
    docker exec smart-assembly-broker mosquitto_pub -h localhost -p 1883 `
        -t "assembly-line/poste_1/metrics" -f /tmp/anomaly.json
    Start-Sleep -Milliseconds 200
}
```

Résultat attendu à partir de la 6e injection :
```
[ML] ANOMALY détectée — score=-0.1159 vib=5.5 temp=75.0
[CLOUD] [CLOSED] CRITICAL — vib=5.5 temp=75.0
```

!!! note "Fenêtre glissante"
    Le ML détecte les anomalies de **pattern** sur les 10 dernières mesures.
    Une seule injection ne suffit pas — la fenêtre doit se remplir de valeurs
    anormales pour que `vib_mean_10` et `vib_std_10` dévient significativement
    du profil appris pendant le warm-up.

!!! note "Seuil de décision"
    Seuil par défaut : `-0.1`. Score < -0.1 → ANOMALY.
    Ajustable dans `detector.py` : `AnomalyDetector(threshold=-0.05)` pour
    plus de sensibilité (plus de faux positifs), ou `-0.2` pour moins (moins de détections).

### Résultats du test Jour 32 (référence)

| Phase | Mesures | Durée | Résultat |
|-------|---------|-------|----------|
| Warm-up | 200 | ~7 min | Collecte features en mémoire |
| Entraînement | — | 145ms | Isolation Forest prêt, FP=5.0% |
| Inférence normale | 60+ | — | 0 ML anomalies (comportement correct) |
| Injection vib=5.5 ×12 | 12 | — | ML déclenche à partir de la 6e (score=-0.1159) |

### Vérifier les stats ML en temps réel
```powershell
docker logs smart-assembly-analyzer --follow | Select-String "STATS|ML"
```

Affiche toutes les 10 mesures :
```
[STATS] 270 mesures | 254 cloud | 0 buffer | 3 ML anomalies | 6% filtrées | CB:CLOSED
```

### Architecture des fichiers

```
src/greengrass/
  analyzer.py    ← orchestrateur (MQTT + CB + routing) — inchangé dans sa logique
  detector.py    ← TinyML : features, warm-up, Isolation Forest, inférence
  Dockerfile     ← ajout scikit-learn + numpy + joblib + COPY detector.py
```


# ECS Fargate + Spring Boot Supervision API

---

## Objectif

Déployer l'API de supervision sur ECS Fargate avec :
- Image Docker Spring Boot poussée sur ECR
- Service ECS derrière un ALB existant
- Accès sécurisé à DynamoDB (`machine_state`) via IAM Task Role + KMS

---

## Architecture déployée

```
Internet
   │
   ▼
ALB (smart-assembly-alb)
   │  /actuator/health → ECS health check
   │  /api/machines    → DynamoDB Scan
   │  /api/alerts      → DynamoDB Scan + FilterExpression
   ▼
ECS Fargate Service (supervision-api)
   │  Task Execution Role → ECR pull + CloudWatch Logs
   │  Task Role           → DynamoDB + KMS Decrypt
   ▼
DynamoDB (machine_state) — chiffrée KMS
```

---

## 1. Prérequis vérifiés

```powershell
# Vérifier que le registre ECR existe
aws ecr describe-repositories --repository-names supervision-api --region eu-west-3

# Vérifier que la table DynamoDB existe
aws dynamodb describe-table --table-name machine_state --region eu-west-3 --query "Table.{Status:TableStatus,Encryption:SSEDescription.SSEType}"
```

---

## 2. Build Docker multi-stage

Depuis `C:\Users\conde\supervision-api\` :

```powershell
docker build -t supervision-api:latest .
```

**Dockerfile (multi-stage) :**
```dockerfile
FROM maven:3.9-eclipse-temurin-21-alpine AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn package -DskipTests -q

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-Dserver.shutdown=graceful", "-jar", "app.jar"]
```

> Image finale : ~180MB (JRE alpine uniquement, sans Maven ni sources)

---

## 3. Push ECR

```powershell
# Authentification Docker → ECR
aws ecr get-login-password --region eu-west-3 | `
  docker login --username AWS --password-stdin `
  169237360990.dkr.ecr.eu-west-3.amazonaws.com

# Tag
docker tag supervision-api:latest `
  169237360990.dkr.ecr.eu-west-3.amazonaws.com/supervision-api:latest

# Push
docker push 169237360990.dkr.ecr.eu-west-3.amazonaws.com/supervision-api:latest
```

---

## 4. Terraform — ressources créées (ecs.tf)

### 4.1 ECR Repository

```hcl
resource "aws_ecr_repository" "supervision_api" {
  name                 = "supervision-api"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "supervision_api" {
  repository = aws_ecr_repository.supervision_api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Garder les 5 dernières images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
```

### 4.2 ECS Cluster

```hcl
resource "aws_ecs_cluster" "main" {
  name = "smart-assembly-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
```

### 4.3 IAM Dual-Role

**Task Execution Role** (infrastructure ECS) :
- Pull image ECR
- Écrire logs CloudWatch

**Task Role** (application) :
- `dynamodb:Scan`, `dynamodb:GetItem`, `dynamodb:Query` sur `machine_state`
- `kms:Decrypt`, `kms:DescribeKey` sur la clé KMS de la table
- `cloudwatch:DescribeAlarms`, `cloudwatch:GetMetricData`

```hcl
resource "aws_iam_role_policy" "supervision_api_task" {
  name = "supervision-api-task-policy"
  role = aws_iam_role.supervision_api_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBReadOnly"
        Effect = "Allow"
        Action = ["dynamodb:Scan", "dynamodb:GetItem", "dynamodb:Query"]
        Resource = aws_dynamodb_table.machine_state.arn
      },
      {
        Sid    = "KMSDecryptDynamoDB"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = "arn:aws:kms:eu-west-3:169237360990:key/7d2fd7d2-6d2a-4ce9-beb3-b61621aa90aa"
      },
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = ["cloudwatch:DescribeAlarms", "cloudwatch:GetMetricData"]
        Resource = "*"
      }
    ]
  })
}
```

### 4.4 Task Definition

```hcl
resource "aws_ecs_task_definition" "supervision_api" {
  family                   = "supervision-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.supervision_api_task.arn

  container_definitions = jsonencode([{
    name  = "supervision-api"
    image = "${aws_ecr_repository.supervision_api.repository_url}:latest"
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment = [
      { name = "AWS_REGION",    value = "eu-west-3" },
      { name = "TABLE_NAME",    value = "machine_state" },
      { name = "SERVER_PORT",   value = "8080" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/supervision-api"
        "awslogs-region"        = "eu-west-3"
        "awslogs-stream-prefix" = "ecs"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8080/actuator/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60  # Spring Boot prend ~44s sur Fargate
    }
  }])
}
```

> `startPeriod = 60` : ECS ignore les health check failures pendant les 60 premières secondes, évitant les restarts prématurés pendant le démarrage Spring Boot.

### 4.5 ECS Service

```hcl
resource "aws_ecs_service" "supervision_api" {
  name            = "supervision-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.supervision_api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false  # subnet privé, pas d'IP publique
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "supervision-api"
    container_port   = 8080
  }

  lifecycle {
    ignore_changes = [task_definition]  # déploiements manuels via ECR/ECS
  }
}
```

---

## 5. ALB — modifications (alb.tf)

Deux changements critiques par rapport à la config initiale :

| Paramètre | Avant | Après | Raison |
|-----------|-------|-------|--------|
| `target_type` | `"instance"` | `"ip"` | Fargate utilise awsvpc (ENI), pas d'instance EC2 |
| `health_check.path` | `"/health"` | `"/actuator/health"` | Spring Boot Actuator expose ce chemin |

> **Piège** : Modifier `target_type` détruit et recrée le Target Group. Si un listener y est attaché, Terraform entre dans un cycle destroy-before-create. Solution : `terraform state rm aws_lb_target_group.backend` puis apply.

---

## 6. Apply Terraform

```powershell
cd terraform/environments/dev

# Apply ciblé pour la policy IAM uniquement
terraform apply -target="aws_iam_role_policy.supervision_api_task"

# Apply complet
terraform apply
```

---

## 7. Déploiement ECS

Après chaque push ECR, forcer un nouveau déploiement :

```powershell
aws ecs update-service `
  --cluster smart-assembly-cluster `
  --service supervision-api `
  --force-new-deployment `
  --region eu-west-3
```

Suivre le déploiement :

```powershell
aws ecs describe-services `
  --cluster smart-assembly-cluster `
  --services supervision-api `
  --region eu-west-3 `
  --query "services[0].{running:runningCount,pending:pendingCount,events:events[0:3]}"
```

---

## 8. Validation

### 8.1 Health check ALB

```powershell
aws elbv2 describe-target-health `
  --target-group-arn arn:aws:elasticloadbalancing:eu-west-3:169237360990:targetgroup/smart-assembly-supervision-tg/35f6af14df48a375 `
  --region eu-west-3 `
  --query "TargetHealthDescriptions[*].{IP:Target.Id,State:TargetHealth.State}"
```

Résultat attendu : `"State": "healthy"`

### 8.2 Tests API via ALB

```powershell
$ALB = "http://smart-assembly-alb-522870733.eu-west-3.elb.amazonaws.com"

# Health check Spring Boot
curl $ALB/actuator/health
# → {"status":"UP",...}

# Liste des machines (DynamoDB Scan)
curl $ALB/api/machines
# → [{"idPoste":"poste_1","statut":"EN_INTERVENTION",...}, ...]

# Alertes (DynamoDB Scan + FilterExpression)
curl $ALB/api/alerts
# → {"count":0,"alerts":[]}
```

### 8.3 Résultats obtenus

| Endpoint | Status | Réponse |
|----------|--------|---------|
| `/actuator/health` | **200 OK** | `{"status":"UP"}` |
| `/api/machines` | **200 OK** | 3 machines depuis DynamoDB |
| `/api/alerts` | **200 OK** | `{"count":0,"alerts":[]}` |

---

## 9. Incident rencontré — KMS Decrypt

### Symptôme

```
HTTP 500 sur /api/machines et /api/alerts
```

Logs CloudWatch :
```
software.amazon.awssdk.services.dynamodb.model.DynamoDbException:
User: arn:aws:sts::169237360990:assumed-role/smart-assembly-supervision-api-task-role/...
is not authorized to perform: kms:Decrypt
on resource: arn:aws:kms:eu-west-3:169237360990:key/7d2fd7d2-6d2a-4ce9-beb3-b61621aa90aa
```

### Cause

La table DynamoDB `machine_state` est chiffrée avec une Customer Managed Key (CMK). Le Task Role avait les permissions `dynamodb:Scan/GetItem/Query` mais pas `kms:Decrypt`. DynamoDB déchiffre les données à la lecture en appelant KMS — ce que le Task Role ne pouvait pas faire.

### Fix

Ajout d'un statement KMS dans `aws_iam_role_policy.supervision_api_task` :

```hcl
{
  Sid    = "KMSDecryptDynamoDB"
  Effect = "Allow"
  Action = ["kms:Decrypt", "kms:DescribeKey"]
  Resource = "arn:aws:kms:eu-west-3:169237360990:key/7d2fd7d2-6d2a-4ce9-beb3-b61621aa90aa"
}
```

Puis :
```powershell
terraform apply -target="aws_iam_role_policy.supervision_api_task"
aws ecs update-service --cluster smart-assembly-cluster --service supervision-api --force-new-deployment --region eu-west-3
```

### Leçon

**Toujours** ajouter `kms:Decrypt` sur la CMK quand un service accède à une ressource AWS chiffrée (DynamoDB, S3 SSE-KMS, Secrets Manager). L'erreur n'apparaît qu'à l'exécution, pas au déploiement.

---

## 10. Logs CloudWatch

```powershell
# Suivre les logs en temps réel
aws logs tail /ecs/supervision-api --follow --region eu-west-3

# Derniers 50 logs
aws logs tail /ecs/supervision-api --since 30m --region eu-west-3
```

---

## 11. Concepts clés retenus

**awsvpc network mode** : Chaque task Fargate reçoit sa propre ENI (Elastic Network Interface) avec une IP privée. Le Target Group ALB doit être `target_type = "ip"` pour enregistrer cette IP, pas `"instance"`.

**Default Credential Provider Chain** : Le SDK AWS Java/Spring découvre automatiquement les credentials. En local → `~/.aws/credentials`. Sur ECS → Task Metadata Endpoint (rôle injecté par ECS). Aucune configuration explicite de credentials dans le code.

**IAM Dual-Role pattern** :
- *Task Execution Role* = ECS agent (pull ECR, push logs CloudWatch) — géré par AWS
- *Task Role* = l'application elle-même (DynamoDB, KMS, CloudWatch metrics) — à définir précisément

**Spring Boot startPeriod** : Spring Boot 4.x démarre en ~44s sur Fargate 0.25 vCPU. Sans `startPeriod = 60`, ECS marque le container unhealthy et le redémarre en boucle avant qu'il soit prêt.

---

## Commit

```powershell
git add terraform/environments/dev/ecs.tf
git add terraform/environments/dev/alb.tf
git add src/supervision-api/
git add docs/ecs/
git add docs/runbooks/jour-39-ecs-fargate.md

git commit -m "feat(jour-39): ECS Fargate supervision API + fix KMS Decrypt

- ECR repository + lifecycle policy (5 images max)
- ECS cluster smart-assembly-cluster (Container Insights enabled)
- IAM dual-role: execution role + task role avec KMS Decrypt
- Task Definition: Spring Boot 4.1, awsvpc, startPeriod=60
- ECS Service: Fargate, subnet privé, ALB integration
- ALB: target_type=ip, health_check=/actuator/health
- Fix KMS: ajout kms:Decrypt sur CMK DynamoDB (machine_state)
- Validation: /actuator/health 200, /api/machines 200 (3 machines), /api/alerts 200
```


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

git commit -m "feat: CloudWatch Dashboard + S3 backend CI fix

- cloudwatch.tf: aws_cloudwatch_dashboard smart-assembly-overview
  11 widgets : Lambda (invocations/erreurs/p99) · ECS (CPU/mémoire/tasks)
  ALB (requêtes/latence p99/5xx+healthy hosts) · DynamoDB (RCU/WCU/latence)
  Widget alarmes : 5 alarmes existantes intégrées
- main.tf: backend S3 (smart-assembly-tfstate-169237360990)
  State migré local → S3, résout ResourceAlreadyExists en CI
- docs: théorie namespaces CloudWatch + runbook Jour 40

```

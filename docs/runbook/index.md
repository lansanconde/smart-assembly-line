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

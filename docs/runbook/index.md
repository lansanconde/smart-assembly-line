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

## IoT Core

### Vérifier les ressources IoT

```bash
# Lister les Things
aws iot list-things

# Lister les certificats
aws iot list-certificates

# Vérifier les policies attachées à un certificat
aws iot list-principal-policies \
  --principal arn:aws:iot:eu-west-3:169237360990:cert/<CERT_ID>

# Lister les Things attachés à un certificat
aws iot list-principal-things \
  --principal arn:aws:iot:eu-west-3:169237360990:cert/<CERT_ID>
```

### Endpoint IoT

```bash
aws iot describe-endpoint --endpoint-type iot:Data-ATS
```

### Tester la connexion MQTT

1. Console AWS → IoT Core → **MQTT Test Client**
2. Subscribe to topic : `assembly-line/poste_1/metrics`
3. Lancer le simulateur :

```bash
cd iot-simulator
python publish_vibration.py
```

### Attacher une policy à un certificat

```bash
aws iot attach-policy \
  --policy-name smart-assembly-device-policy \
  --target arn:aws:iot:eu-west-3:169237360990:cert/<CERT_ID>
```

## Lambda

### Lister les fonctions déployées

```bash
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `smart-assembly`)].{Nom:FunctionName,Runtime:Runtime,Timeout:Timeout}'
```

### Invoquer une fonction manuellement (test)

```bash
# Écrire le payload dans un fichier
echo '{"id_poste":"poste_1","vibration":1.8,"temperature":82.0,"pression":4.5,"timestamp":"2026-07-11T10:00:00+00:00"}' > payload.json

# Invoquer
aws lambda invoke \
  --function-name smart-assembly-analyze-vibration \
  --payload file://payload.json \
  response.json && cat response.json
```

### Consulter les logs CloudWatch

```bash
# Derniers logs de AnalyzeVibration
aws logs tail /aws/lambda/smart-assembly-analyze-vibration --since 1h

# Derniers logs de StoreMetrics
aws logs tail /aws/lambda/smart-assembly-store-metrics --since 1h
```

### Vérifier les objets S3 archivés

```bash
aws s3 ls s3://smart-assembly-raw-data-169237360990/ --recursive
```

### IoT Rules Engine — vérifier les règles actives

```bash
aws iot list-topic-rules
```

## NAT Gateway

> ⚠️ Ressource coûteuse (~$32/mois). Créer uniquement pour un lab, détruire immédiatement après.

### Créer la NAT Gateway

```bash
terraform apply \
  -target="aws_eip.nat" \
  -target="aws_nat_gateway.main" \
  -target="aws_route.private_nat"
```

### Vérifier la route dans le subnet privé

```bash
aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=smart-assembly-rt-private" \
  --query "RouteTables[].Routes"
```

La route `0.0.0.0/0 → nat-xxxxxxx` doit apparaître.

### Détruire après le lab (obligatoire)

```bash
terraform destroy \
  -target="aws_route.private_nat" \
  -target="aws_nat_gateway.main" \
  -target="aws_eip.nat"
```
## Application Load Balancer

> ⚠️ Ressource coûteuse (~$18/mois). Créer uniquement pour un lab ou la production — détruire après le lab.

### Créer l'ALB

```bash
terraform apply \
  -target="aws_subnet.public_b" \
  -target="aws_route_table_association.public_b" \
  -target="aws_security_group.alb" \
  -target="aws_lb.main" \
  -target="aws_lb_target_group.backend" \
  -target="aws_lb_listener.http"
```

### Vérifier l'état de l'ALB

```bash
aws elbv2 describe-load-balancers \
  --names smart-assembly-alb \
  --query "LoadBalancers[].{State:State.Code,DNS:DNSName,AZs:AvailabilityZones[].ZoneName}"
```

### Vérifier le Target Group

```bash
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:eu-west-3:169237360990:targetgroup/smart-assembly-backend-tg/913b37b4350dd4ea
```

### Détruire après le lab (obligatoire)

```bash
terraform destroy \
  -target="aws_lb_listener.http" \
  -target="aws_lb.main" \
  -target="aws_lb_target_group.backend" \
  -target="aws_security_group.alb" \
  -target="aws_route_table_association.public_b" \
  -target="aws_subnet.public_b"
```

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

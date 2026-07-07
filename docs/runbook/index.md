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

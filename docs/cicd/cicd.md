# CI/CD — GitHub Actions (Jour 38)

> Pipeline automatisé pour le projet Smart Assembly Line.
> Déclenché sur chaque PR et push sur `main`.

---

## 1. Positionnement dans la stack

```
Developer → git push → GitHub
                          │
                          ▼
                   GitHub Actions
                          │
              ┌───────────┼───────────┐
              │           │           │
         Validate      Test        Security
         tf fmt        pytest      checkov
         tf validate   Lambda      tfsec
              │           │           │
              └───────────┴───────────┘
                          │
                     [PR] terraform plan → commentaire PR
                     [main] terraform apply → AWS
```

**Pourquoi CI/CD pour l'infra ?**

Sans pipeline, chaque ingénieur applique le Terraform depuis sa machine avec ses propres credentials. Risques : état Terraform corrompu si deux personnes appliquent simultanément, pas de traçabilité des changements infra, pas de revue avant apply.

Avec GitHub Actions :
- Tout changement infra passe par une PR avec plan affiché
- Apply uniquement sur `main` après merge (branche protégée)
- Secrets AWS dans GitHub Secrets (jamais dans le code)
- Historique complet dans CloudTrail (toutes les actions viennent du même rôle IAM CI)

---

## 2. Concepts GitHub Actions

### 2.1 Terminologie

```
workflow  → fichier YAML dans .github/workflows/
job       → ensemble d'étapes sur un runner
step      → commande ou action unitaire
runner    → machine virtuelle (ubuntu-latest = Ubuntu 22.04 gratuit)
event     → ce qui déclenche le workflow (push, pull_request, schedule)
```

### 2.2 Triggers utilisés

```yaml
on:
  pull_request:
    branches: [main]
    paths:
      - 'terraform/**'
      - 'src/**'
  push:
    branches: [main]
```

`paths` : le pipeline ne se déclenche que si des fichiers Terraform ou src ont changé.
Un commit qui ne touche que la doc ne déclenche pas de `terraform plan`.

### 2.3 Secrets GitHub

Les credentials AWS ne sont **jamais** dans le code. Ils sont stockés dans :
`GitHub repo → Settings → Secrets and variables → Actions`

```
AWS_ACCESS_KEY_ID      → clé d'accès IAM CI
AWS_SECRET_ACCESS_KEY  → secret IAM CI
AWS_REGION             → eu-west-3
```

Dans le workflow :
```yaml
env:
  AWS_ACCESS_KEY_ID:     ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  AWS_DEFAULT_REGION:    ${{ secrets.AWS_REGION }}
```

### 2.4 OIDC vs Access Keys (production)

Pour une vraie production, on remplace les Access Keys par **OIDC** (OpenID Connect) :
GitHub se fédère avec AWS IAM → assume role temporaire → pas de secret long terme.

```yaml
# Alternative OIDC (production) — pas de secrets à gérer
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::169237360990:role/github-actions-role
    aws-region: eu-west-3
```

Pour ce projet on utilise Access Keys (plus simple à configurer, niveau staff suffisant
pour démontrer le principe en entretien avec la note "OIDC en production").

---

## 3. Stages du pipeline

### Stage 1 — Terraform Validate & Format

```
tf fmt --check      → vérifie le formatage (ne modifie pas les fichiers)
tf validate         → vérifie la syntaxe HCL et les références
```

Bloque la PR si le code n'est pas formaté ou contient des erreurs HCL.
`terraform fmt -recursive` corrige localement avant de pusher.

### Stage 2 — Security Scan (Checkov)

**Checkov** analyse le code Terraform et détecte les mauvaises pratiques de sécurité :
- S3 sans chiffrement
- IAM trop permissif (`*` sur `*`)
- CloudTrail désactivé
- SG ouvert sur 0.0.0.0/0

```
checkov -d terraform/ --framework terraform --output cli
```

Pour ce projet, certaines règles légitimes sont ignorées via `#checkov:skip` dans le `.tf`.
Exemple : `force_destroy = true` sur S3 → acceptable en lab, à retirer en prod.

### Stage 3 — Tests Python Lambda

```
pytest src/lambda/tests/ -v --tb=short
```

Tests unitaires des handlers Lambda (mocks boto3). Vérifie que la logique métier
(statut CRITICAL, publication CloudWatch, circuit breaker) fonctionne avant deploy.

### Stage 4 — Terraform Plan (PR uniquement)

Sur une PR, le pipeline génère un `terraform plan` et poste le résultat en commentaire.
Le reviewer voit exactement ce qui va changer en AWS avant de merger.

```yaml
- name: Terraform Plan
  run: terraform plan -no-color -out=tfplan

- name: Post plan as PR comment
  uses: actions/github-script@v7
  with:
    script: |
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        body: `\`\`\`\n${plan_output}\n\`\`\``
      })
```

### Stage 5 — Terraform Apply (main uniquement)

```yaml
if: github.ref == 'refs/heads/main' && github.event_name == 'push'
```

Uniquement sur push sur `main` (après merge de PR).
Jamais sur une PR en cours — évite les applies partiels sur des branches de feature.

---

## 4. State Terraform en CI

### Problème

`terraform.tfstate` ne peut pas être dans le repo git (contient des données sensibles,
conflits si plusieurs jobs tournent en parallèle).

### Solution — Remote State S3

```hcl
# terraform/environments/dev/backend.tf
terraform {
  backend "s3" {
    bucket         = "smart-assembly-tfstate-169237360990"
    key            = "dev/terraform.tfstate"
    region         = "eu-west-3"
    encrypt        = true
    dynamodb_table = "smart-assembly-tfstate-lock"  # verrou anti-concurrent
  }
}
```

En CI, `terraform init` récupère automatiquement le state depuis S3.
Le `dynamodb_table` est un verrou distribué : si deux jobs tournent en même temps,
le second attend que le premier libère le verrou.

**Note** : pour ce projet lab, le state est local (pas de backend S3 configuré).
En entretien : toujours mentionner remote state + lock comme requis en production.

---

## 5. Fichier créé

```
.github/workflows/
  ci.yml   ← pipeline complet (validate, checkov, pytest, plan/apply)
```

---

## 6. IAM Role pour CI/CD (principe du moindre privilège)

En production, le rôle IAM utilisé par GitHub Actions n'a que les permissions
nécessaires pour Terraform apply, et rien de plus :

```
Permissions minimales CI :
  - ec2:Describe*, ec2:Create*, ec2:Delete* (VPC, subnets...)
  - lambda:UpdateFunctionCode, lambda:GetFunction
  - iam:PassRole (uniquement sur les rôles smart-assembly-*)
  - s3:PutObject, s3:GetObject (sur les buckets du projet)
  - dynamodb:PutItem, dynamodb:UpdateItem (sur machine_state)
  - cloudwatch:PutMetricAlarm, cloudwatch:DeleteAlarms
  - cloudtrail:CreateTrail, cloudtrail:UpdateTrail
```

Permission refusée : `iam:CreateUser`, `iam:CreateAccessKey`.
Le rôle CI ne peut pas créer de nouveaux utilisateurs IAM.

---

## 7. Bonnes pratiques senior architect

**Branch protection** : activer "Require status checks to pass before merging"
sur `main` → impossible de merger si validate/checkov/tests échouent.

**Concurrency** : si deux PRs sont ouvertes en même temps, éviter deux `terraform plan`
simultanés sur le même state :

```yaml
concurrency:
  group: terraform-${{ github.ref }}
  cancel-in-progress: false  # ne pas annuler un apply en cours
```

**Plan artifact** : sauvegarder le `tfplan` binaire comme artifact GitHub Actions.
L'apply utilise ce fichier exact (pas un nouveau plan) → garantit que ce qui a été
reviewé est exactement ce qui sera appliqué.

**Drift detection** : ajouter un job `schedule` hebdomadaire qui fait un `terraform plan`
et alerte si des ressources ont été modifiées manuellement en console (drift).

```yaml
on:
  schedule:
    - cron: '0 8 * * 1'  # chaque lundi 8h
```

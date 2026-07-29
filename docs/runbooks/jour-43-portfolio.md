# Portfolio — S3 + CloudFront + Responsive + Industry 4.0

---

## Objectif

Déployer un portfolio technique statique sur AWS (S3 + CloudFront) présentant le projet Smart Aerospace Assembly Line. Accessible publiquement via HTTPS avec CDN global.

**URL publique :** https://do1vmragia1j9.cloudfront.net

---

## Architecture

```
Browser (HTTPS)
  └── CloudFront Distribution (PriceClass_100 — EU + NA)
        └── OAC (sigv4) → S3 Bucket (privé)
              ├── index.html
              ├── photo.png
              └── screenshots/
                    ├── capt1_smart-assembly-overview.png
                    ├── capt2_smart-assembly-overview.png
                    ├── cap1_supervision-api.png
                    ├── cap2_supervision-api.png
                    ├── capt1_alb-target-group.png
                    ├── capt2_alb-target-group.png
                    ├── cap_eventBridge-bus-events.png
                    ├── cap_greengrass-core-poste.png
                    ├── cap_step_funtion_circuitBreaker.png
                    ├── github-actions-ci-cd.png
                    ├── cap_s3.png
                    ├── cap1_dynamo.png
                    └── cap2_dynamo.png
```

---

## 1. Ressources Terraform créées

**Fichier :** `terraform/environments/dev/portfolio.tf`

| Ressource | Description |
|-----------|-------------|
| `aws_s3_bucket.portfolio` | Bucket `smart-assembly-portfolio-169237360990` |
| `aws_s3_bucket_public_access_block.portfolio` | Accès public désactivé |
| `aws_s3_bucket_versioning.portfolio` | Versioning activé |
| `aws_cloudfront_origin_access_control.portfolio` | OAC sigv4 → S3 |
| `aws_cloudfront_distribution.portfolio` | Distribution CDN HTTPS |
| `aws_s3_bucket_policy.portfolio` | Autorisation CloudFront OAC uniquement |

**Choix techniques :**

| Choix | Justification |
|-------|---------------|
| S3 privé + OAC | Méthode recommandée depuis 2022 — remplace OAI ; sigv4 plus sécurisé |
| `PriceClass_100` | Europe + Amérique du Nord uniquement — optimise les coûts |
| `CachingOptimized` (ID géré AWS) | Cache agressif pour assets statiques — TTL par défaut 24h |
| `redirect-to-https` | HTTP → HTTPS automatique |
| `custom_error_response 403/404 → 200/index.html` | SPA fallback — gère les routes directes |
| `default_root_object = index.html` | Accès direct sans `/index.html` |

---

## 2. Déploiement du contenu

### Upload initial

```powershell
cd smart-assembly-line

# HTML principal
aws s3 cp src/portfolio/index.html `
  s3://smart-assembly-portfolio-169237360990/index.html `
  --content-type text/html --region eu-west-3

# Photo professionnelle
aws s3 cp src/portfolio/photo.png `
  s3://smart-assembly-portfolio-169237360990/photo.png `
  --content-type image/png --region eu-west-3

# Toutes les captures AWS
aws s3 sync src/portfolio/screenshots/ `
  s3://smart-assembly-portfolio-169237360990/screenshots/ `
  --content-type image/png --region eu-west-3
```

### Mise à jour (après modification du HTML)

```powershell
# 1. Re-upload index.html
aws s3 cp src/portfolio/index.html `
  s3://smart-assembly-portfolio-169237360990/index.html `
  --content-type text/html --region eu-west-3

# 2. Invalider le cache CloudFront (obligatoire — sinon les visiteurs voient l'ancienne version)
aws cloudfront create-invalidation `
  --distribution-id E271YNMVZ3GMXD `
  --paths "/*"
```

> **Note :** L'invalidation CloudFront prend ~30 secondes. Sans invalidation, le cache TTL par défaut est 24h.

---

## 3. Contenu du portfolio

### Sections

| Section | Contenu |
|---------|---------|
| **Hero** | Photo + nom + titre · Présentation projet · 4 métriques · 2 CTA |
| **Marquee AWS Live** | 2 rangées défilantes (sens opposés) · 13 captures AWS réelles |
| **Architecture** | Diagramme ASCII edge-to-cloud · 4 couches (Edge/IoT/Event/API) |
| **Résilience** | 9 patterns (Circuit Breaker, DLQ, Canary, Idempotency…) |
| **Chaos** | 5 scénarios testés (Lambda kill, DynamoDB throttle, ECS kill…) |
| **CI/CD** | Pipeline GitHub Actions 6 étapes |
| **Stack** | 6 groupes · services réellement utilisés uniquement |
| **Métriques** | 8 indicateurs mesurés (p99, RTO, throughput…) |
| **Preuves AWS** | 13 captures filtrables (CloudWatch/ECS/ALB/EventBridge/IoT/SF/CI/S3/DynamoDB) |
| **À propos** | Photo + biographie + cible septembre 2026 |

### Stack (services réellement utilisés)

- **IoT & Edge** : IoT Core, Greengrass v2, MQTT/TLS, Device Shadow, Rules Engine
- **Event-Driven** : Lambda Python 3.12, EventBridge, SQS + DLQ, Step Functions
- **Data & Stockage** : DynamoDB, S3, KMS CMK
- **API & Containers** : ECS Fargate, Spring Boot 3 / Java 21, ALB multi-AZ, ECR, App Auto Scaling
- **Observabilité** : CloudWatch Dashboard, CloudWatch Alarms, CloudTrail, Container Insights
- **IaC & CI/CD** : Terraform 1.9, GitHub Actions, Checkov (SARIF), S3 backend, Docker/ECR

> ⚠️ **Non inclus (non implémentés)** : Kinesis (pipeline IoT → SQS direct), S3 Lifecycle / Glacier (non disponible)

---

## 4. Features UI

- **Responsive** : Mobile (≤480px) / Mobile large (≤768px) / Tablette (≤1024px) / Bureau
- **Hamburger nav** sur mobile avec fermeture automatique au clic
- **Marquee défilant** : 2 rangées CSS-only, sens opposés, pause au hover
- **Galerie filtrée** : 9 filtres par service AWS, affichage/masquage instantané
- **Lightbox** : plein écran, navigation clavier (←/→/Échap)
- **Industry 4.0** : scan-line hero, coins HUD, pulse live, glow cards, status bar AWS live

---

## 5. Validation

```powershell
# Vérifier que le bucket contient les bons fichiers
aws s3 ls s3://smart-assembly-portfolio-169237360990/ --recursive --region eu-west-3

# Vérifier que CloudFront est bien déployé (Status = Deployed)
aws cloudfront get-distribution `
  --id E271YNMVZ3GMXD `
  --query "Distribution.Status" --region eu-west-3

# Tester l'URL publique
curl -I https://do1vmragia1j9.cloudfront.net
# Attendu : HTTP/2 200, x-cache: Hit from cloudfront
```

---

## Commit

```powershell
git add src/portfolio/index.html
git add src/portfolio/photo.png
git add src/portfolio/screenshots/
git add terraform/environments/dev/portfolio.tf
git add docs/runbooks/jour-43-portfolio.md

git commit -m "feat(jour-43): Portfolio AWS — S3 + CloudFront + Responsive + Industry 4.0

- portfolio.tf : S3 privé + CloudFront OAC (sigv4) + bucket policy
  URL publique : https://do1vmragia1j9.cloudfront.net
- index.html : portfolio single-page complet
  Hero 2 colonnes (photo + projet), marquee AWS live (13 captures, 2 rangées),
  galerie filtrée (9 services), lightbox, section À propos
- Responsive 3 niveaux : mobile/tablette/bureau + hamburger nav
- Style Industry 4.0 : scan-line, HUD corners, pulse live, glow, status bar
- Stack nettoyée : Kinesis et S3 Lifecycle/Glacier retirés (non implémentés)
- 13 captures AWS réelles : CloudWatch, ECS, ALB, EventBridge, IoT, Step Functions,
  CI/CD, S3 raw-data, DynamoDB machine_state

Closes #jour-43"

git push
```

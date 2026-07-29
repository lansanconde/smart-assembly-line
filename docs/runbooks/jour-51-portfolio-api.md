# Runbook — Jour 51 : Portfolio API Live + CloudFront auto-expiry

---

## Objectif

Exposer les 3 endpoints de `supervision-api` sur le portfolio CloudFront avec un arrêt automatique programmé au 31 décembre 2026. Mise à jour du portfolio (stack, métriques, section API Live).

---

## 1. Documents produits / modifiés

| Fichier | Action | Contenu |
|---|---|---|
| `src/portfolio/index.html` | Modifié | Section API Live, nav link, stack mis à jour (X-Ray, GuardDuty, Security Hub, AWS Config), métriques RTO/RPO/104ms |
| `terraform/environments/dev/cloudfront-api.tf` | Créé | CloudFront distribution → ALB (HTTP interne, HTTPS public) |
| `terraform/environments/dev/cloudfront-expiry.tf` | Créé | EventBridge Scheduler + Lambda → disable distribution le 31/12/2026 à 23h59 |

---

## 2. Architecture de l'arrêt automatique

```
EventBridge Scheduler
  └── at(2026-12-31T22:59:00 UTC)       ← 23h59 heure Paris
        │
        ▼
  Lambda cf_expiry (Python 3.12)
        │
        ▼
  CloudFront UpdateDistribution
        └── Enabled: false
            └── Distribution supervision-api désactivée
```

---

## 3. Commandes — Déployer et configurer

### Étape 1 — Créer la distribution CloudFront devant l'API

```powershell
cd terraform/environments/dev
terraform apply -target=aws_cloudfront_distribution.supervision_api

# Copier l'URL affichée dans la sortie Terraform :
terraform output supervision_api_cloudfront_url
# → "https://dXXXXXXXXXXXX.cloudfront.net"
```

### Étape 2 — Mettre à jour l'URL dans le portfolio

Ouvrir `src/portfolio/index.html` et remplacer **les 3 occurrences** de `YOUR_API_CF_URL`
par l'URL obtenue à l'étape 1 (ex: `https://dXXXXXXXXXXXX.cloudfront.net`).

> Raccourci VS Code : `Ctrl+H` → rechercher `YOUR_API_CF_URL` → remplacer → Remplacer tout

### Étape 3 — Uploader le portfolio mis à jour

```powershell
# 1. Upload index.html
aws s3 cp src/portfolio/index.html `
  s3://smart-assembly-portfolio-169237360990/index.html `
  --content-type text/html --region eu-west-3

# 2. Invalider le cache CloudFront portfolio
aws cloudfront create-invalidation `
  --distribution-id E271YNMVZ3GMXD `
  --paths "/*"
```

### Étape 4 — Déployer l'auto-expiry (EventBridge + Lambda)

```powershell
terraform apply -target=aws_lambda_function.cf_expiry `
                -target=aws_scheduler_schedule.cf_expiry
```

---

## 4. Vérification

```powershell
# Tester les 3 endpoints
$BASE = "https://VOTRE_ID.cloudfront.net"

Invoke-RestMethod "$BASE/api/machines"
Invoke-RestMethod "$BASE/api/machines/poste_1"
Invoke-RestMethod "$BASE/api/alerts"

# Vérifier que le scheduler est bien créé
aws scheduler get-schedule --name smart-assembly-cf-expiry-2026-12-31 --group-name default
```

---

## 5. Les 3 endpoints exposés

| Méthode | Endpoint | Description |
|---|---|---|
| GET | `/api/machines` | Liste tous les postes de travail supervisés |
| GET | `/api/machines/{idPoste}` | Détail d'un poste (ex: `poste_1`) |
| GET | `/api/alerts` | Postes en WARN ou CRITICAL |

---

## Commit

```powershell
git add src/portfolio/index.html
git add terraform/environments/dev/cloudfront-api.tf
git add terraform/environments/dev/cloudfront-expiry.tf
git add docs/runbooks/jour-51-portfolio-api.md
git add mkdocs.yml

git commit -m "feat(jour-51): Portfolio API Live + CloudFront auto-expiry 2026-12-31

- portfolio/index.html :
  Section API Live : 3 endpoints supervision-api avec boutons 'Tester'
  Nav link 'API Live' ajouté
  Stack mis à jour : X-Ray, GuardDuty, Security Hub, AWS Config
  Métriques ajoutées : 104ms latence X-Ray, RTO < 5min, RPO < 1s

- cloudfront-api.tf :
  Distribution CloudFront → ALB (HTTP origin, HTTPS public)
  PriceClass_100 (US + EU)
  TTL 0s (API temps réel)
  Output : supervision_api_cloudfront_url

- cloudfront-expiry.tf :
  Lambda cf_expiry (Python 3.12) : GetDistributionConfig + UpdateDistribution(Enabled=false)
  IAM least privilege : cloudfront:Get + Update seulement
  EventBridge Scheduler one-time : at(2026-12-31T22:59:00 UTC) = 23h59 Paris
  Arrêt automatique garanti au plus tard le 31/12/2026

Closes #jour-51"

git push
```

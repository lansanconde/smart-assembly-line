# Runbook — Jour 50 : Finalisation repo GitHub

---

## Objectif

Finaliser le repo GitHub : README complet prêt pour entretien, nettoyage des fichiers temporaires, mise à jour du `.gitignore`, et désindexation des fichiers qui ne doivent plus être trackés.

---

## 1. Documents produits / modifiés

| Fichier | Action | Contenu |
|---|---|---|
| `README.md` | Créé | Contexte, architecture ASCII, stack, patterns résilience, 5 chaos scenarios, trade-offs, métriques, setup |
| `.gitignore` | Mis à jour | Ajout : zips Lambda, __pycache__, target/ Maven, fichiers JSON temporaires, .idea/, .pytest_cache/ |

---

## 2. Nettoyage — commandes à exécuter en local

Ces commandes suppriment les fichiers temporaires et les désindexent du tracking Git :

```powershell
cd C:\Users\conde\smart-assembly-line

# ── Désindexer les fichiers maintenant dans .gitignore ────────────
# (git rm --cached supprime du tracking sans supprimer le fichier local)

# Terraform providers et state backups
git rm --cached terraform/environments/dev/terraform.tfstate.*.backup 2>$null
git rm --cached -r terraform/environments/dev/.terraform/ 2>$null

# Lambda zips
git rm --cached src/lambda/analyze_vibration/handler.zip 2>$null
git rm --cached src/lambda/detect_anomaly/handler.zip 2>$null
git rm --cached src/lambda/store_metrics/handler.zip 2>$null
git rm --cached terraform/environments/dev/log_intervention.zip 2>$null
git rm --cached terraform/environments/dev/sqs_processor.zip 2>$null

# Python cache
git rm --cached -r src/lambda/analyze_vibration/__pycache__/ 2>$null
git rm --cached -r src/lambda/tests/__pycache__/ 2>$null
git rm --cached -r .pytest_cache/ 2>$null

# Java target
git rm --cached -r src/supervision-api/target/ 2>$null

# Fichiers temporaires racine
git rm --cached e2e_validation.py 2>$null
git rm --cached event_malformed.json events_load.json expr.json expr_gsi.json 2>$null
git rm --cached gitignore item.json key.json reset.json 2>$null
git rm --cached store_logs.txt store_logs_full.txt 2>$null
git rm --cached terraform/environments/dev/expr.json terraform/environments/dev/key.json 2>$null

# Docs non implémentés (Grafana, SiteWise, ML)
git rm --cached docs/monitoring/grafana.md 2>$null
git rm --cached docs/monitoring/sitewise.md 2>$null
git rm --cached docs/ml/tinyml.md docs/ml/models/model_card.md 2>$null

# IDE IntelliJ
git rm --cached -r src/supervision-api/.idea/ 2>$null

# Puis supprimer physiquement les fichiers (optionnel — ils sont ignorés de toute façon)
Remove-Item -Force e2e_validation.py, event_malformed.json, events_load.json, `
  expr.json, expr_gsi.json, gitignore, item.json, key.json, reset.json, `
  store_logs.txt, store_logs_full.txt -ErrorAction SilentlyContinue

Remove-Item -Force terraform\environments\dev\expr.json, `
  terraform\environments\dev\key.json, `
  terraform\environments\dev\log_intervention.zip, `
  terraform\environments\dev\sqs_processor.zip -ErrorAction SilentlyContinue

Remove-Item -Force terraform\environments\dev\terraform.tfstate.*.backup -ErrorAction SilentlyContinue

Remove-Item -Recurse -Force src\lambda\analyze_vibration\__pycache__, `
  src\lambda\tests\__pycache__, .pytest_cache, `
  src\supervision-api\target -ErrorAction SilentlyContinue

Remove-Item -Force docs\monitoring\grafana.md, docs\monitoring\sitewise.md -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force docs\ml -ErrorAction SilentlyContinue
```

---

## 3. Vérification avant commit

```powershell
# Vérifier l'état du repo — rien de non voulu dans le staging
git status

# Vérifier que .gitignore couvre bien les nouveaux patterns
git check-ignore -v e2e_validation.py
git check-ignore -v src/lambda/analyze_vibration/handler.zip
git check-ignore -v src/supervision-api/target/
```

---

## Commit

```powershell
git add README.md
git add .gitignore
git add docs/runbooks/jour-50-finalisation.md
git add mkdocs.yml

git commit -m "feat(jour-50): Finalisation repo — README + nettoyage

- README.md :
  Contexte projet : 100K capteurs, Industrie 4.0 aérospatial
  Diagramme ASCII architecture complet (Edge → DR eu-central-1)
  Stack technique : 15+ services AWS
  9 patterns de résilience listés et contextualisés
  5 chaos scenarios avec résultats mesurés
  3 trade-offs : SQS/Kinesis/Kafka, Lambda/ECS, DynamoDB/RDS
  Métriques défendables : 104ms latence, RTO<5min, RPO<1s, ROI +69700%
  Structure repo, setup local, lien documentation MkDocs
  Template réponse System Design 5 minutes pour entretien

- .gitignore mis à jour :
  Zips Lambda et Terraform
  __pycache__ et .pyc
  target/ Maven
  .pytest_cache/
  Fichiers JSON temporaires de lab (racine + terraform/dev)
  .idea/ IntelliJ

Closes #jour-50"

git push
```

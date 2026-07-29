# Runbook — Jour 45 : Architecture multi-site (100 000 capteurs)

---

## Objectif

Concevoir l'évolution de l'architecture Smart Assembly Line vers un modèle multi-site capable de supporter 100 000 capteurs répartis sur plusieurs usines. Adapter le modèle de données DynamoDB et justifier le dimensionnement cible.

---

## 1. Documents produits

| Document | Chemin | Contenu |
|---|---|---|
| Théorie multi-site | `docs/architecture/multi-site.md` | Limites mono-site, hiérarchie industrielle, patterns Hub&Spoke / multi-région / edge, dimensionnement complet |
| Modèle de données | `docs/architecture/multi-site-data-model.md` | Schéma DynamoDB v2, access patterns, migration script, Terraform, code Lambda adapté |

---

## 2. Changements clés

### Modèle de données DynamoDB

**Avant (mono-site) :**
```
Table : machine_state
PK    : id_poste    "poste_1"
```

**Après (multi-site) :**
```
Table : machine_state_v2
PK    : site_poste_id    "TLS#A320#P12"   ← site#ligne#poste
SK    : sensor_type      "VIBRATION"
GSI   : statut-site-index (PK=statut, SK=site_id)
TTL   : expiration automatique 30 jours
```

### Hiérarchie industrielle cible

```
100 000 capteurs = 16 sites × 6 lignes × 10 postes × ~100 capteurs/poste
```

### Patterns d'accès

| Pattern | Query DynamoDB |
|---|---|
| État de tous les capteurs d'un poste | `Query PK = "TLS#A320#P12"` |
| Incidents actifs d'un site | `Query GSI statut-site-index, PK="EN_INTERVENTION", SK="TLS"` |
| Dashboard global tous sites | `Query GSI statut-site-index, PK="EN_INTERVENTION"` |

---

## 3. Dimensionnement justifié

| Paramètre | Valeur |
|---|---|
| Capteurs | 100 000 |
| Fréquence update (après agrégation Greengrass) | 1/10s par capteur |
| WCU requis | 10 000 WCU/s → 12 000 provisioned |
| RCU requis | 1 000 RCU/s → 1 200 provisioned |
| Mode DynamoDB (prod) | Provisioned + Auto Scaling |
| Économie vs PAY_PER_REQUEST | -82% |
| Seuil de bascule | ~200 WCU/s continus |
| Coût DynamoDB prod | ~6 760 €/mois |
| Coût infra totale prod | ~1 834 €/mois (avec Greengrass) |
| ROI industriel | +69 700% |

---

## 4. Vérification des fichiers

```powershell
# Vérifier les fichiers créés
ls docs\architecture\multi-site.md
ls docs\architecture\multi-site-data-model.md
ls docs\runbooks\jour-45-multi-site.md
```

---

## 5. Mise à jour mkdocs.yml

Ajouter dans la section `Architecture` :

```yaml
  - Architecture:
      - Vue d'ensemble: architecture/global.md
      - Composants & Services: architecture/components.md
      - Sécurité & IAM: architecture/security.md
      - Consolidation des axes: architecture/consolidation.md
      - "Multi-site — 100K capteurs": architecture/multi-site.md
      - "Modèle de données multi-site": architecture/multi-site-data-model.md
```

Et dans la section `Runbooks` :

```yaml
      - "Jour 45 — Architecture multi-site": runbooks/jour-45-multi-site.md
```

---

## Commit

```powershell
git add docs/architecture/multi-site.md
git add docs/architecture/multi-site-data-model.md
git add docs/runbooks/jour-45-multi-site.md
git add mkdocs.yml

git commit -m "feat(jour-45): Architecture multi-site — 100 000 capteurs

- docs/architecture/multi-site.md :
  Limites mono-site (hot partition, pas de site_id)
  Hiérarchie industrielle : 16 sites × 6 lignes × 10 postes × 100 capteurs
  Schéma DynamoDB v2 : PK site_id#line_id#poste_id + SK sensor_type
  Option A (clé composite) retenue + GSI statut-site-index
  IoT Core : Thing Groups par site, topics MQTT hiérarchiques
  Patterns : Hub&Spoke / Multi-région / Edge Processing distribué
  Dimensionnement : 10K WCU/s, 1K RCU/s, ~1 834 €/mois prod, ROI +69 700%

- docs/architecture/multi-site-data-model.md :
  Schéma complet machine_state_v2 avec TTL et GSI
  4 access patterns documentés avec code Python/Boto3
  Script de migration depuis machine_state (mono-site)
  Terraform : table + GSI + TTL + KMS + Auto Scaling prod
  Seuil PAY_PER_REQUEST → Provisioned : ~200 WCU/s
  Lambda analyze_vibration adapté pour extraction site_id depuis topic MQTT

Closes #jour-45"

git push
```

# Model Card — Isolation Forest Edge Anomaly Detector

> Standard MLOps : chaque modèle déployé en production dispose d'une fiche
> décrivant son contexte, ses performances et ses limites.
> Mise à jour à chaque nouvelle version.

---

## Identité du modèle

| Champ | Valeur |
|-------|--------|
| Nom | `smart-assembly-anomaly-detector` |
| Version courante | `v1` |
| Algorithme | Isolation Forest (scikit-learn) |
| Type | Détection d'anomalies non supervisée |
| Date d'entraînement | À remplir après Jour 32 |
| Entraîné par | Lansana CONDÉ |
| Fichier | `models/model_current.pkl` |

---

## Problème résolu

Détecter des anomalies de comportement capteur sur une ligne d'assemblage
aérospatiale que les seuils statiques ne capturent pas :

- **Anomalie de pattern** : vibration sous le seuil mais variabilité anormale
- **Anomalie multivariée** : combinaison (vibration, température, pression) jamais observée en conditions normales

---

## Données d'entraînement

| Champ | Valeur |
|-------|--------|
| Source | `publish_vibration_edge.py` (simulateur capteur poste_1) |
| Taille | 200 mesures (warm-up in-situ) |
| Période | À remplir après Jour 32 |
| Conditions | Machine en état normal, opérateur présent |
| Label | Aucun (apprentissage non supervisé) |

---

## Features

| # | Feature | Description |
|---|---------|-------------|
| 0 | `vibration` | Vibration instantanée (m/s²) |
| 1 | `temperature` | Température instantanée (°C) |
| 2 | `pression` | Pression instantanée (bar) |
| 3 | `vib_mean_10` | Moyenne vibration sur fenêtre 10 mesures |
| 4 | `vib_std_10` | Écart-type vibration sur fenêtre 10 mesures |
| 5 | `vib_max_10` | Maximum vibration sur fenêtre 10 mesures |
| 6 | `temp_mean_10` | Moyenne température sur fenêtre 10 mesures |
| 7 | `temp_std_10` | Écart-type température sur fenêtre 10 mesures |
| 8 | `vib_x_temp` | Produit vibration × température (corrélation instantanée) |
| 9 | `vib_cv` | Coefficient de variation vib_std / vib_mean (instabilité relative) |

---

## Hyperparamètres

```python
IsolationForest(
    n_estimators  = 100,   # nombre d'arbres
    contamination = 0.05,  # % estimé d'anomalies dans le train
    max_samples   = 'auto',
    random_state  = 42,
)
StandardScaler()           # normalisation pré-entraînement
```

---

## Performances

| Métrique | Valeur | Seuil cible |
|----------|--------|-------------|
| Taux faux positifs (train) | À mesurer | < 5% |
| Détection anomalies synthétiques (vib=5.0) | À mesurer | > 99% |
| Latence inférence (edge) | À mesurer | < 5ms |
| Taille fichier pkl | À mesurer | < 500 Ko |

---

## Seuil de décision

```python
ANOMALY_THRESHOLD = -0.1
# score < -0.1  → ANOMALY  (ml_detected=True)
# score >= -0.1 → NORMAL   (ml_detected=False)
```

Ajuster selon le taux de faux positifs observé en production.

---

## Limites connues

- Entraîné sur données **simulées** (pas de données réelles machine)
- Warm-up de 200 mesures : si les premières mesures sont anormales, le modèle apprend un "normal" incorrect
- Pas de gestion du drift automatique en v1 (retrain manuel)
- Un seul poste (`poste_1`) — non généralisable sans re-entraînement sur d'autres postes

---

## Déploiement

| Environnement | Méthode | Fichier |
|---------------|---------|---------|
| Développement | Entraîné in-situ au démarrage | en mémoire (pas de pkl) |
| Production (cible) | Téléchargé depuis S3 au démarrage | `s3://smart-assembly-models/edge/model_current.pkl` |

---

## Historique des versions

| Version | Date | Changements | Métriques |
|---------|------|-------------|-----------|
| v1 | Jour 32 | Version initiale, warm-up 200 mesures | À compléter |

---

## Monitoring et retrain

**Trigger retrain si :**
- Taux d'anomalies détectées > 10% sur 100 mesures consécutives (drift probable)
- Retrain calendaire : tous les 30 jours
- Signal opérateur : "machine réparée / reconfigurée"

**Procédure retrain :** voir `docs/runbook/index.md` → section TinyML

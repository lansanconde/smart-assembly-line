---

## 7. TinyML — Inférence Edge (Jour 32)

### 7.1 Contexte et positionnement

**TinyML au sens strict** désigne des modèles ML inférés sur des microcontrôleurs (Arduino, STM32, ESP32) avec quelques kB de RAM. Dans notre projet, le terme est utilisé au sens large : **inférence ML légère à l'edge**, exécutée dans le conteneur Docker qui simule le device edge. L'esprit est identique : décision locale, sans round-trip vers le cloud.

**Pourquoi faire de l'inférence à l'edge et pas dans le cloud ?**

| Critère | Inférence cloud | Inférence edge |
|---------|----------------|----------------|
| Latence | 50-200ms (réseau) | < 5ms (local) |
| Disponibilité | Dépend du réseau | Toujours disponible |
| Coût | API calls facturés | CPU local gratuit |
| Confidentialité | Données envoyées | Données restent locales |
| Cas d'usage | Modèles lourds | Décisions temps réel |

Dans un contexte aérospatial, une anomalie vibratoire détectée en 2ms edge plutôt qu'en 200ms cloud peut éviter un incident sur une pièce critique tournant à 10 000 RPM.

### 7.2 Limitation des seuils statiques

Notre analyzer actuel utilise des règles fixes :
```
vibration > 2.0  → WARN
vibration > 2.5  → CRITICAL
```

Ces seuils ratent deux classes d'anomalies réelles :

**Anomalie de pattern** : vibration à 1.8 (sous le seuil) mais avec une variabilité anormalement élevée sur les 10 dernières mesures — signe d'un roulement qui commence à s'user.

**Anomalie multivariée** : vibration à 1.9 ET température à 78°C pris séparément sont normaux, mais cette combinaison précise n'existe jamais dans les données normales — corrélation anormale.

Un modèle ML apprend ces patterns automatiquement depuis les données, sans qu'on les programme explicitement.

### 7.3 Choix algorithmique : Isolation Forest

#### Pourquoi pas un classifieur supervisé ?

Un classifieur (Random Forest, SVM) nécessite des données **labellisées** : "ceci est normal", "ceci est une anomalie". On n'a pas de labels — on ne sait pas a priori quelles combinaisons sont anormales sur une nouvelle ligne d'assemblage.

#### Isolation Forest (Liu et al., 2008)

**Principe** : une anomalie est un point qui s'isole facilement de l'ensemble des données. L'algorithme construit des arbres de décision aléatoires. Plus un point est isolé rapidement (peu de coupures nécessaires), plus son score d'anomalie est élevé.

```
Données normales : regroupées → difficiles à isoler → chemin long dans l'arbre
Anomalies        : isolées   → faciles à isoler   → chemin court dans l'arbre
```

**Score de décision** : retourne un score entre -1 et 1.
- Score proche de +1 : point normal
- Score proche de -1 : anomalie probable
- Seuil typique : -0.1 (ajustable selon la tolérance aux faux positifs)

**Avantages pour notre cas :**
- Non supervisé : pas besoin de labels
- Efficace sur données multivariées (vibration + température + pression ensemble)
- Léger : quelques Ko en mémoire une fois entraîné
- Robuste aux données de haute dimension

**Hyperparamètres clés :**
```python
IsolationForest(
    n_estimators=100,    # nombre d'arbres (100 = bon équilibre perf/vitesse)
    contamination=0.05,  # % estimé d'anomalies dans les données d'entraînement
    max_samples='auto',  # taille de chaque sous-échantillon
    random_state=42      # reproductibilité
)
```

### 7.4 Pipeline ML complet

Le pipeline suit les étapes CRISP-DM adapté au contexte IoT edge.

```
┌────────────────────────────────────────────────────────────────────┐
│                       PIPELINE ML COMPLET                          │
│                                                                    │
│  1.COLLECTE   2.FEATURES   3.TRAIN    4.EVAL   5.DEPLOY           │
│  ─────────    ─────────    ───────    ──────   ──────             │
│  Données      Rolling      Isolation  Scores   joblib             │
│  capteurs  →  stats    →   Forest  →  AUC   →  pickle  →         │
│  (brutes)     fenêtre 10   sklearn    PR        S3/image           │
│                                                                    │
│  6.INFÉRENCE  7.MONITOR    8.RETRAIN                              │
│  ─────────    ─────────    ─────────                              │
│  predict() →  drift     →  trigger →  (retour étape 1)           │
│  < 5ms        détection    auto                                   │
└────────────────────────────────────────────────────────────────────┘
```

#### Étape 1 : Collecte des données

On collecte les N premières mesures reçues par l'analyzer en phase "normale" (capteur fonctionnel, pas d'anomalie connue). Ces données constituent le **jeu d'entraînement**.

Dans notre implémentation, l'analyzer collecte automatiquement les 200 premières mesures avant d'entraîner le modèle (phase de warm-up).

#### Étape 2 : Feature Engineering

Les features brutes (vibration, température, pression à l'instant t) ne capturent pas les patterns temporels. On enrichit avec des **features de fenêtre glissante** sur les 10 dernières mesures :

```python
features = [
    # Mesures brutes
    vibration_t, temperature_t, pression_t,

    # Rolling stats vibration (fenêtre 10)
    vib_mean_10, vib_std_10, vib_max_10,

    # Rolling stats température (fenêtre 10)
    temp_mean_10, temp_std_10,

    # Features croisées (corrélations)
    vib_t * temp_t,            # produit (corrélation instantanée)
    vib_std_10 / vib_mean_10,  # coefficient de variation (instabilité relative)
]
```

**Pourquoi ces features ?**
- `vib_std_10` : détecte les vibrations erratiques avant que la moyenne dépasse le seuil
- `vib_std / vib_mean` : coefficient de variation — un roulement usé a un CV élevé même à vibration moyenne basse
- `vib * temp` : capture les anomalies de corrélation multivariées

#### Étape 3 : Entraînement

```python
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
import joblib

# Normalisation (important : IF est sensible aux échelles)
scaler = StandardScaler()
X_train = scaler.fit_transform(features_matrix)

# Entraînement
model = IsolationForest(n_estimators=100, contamination=0.05, random_state=42)
model.fit(X_train)

# Sérialisation
joblib.dump({"model": model, "scaler": scaler}, "model.pkl")
```

L'entraînement dure < 1 seconde pour 200 points. Le fichier `model.pkl` fait < 500 Ko.

#### Étape 4 : Évaluation

Sans labels vrais, l'évaluation est indirecte :

**Taux de faux positifs** : sur les données d'entraînement "normales", le modèle doit prédire NORMAL dans ~95% des cas (cohérent avec `contamination=0.05`).

**Injection d'anomalies synthétiques** : générer des points avec vibration = 5.0 et vérifier que le modèle les détecte → taux de détection attendu > 99%.

**Score de décision** : tracer la distribution des scores sur les données de validation pour vérifier la séparation normal/anomalie.

```python
scores = model.decision_function(X_val)
# scores négatifs = anomalies probables
# distribution bimodale attendue = bonne séparation
```

#### Étape 5 : Sérialisation et versioning

```python
import joblib
from datetime import datetime

version = datetime.now().strftime("%Y%m%d_%H%M")
joblib.dump({
    "model": model,
    "scaler": scaler,
    "version": version,
    "n_train": len(X_train),
    "features": FEATURE_NAMES,
    "contamination": 0.05,
}, f"models/model_{version}.pkl")
```

### 7.5 Déploiement du modèle

#### Option A — Modèle statique dans l'image Docker (développement)

Le modèle est copié dans l'image au moment du build. Simple mais rigide : un changement de modèle nécessite un rebuild.

```dockerfile
COPY models/model_current.pkl /app/models/model.pkl
```

**Usage** : environnement de dev, Jour 32.

#### Option B — Modèle dynamique depuis S3 (production)

Le conteneur télécharge le modèle depuis S3 au démarrage. Mise à jour sans rebuild d'image.

```python
import boto3, joblib

def load_model_from_s3():
    s3 = boto3.client("s3")
    s3.download_file(
        "smart-assembly-models",
        "edge/model_current.pkl",
        "/app/models/model.pkl"
    )
    return joblib.load("/app/models/model.pkl")
```

**Architecture S3 :**
```
s3://smart-assembly-models/
  edge/
    model_current.pkl           ← toujours le modèle en prod
    model_20260719_1030.pkl     ← archive versionnée
    metadata.json               ← version, métriques, date
```

**Usage** : production, Semaine 7 (CI/CD).

### 7.6 Industrialisation MLOps

L'industrialisation répond à la question : comment s'assurer que le modèle reste performant dans le temps et que les mises à jour sont sûres ?

#### 7.6.1 Concept Drift — Détection de dérive

Un modèle entraîné en juillet peut devenir obsolète en octobre si les conditions changent (nouveau lot de pièces, usure normale des machines). C'est le **concept drift**.

**Détection par score moyen glissant :**
```python
avg_score = np.mean(recent_scores[-100:])
if avg_score < DRIFT_THRESHOLD:
    trigger_retrain()
```

**Détection par taux d'anomalies :**
```python
anomaly_rate = sum(preds == -1) / len(preds)
if anomaly_rate > 2 * contamination:
    alert("drift_detected")
```

#### 7.6.2 Pipeline de retrain automatique

```
Trigger :
  - Drift détecté (score moyen < seuil)
  - Calendrier (ex : tous les 30 jours)
  - Manuel (opérateur)

Étapes :
  1. Collecter N nouvelles mesures normales (opérateur confirme "machine OK")
  2. Entraîner nouveau modèle (Colab ou Lambda)
  3. Évaluer : taux FP < 5%, détection anomalies synthétiques > 99%
  4. Si OK → publier sur S3 (model_current.pkl)
  5. Conteneur edge recharge le modèle au prochain restart
```

#### 7.6.3 Shadow Mode — Déploiement sans risque

Avant de remplacer un modèle en production, on le teste en **shadow mode** : le nouveau modèle tourne en parallèle mais ses prédictions ne déclenchent pas d'alertes — elles sont seulement loguées et comparées à l'ancien.

```
Mesure → Ancien modèle → décision réelle (alerte ou non)
       → Nouveau modèle → prédiction loguée uniquement
```

Après 24h en shadow, si les prédictions convergent → promotion du nouveau modèle.

#### 7.6.4 Canary Deployment

Déploiement progressif : 10% des devices edge reçoivent le nouveau modèle, 90% gardent l'ancien. Si aucune anomalie de comportement → déploiement à 100%.

#### 7.6.5 Model Registry

```
s3://smart-assembly-models/registry/
  model_v1_20260719.pkl   → métriques: FP=4.2%
  model_v2_20260826.pkl   → métriques: FP=3.8%
  metadata/
    model_v2.json → {
      "version": "v2",
      "contamination": 0.05,
      "n_train": 5000,
      "features": [...],
      "eval": {"fp_rate": 0.038, "auc_pr": 0.94},
      "deployed_at": "2026-08-26",
      "trained_by": "lansana@"
    }
```

### 7.7 Google Colab — Quand et pourquoi

| Phase | Local / Docker | Colab |
|-------|---------------|-------|
| Entraînement < 1 000 points | suffisant | inutile |
| Entraînement > 10 000 points | lent | GPU/TPU gratuits |
| Exploration et visualisation | possible | natif (matplotlib, seaborn) |
| Partage notebook avec l'équipe | difficile | URL partageable |
| MLflow, Weights & Biases | à installer | pré-installé |
| Déploiement en production | non | non (Colab = dev uniquement) |

**Workflow recommandé :**
```
1. Colab : exploration, feature engineering, tuning hyperparamètres
           ↓ export model.pkl
2. Test local : intégration dans analyzer.py
           ↓ si OK
3. S3 : publication du modèle versionné
           ↓ téléchargement au démarrage du conteneur
4. Docker : inférence en production
```

**Pour Jour 32 :** entraînement directement dans l'analyzer (warm-up 200 mesures → fit) car le dataset est petit. Pour l'industrialisation (Semaine 7), on bascule vers Colab + S3.

### 7.8 Architecture cible Jour 32

```
publish_vibration_edge.py
        │ MQTT (paho)
        ▼
   Mosquitto:1883 (Docker)
        │
        ▼
   analyzer.py
        │
        ├── Phase WARM-UP (200 premières mesures)
        │       └── collecte features → entraînement Isolation Forest
        │
        ├── Phase INFÉRENCE (après warm-up)
        │       ├── Seuils statiques   → WARN / CRITICAL (inchangé)
        │       └── Isolation Forest   → ANOMALY (nouveau)
        │               tag: ml_detected=True, anomaly_score=-0.32
        │
        ├── Circuit Breaker (Jour 31, inchangé)
        │
        └── IoT Core → Lambda → DynamoDB
                   payload enrichi: {statut, ml_detected, anomaly_score}
```

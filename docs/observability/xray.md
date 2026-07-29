# AWS X-Ray — Distributed Tracing

---

## Objectif

Compléter le triptyque d'observabilité du Smart Assembly Line avec le **tracing distribué**. Là où CloudWatch répond à "quoi" (métriques) et "pourquoi" (logs), X-Ray répond à "où" — où exactement dans la chaîne de traitement une requête ralentit ou échoue.

---

## 1. Le triptyque observabilité

```
┌──────────────────────────────────────────────────────────────────┐
│                    OBSERVABILITÉ COMPLÈTE                         │
├────────────────┬───────────────────┬─────────────────────────────┤
│   MÉTRIQUES    │      LOGS         │       TRACES                │
│  CloudWatch    │  CloudWatch Logs  │      AWS X-Ray              │
│                │                   │                             │
│ "Quoi se       │ "Pourquoi ça      │ "Où exactement dans         │
│  passe ?"      │  a échoué ?"      │  la chaîne ça ralentit ?"  │
│                │                   │                             │
│ CPU, latence,  │ Stack traces,     │ Chemin complet d'une        │
│ error rate,    │ messages d'erreur,│ requête de IoT Core         │
│ throughput     │ événements métier │ jusqu'à DynamoDB            │
└────────────────┴───────────────────┴─────────────────────────────┘

Les trois sont complémentaires — X-Ray ne remplace pas CloudWatch,
il le complète en ajoutant la dimension "chemin de la requête".
```

---

## 2. Concepts fondamentaux X-Ray

### Trace, Segment, Subsegment

```
TRACE
  Représente le parcours complet d'une requête à travers le système.
  Identifié par un Trace ID unique (ex: 1-5e1b4f3a-0e2b4f3a0e2b4f3a0e2b4f3a)

  SEGMENT (1 par service AWS)
    Représente le travail d'un service unique dans la trace.
    Ex : le segment Lambda "analyze_vibration"

    SUBSEGMENT (1 par opération interne)
      Opération atomique dans un segment.
      Ex : l'appel DynamoDB put_item dans la Lambda
      Ex : l'appel à un service externe

Exemple pour une requête IoT → Lambda → DynamoDB :

Trace ID: 1-5f4a3b2c-...
│
├── Segment: IoT Rule (durée: 2ms)
│
├── Segment: Lambda analyze_vibration (durée: 245ms)
│     ├── Subsegment: Initialization (durée: 180ms) ← cold start détecté
│     ├── Subsegment: DynamoDB.update_item (durée: 45ms)
│     └── Subsegment: SNS.publish (durée: 12ms)
│
└── Segment: DynamoDB machine_state_v2 (durée: 45ms)
      └── Subsegment: ProvisionedThroughput check (durée: 1ms)
```

### Annotations vs Metadata

```
ANNOTATIONS (indexées — filtrables dans X-Ray console)
  Paires clé-valeur simples, indexées pour la recherche.
  Limite : 50 annotations par trace.
  Usage : filtrer les traces par site_id, poste_id, sensor_type

  Exemple :
    xray_recorder.put_annotation('site_id', 'TLS')
    xray_recorder.put_annotation('sensor_type', 'VIBRATION')
    xray_recorder.put_annotation('anomalie_score', 0.92)

METADATA (non indexées — contexte riche)
  Données complexes (JSON, listes) non filtrables mais visibles dans la trace.
  Usage : payload complet, context de debug

  Exemple :
    xray_recorder.put_metadata('sensor_payload', {
        'valeur': 12.7,
        'seuil': 10.0,
        'timestamp': '2026-07-29T14:23:11Z'
    })
```

### Sampling Rules

```
Le sampling détermine quel pourcentage de requêtes est tracé.
Tracer 100% = coût élevé + bruit. Tracer 0% = pas de visibilité.

Règle par défaut AWS :
  - 1 requête/seconde garantie (reservoir)
  - 5% des requêtes supplémentaires

Règle custom pour Smart Assembly Line :
  - Requêtes NORMALES     : 5% (bruit de fond)
  - Requêtes EN_INTERVENTION : 100% (on trace tout ce qui est anomalie)
  - Lambda cold start     : 100% (performance critique)
  - Erreurs (5xx)         : 100% (debug systématique)
```

---

## 3. Service Map — Visualisation de l'architecture

La Service Map X-Ray génère automatiquement un graphe de l'architecture à partir des traces collectées :

```
                    ┌─────────────┐
   MQTT/TLS         │  IoT Core   │
Greengrass ────────►│  Rule SQL   │
                    └──────┬──────┘
                           │ invoke
                    ┌──────▼──────┐
                    │   Lambda    │
                    │analyze_     │◄── cold start détecté (P99: 450ms)
                    │vibration    │
                    └──────┬──────┘
                    ┌──────┴──────┬─────────────────┐
                    │             │                 │
             ┌──────▼──────┐ ┌───▼───┐    ┌────────▼───────┐
             │  DynamoDB   │ │  SNS  │    │  EventBridge   │
             │machine_state│ │alerts │    │ anomaly.events │
             │    _v2      │ └───────┘    └────────────────┘
             └─────────────┘

Chaque nœud affiche :
  ✓ Latence moyenne (P50, P90, P99)
  ✓ Taux d'erreur (%)
  ✓ Taux de throttle (%)
  ✓ Nombre de requêtes/min
```

En couleur :
- **Vert** : sain (< 1% erreurs)
- **Jaune** : dégradé (throttling ou latence élevée)
- **Rouge** : critique (> 5% erreurs ou timeout)

---

## 4. Intégration avec les services du projet

### Lambda — activation automatique

```python
# Activation X-Ray sur Lambda : 2 étapes

# 1. Dans Terraform : tracing_config { mode = "Active" }
# 2. Dans le code Python : aws-xray-sdk

from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patche automatiquement boto3, requests, etc.
patch_all()

@xray_recorder.capture('analyze_vibration_handler')
def lambda_handler(event, context):
    site_id     = event.get('site_id', 'TLS')
    sensor_type = event.get('sensor_type', 'VIBRATION')
    valeur      = float(event.get('valeur', 0))

    # Annotation indexée — filtrable dans X-Ray console
    xray_recorder.put_annotation('site_id', site_id)
    xray_recorder.put_annotation('sensor_type', sensor_type)
    xray_recorder.put_annotation('valeur', valeur)

    with xray_recorder.in_subsegment('threshold_check') as subsegment:
        seuil = SEUILS.get(sensor_type, 10.0)
        statut = 'EN_INTERVENTION' if valeur > seuil else 'NOMINAL'
        anomalie_score = min(valeur / (seuil * 1.5), 1.0)

        subsegment.put_annotation('statut', statut)
        subsegment.put_annotation('anomalie_score', round(anomalie_score, 3))

    # DynamoDB est automatiquement tracé via patch_all()
    # → un subsegment DynamoDB.update_item apparaît dans la trace
    dynamodb.update_item(...)

    return {'statusCode': 200, 'statut': statut}
```

### ECS Fargate — X-Ray Daemon en sidecar

Pour ECS, X-Ray nécessite un **daemon sidecar** dans la task definition :

```
Task Definition supervision-api
  ├── Container : supervision-api  (ton application)
  │     └── Envoie les segments UDP → localhost:2000
  │
  └── Container : xray-daemon     (sidecar AWS officiel)
        └── Collecte les segments UDP et les envoie à X-Ray API
```

```python
# Dans supervision-api (FastAPI/Flask)
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.ext.flask.middleware import XRayMiddleware

app = Flask(__name__)

xray_recorder.configure(
    service='supervision-api',
    daemon_address='127.0.0.1:2000'  # sidecar xray-daemon
)

XRayMiddleware(app, xray_recorder)
```

### DynamoDB — tracing automatique

Avec `patch_all()` ou `patch(['boto3'])`, chaque appel DynamoDB génère automatiquement un subsegment avec :
- Nom de la table
- Opération (query, put_item, update_item)
- Durée
- Clé d'accès (PK/SK)
- Consommation RCU/WCU (via ResponseMetadata)

---

## 5. X-Ray Insights — Détection d'anomalies automatique

X-Ray Insights analyse automatiquement les traces pour détecter des **anomalies statistiques** :

```
Exemples d'insights générés :
  ⚠ "La latence P99 de analyze_vibration a augmenté de 340% à 14h23"
     → DynamoDB throttling détecté dans les subsegments

  ⚠ "Taux d'erreur de supervision-api a atteint 8.3% (seuil: 2%)"
     → 3 traces en erreur liées au même endpoint /api/postes/{id}

  ✓ "Retour à la normale — anomalie résolue à 14h31"
     → Durée de l'incident : 8 minutes
```

Ces insights sont envoyables vers EventBridge → SNS pour alerter.

---

## 6. CloudWatch ServiceLens

ServiceLens est l'intégration X-Ray + CloudWatch dans la console AWS. Elle corrèle :

```
Pour une même ressource Lambda ou ECS :
  ✓ Métriques CloudWatch (invocations, erreurs, durée)
  ✓ Logs CloudWatch (messages d'erreur détaillés)
  ✓ Traces X-Ray (chemin complet de la requête)

→ Depuis un pic d'erreur sur un graphe CloudWatch,
  on peut cliquer pour voir les traces X-Ray correspondantes,
  puis ouvrir les logs du même span de temps.
```

C'est le "single pane of glass" pour le debug en production.

---

## 7. Cas d'usage concrets — Smart Assembly Line

### Cas 1 — Détecter un cold start Lambda excessif

```
Symptôme observé : latence P99 > 800ms sur analyze_vibration

Sans X-Ray : on voit la métrique Duration élevée → impossible de savoir pourquoi

Avec X-Ray :
  Trace filtrée : annotation cold_start = true
  Subsegment "Initialization" : 650ms
  → Cold start identifié, solution : Provisioned Concurrency ou Lambda SnapStart
```

### Cas 2 — Identifier un goulot DynamoDB

```
Symptôme : erreurs 500 sporadiques sur /api/postes/{id}

Avec X-Ray :
  Service Map : DynamoDB en rouge (throttle: 12%)
  Subsegment DynamoDB : ProvisionedThroughputExceededException
  → WCU undersized, solution : augmenter WCU ou passer PAY_PER_REQUEST
```

### Cas 3 — Tracer une anomalie end-to-end

```
Capteur TLS#A320#P12 → vibration = 12.7 (anormale)

Trace complète :
  T+0ms   : IoT Rule déclenche (2ms)
  T+2ms   : Lambda invoquée (cold start: 180ms + exec: 65ms = 245ms total)
  T+47ms  : DynamoDB update_item (45ms)
  T+92ms  : SNS publish (12ms)
  T+104ms : EventBridge put_events (8ms)
  ─────────────────────────────────────
  Durée totale : 104ms (latence end-to-end capteur → alerte)
```

---

## 8. Concepts clés retenus

**Traces vs Métriques** : une métrique dit "il y a eu 50 erreurs entre 14h00 et 14h05". Une trace dit "voici exactement ce qui s'est passé pour la requête n°42 qui a échoué : elle a mis 450ms sur DynamoDB avant de timeout". Les deux sont nécessaires.

**Sampling obligatoire** : tracer 100% des requêtes en production haute charge n'est pas viable (coût + performance). Le sampling intelligent (100% sur erreurs + anomalies, 5% sur nominal) donne la visibilité sans le coût.

**patch_all() vs instrumentation manuelle** : `patch_all()` instrumente automatiquement boto3, requests, httplib. L'instrumentation manuelle avec `@xray_recorder.capture()` et `put_annotation()` ajoute le contexte métier (site_id, sensor_type) que X-Ray ne peut pas deviner seul.

**Sidecar vs Lambda Layer** : sur Lambda, X-Ray est géré par le runtime AWS (pas de sidecar). Sur ECS Fargate, il faut obligatoirement le daemon xray en sidecar car il n'y a pas d'agent intégré dans le runtime.

**ServiceLens = observabilité unifiée** : c'est la réponse AWS au problème du "context switching" entre plusieurs outils de monitoring. Métriques + logs + traces dans une seule vue, corrélés temporellement.

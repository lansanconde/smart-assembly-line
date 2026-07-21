# IoT SiteWise — Monitoring Industriel (Théorie)

> IoT SiteWise n'est pas disponible en eu-west-3 (Paris).
> Cette section documente l'architecture cible pour un déploiement en production
> sur une région supportée (eu-west-1, us-east-1...).
> L'implémentation pratique utilise Amazon Managed Grafana + CloudWatch (voir `grafana.md`).

---

## 1. Positionnement

AWS IoT SiteWise est un service managé de **monitoring d'équipements industriels**.
Il ne remplace pas IoT Core — il le complète :

```
IoT Core       → ingestion, routing, règles
IoT SiteWise   → modélisation, calculs industriels, historique structuré
```

| Dimension | IoT Core | IoT SiteWise |
|-----------|----------|--------------|
| Rôle | Connectivité MQTT, règles | Modèle de données industriel |
| Données | Messages bruts | Propriétés structurées par asset |
| Calculs | Lambda (custom) | Transforms et Metrics natifs |
| Historique | DynamoDB (custom) | Storage SiteWise intégré |
| Visualisation | Aucune native | SiteWise Monitor (dashboards no-code) |
| OPC-UA | Non | Oui (gateway SiteWise) |

---

## 2. Concepts fondamentaux

### 2.1 Asset Model

Un **Asset Model** est le gabarit qui décrit un type d'équipement.
Il définit les propriétés mesurables, les calculs et les relations hiérarchiques.

```
AssetModel : PosteAssemblage
  Properties :
    ├── Measurements (données brutes capteurs)
    │     ├── vibration      (DOUBLE, m/s²)
    │     ├── temperature    (DOUBLE, °C)
    │     └── pression       (DOUBLE, bar)
    │
    ├── Transforms (calculs sur mesures brutes, temps réel)
    │     ├── vibration_ms   = vibration * 1000    (conversion m/s² → mm/s²)
    │     └── temp_fahrenheit = temperature * 9/5 + 32
    │
    ├── Metrics (agrégats sur fenêtre temporelle)
    │     ├── vibration_moy_1h  = avg(vibration)   sur 1h
    │     ├── temp_max_1h       = max(temperature) sur 1h
    │     └── taux_critique_1h  = (count_critical / count_total) * 100 sur 1h
    │
    └── Hierarchies (relations parent/enfant)
          └── appartient_a → LigneAssemblage
```

**Measurements** : valeurs brutes envoyées par les capteurs. Pas de calcul.

**Transforms** : formules appliquées sur chaque nouvelle valeur. Résultat immédiat.
```
formula: vibration * 1000
```

**Metrics** : agrégats calculés sur une fenêtre temporelle (1min, 1h, 1j...).
Utiles pour les KPIs industriels (OEE, taux de défaut, disponibilité).
```
formula: avg(vibration)
window:  tumbling(1h)
```

### 2.2 Asset

Un **Asset** est une instance d'un Asset Model — l'équipement réel.

```
Asset : poste_1  (instance de PosteAssemblage)
  ├── vibration      → flux MQTT assembly-line/poste_1/metrics
  ├── temperature    → même flux
  └── pression       → même flux

Asset : poste_2  (autre instance du même modèle)
  └── ...
```

La puissance : définir le modèle une fois, instancier N assets.
Chaque asset a son propre historique, ses propres alertes, ses propres metrics.

### 2.3 Hiérarchie d'assets

SiteWise permet de modéliser la hiérarchie physique réelle d'une usine :

```
LigneAssemblage (Asset Model : Ligne)
  ├── poste_1  (Asset : PosteAssemblage)
  ├── poste_2  (Asset : PosteAssemblage)
  └── poste_3  (Asset : PosteAssemblage)

Usine (Asset Model : Site)
  ├── ligne_A  (Asset : LigneAssemblage)
  │     ├── poste_1
  │     └── poste_2
  └── ligne_B  (Asset : LigneAssemblage)
        └── poste_3
```

Cette hiérarchie est navigable dans SiteWise Monitor et dans l'API.
On peut agréger les métriques à chaque niveau (poste → ligne → usine).

### 2.4 OEE — Overall Equipment Effectiveness

L'OEE est le KPI industriel standard. SiteWise le calcule nativement via des Metrics.

```
OEE = Disponibilité × Performance × Qualité

Disponibilité  = temps_productif / temps_planifié
Performance    = production_réelle / production_théorique
Qualité        = pièces_conformes / pièces_produites
```

Dans notre contexte aérospatial :
```
SiteWise Metric : disponibilite_poste_1
  formula: (3600 - sum(duree_arret)) / 3600 * 100
  window:  tumbling(1h)

SiteWise Metric : taux_anomalie_poste_1
  formula: sum(nb_critical) / sum(nb_total) * 100
  window:  tumbling(1h)
```

---

## 3. Flux de données avec IoT Core

```
Capteur
  │ MQTT
  ▼
IoT Core
  │ IoT Rule : republish vers SiteWise
  ▼
IoT SiteWise
  │
  ├── Storage (historique 30 jours natif, extensible S3 Cold Tier)
  ├── Transforms → calculs temps réel
  ├── Metrics → OEE, KPIs sur fenêtre temporelle
  └── SiteWise Monitor → dashboards no-code
```

### IoT Rule → SiteWise (action native)

```json
{
  "sql": "SELECT * FROM 'assembly-line/+/metrics'",
  "actions": [{
    "iotSiteWise": {
      "putAssetPropertyValueEntries": [{
        "assetId": "${topic(2)}",
        "propertyAlias": "/poste/${topic(2)}/vibration",
        "propertyValues": [{
          "value": { "doubleValue": "${vibration}" },
          "timestamp": { "timeInSeconds": "${timestamp}" }
        }]
      }]
    }
  }]
}
```

L'action `iotSiteWise` est disponible dans IoT Rules — contrairement à `eventBridge`
qui n'était pas supportée en eu-west-3.

---

## 4. SiteWise Monitor — Dashboards no-code

SiteWise Monitor est l'interface web native pour visualiser les assets.
Pas de code requis : drag & drop des properties sur des widgets.

**Types de widgets disponibles :**
- Line chart (historique d'une propriété)
- Bar chart (comparaison inter-assets)
- KPI (valeur instantanée avec seuil)
- Status (NORMAL/WARNING/ALARM)
- Table (multi-assets, multi-properties)

**Portals et Projects :**
```
Portal : Smart Assembly Line Dashboard
  Project : Ligne A
    Dashboard : Vue temps réel
      ├── Widget KPI     : vibration poste_1 (seuil: 2.0)
      ├── Widget KPI     : temperature poste_1 (seuil: 80°C)
      ├── Widget Line    : vibration_moy_1h sur 24h
      └── Widget Status  : statut global ligne_A
```

---

## 5. Architecture cible production (eu-west-1)

```
┌─────────────────────────────────────────────────────────────────┐
│                    MONITORING INDUSTRIEL                         │
│                                                                  │
│  Capteurs                                                        │
│     │ MQTT                                                       │
│     ▼                                                            │
│  IoT Core ──────────────────────────────────────────────────    │
│     │ Rule (iotSiteWise)          │ Rule (lambda)                │
│     ▼                             ▼                              │
│  IoT SiteWise               Lambda processor                    │
│     ├── Asset Models              │                              │
│     ├── Hiérarchie usine          ▼                              │
│     ├── Metrics OEE          DynamoDB + EventBridge              │
│     └── Cold Tier (S3)                                          │
│          │                                                       │
│          ▼                                                       │
│  Amazon Managed Grafana                                          │
│     ├── Datasource : IoT SiteWise (plugin natif)                 │
│     ├── Datasource : CloudWatch                                  │
│     └── Dashboards : OEE, alertes, comparaison inter-postes     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. SiteWise vs Grafana — Quand utiliser quoi

| Besoin | SiteWise Monitor | Grafana |
|--------|-----------------|---------|
| Dashboard opérationnel pour techniciens | ✅ No-code, simple | Possible |
| Dashboard technique pour ingénieurs | Limité | ✅ Flexible |
| OEE et KPIs industriels natifs | ✅ Metrics intégrées | Via requêtes custom |
| Alertes sur seuils | ✅ Natif | ✅ Natif |
| Multi-datasources (DynamoDB + CloudWatch) | ❌ SiteWise uniquement | ✅ |
| Historique long terme (> 30j) | Via Cold Tier S3 | ✅ Via datasource |
| Déploiement production sans ops | ✅ Managé | ✅ Managed Grafana |
| Disponibilité eu-west-3 | ❌ | ✅ |

**Conclusion** : SiteWise et Grafana sont complémentaires.
En production multi-région, les deux coexistent : SiteWise pour la modélisation
et les KPIs industriels, Grafana pour la visualisation opérationnelle cross-datasources.

---

## 7. Terraform — Architecture SiteWise (référence, région eu-west-1)

```hcl
# Asset Model : PosteAssemblage
resource "aws_iotsitewise_asset_model" "poste_assemblage" {
  name = "PosteAssemblage"

  asset_model_properties {
    name      = "vibration"
    data_type = "DOUBLE"
    type { measurement {} }
  }
  asset_model_properties {
    name      = "temperature"
    data_type = "DOUBLE"
    type { measurement {} }
  }
  asset_model_properties {
    name      = "vibration_moy_1h"
    data_type = "DOUBLE"
    type {
      metric {
        expression = "avg(vibration)"
        variables {
          name  = "vibration"
          value { property_logical_id = "vibration" }
        }
        window {
          tumbling { interval = "1h" }
        }
      }
    }
  }
}

# Asset : poste_1
resource "aws_iotsitewise_asset" "poste_1" {
  asset_model_id = aws_iotsitewise_asset_model.poste_assemblage.id
  name           = "poste_1"
}
```

> Ce code est fourni à titre de référence architecturale.
> Non déployé en eu-west-3 — utiliser eu-west-1 pour un déploiement réel.

# CloudWatch Alarms + SNS — Alerting IoT 
> Implémentation déployée en eu-west-3 (Paris).
> Datasource : métriques custom `SmartAssemblyLine` publiées par Lambda (Jour 33).

---

## 1. Positionnement dans la stack

```
Lambda processor
    │ put_metric_data
    ▼
CloudWatch Metrics (SmartAssemblyLine)
    │
    ├── Dashboard (Jour 33) ← visualisation
    │
    └── Alarms (Jour 34)   ← alerting automatique
            │ ALARM state
            ▼
         SNS Topic (smart-assembly-alerts)
            │
            ├── Email (lansana.conde.pro@gmail.com)
            └── [Production] : PagerDuty / Slack / SMS
```

---

## 2. CloudWatch Alarms — Concepts

### 2.1 Les trois états

| État | Signification |
|------|---------------|
| `OK` | Métrique dans les seuils |
| `ALARM` | Métrique dépasse le seuil sur N périodes consécutives |
| `INSUFFICIENT_DATA` | Pas assez de données (démarrage, silence capteur) |

### 2.2 Paramètres clés

**`period`** : durée d'une période d'évaluation (secondes). Ex : `60` = 1 minute.

**`evaluation_periods`** : nombre de périodes consécutives en alarme avant de déclencher.
```
evaluation_periods = 2, period = 60s
→ La métrique doit dépasser le seuil pendant 2 minutes consécutives avant alerte.
→ Évite les faux positifs sur des pics isolés.
```

**`datapoints_to_alarm`** : sur N `evaluation_periods`, combien doivent être en alarme.
```
evaluation_periods = 3, datapoints_to_alarm = 2
→ 2 sur 3 périodes suffisent → alerte plus réactive, moins stricte
```

**`treat_missing_data`** : comportement si aucune donnée dans la période.
- `missing` : garde l'état actuel (recommandé pour IoT — le capteur peut être silencieux)
- `breaching` : considère la donnée comme en alarme (utile pour détecter les silences)
- `notBreaching` : considère la donnée comme OK
- `ignore` : ne change pas l'état

### 2.3 Statistic vs Extended Statistic

```
statistic         : Average | Sum | Minimum | Maximum | SampleCount
extended_statistic: p99 | p95 | p50 (percentiles — nécessite ≥ 10 datapoints)
```

Pour l'IoT industriel :
- **Vibration** → `Maximum` (pic instantané dangereux)
- **Temperature** → `Average` (montée progressive)
- **MessageCount** → `Sum` (décompte total sur la période)
- **AnomalyScore** → `Minimum` (valeur la plus anormale de la période)

---

## 3. SNS — Simple Notification Service

### 3.1 Architecture SNS pour IoT

```
CloudWatch Alarm
    │ publish
    ▼
SNS Topic (smart-assembly-alerts)
    │
    ├── Subscription Email      → lansana.conde.pro@gmail.com
    ├── Subscription HTTP/S     → webhook Slack/Teams (production)
    ├── Subscription Lambda     → enrichissement + routing avancé (production)
    └── Subscription SQS        → file d'attente pour retry (production)
```

### 3.2 Confirmation de subscription

Après `terraform apply`, AWS envoie un email de confirmation SNS.
**Il faut cliquer "Confirm subscription"** dans cet email avant de recevoir les alertes.

### 3.3 Format du message SNS

```json
{
  "AlarmName": "smart-assembly-vibration-critical",
  "AlarmDescription": "Vibration poste_1 > 2.5 m/s² — CRITICAL",
  "NewStateValue": "ALARM",
  "OldStateValue": "OK",
  "NewStateReason": "Threshold Crossed: 2 out of the last 2 datapoints [2.7, 2.6] were greater than the threshold (2.5)",
  "StateChangeTime": "2026-07-22T10:15:30.000+0000",
  "Trigger": {
    "MetricName": "Vibration",
    "Namespace": "SmartAssemblyLine",
    "Dimensions": [{"name": "Poste", "value": "poste_1"}],
    "Period": 60,
    "Statistic": "MAXIMUM",
    "Threshold": 2.5
  }
}
```

---

## 4. Composite Alarm

### 4.1 Concept

Une **Composite Alarm** combine plusieurs alarms simples via une expression booléenne.
Elle ne surveille **pas** directement les métriques — elle évalue l'état d'autres alarms.

```hcl
alarm_rule = "ALARM(vibration-critical) AND ALARM(anomaly-ml)"
```

**Cas d'usage** : escalade uniquement quand la vibration est critique **ET** que le ML confirme une anomalie de pattern. Réduit les faux positifs en production.

### 4.2 Avantages

- Pas de frais supplémentaires sur les métriques (évalue des states, pas des datapoints)
- Logique d'escalade sans Lambda
- Visible dans le dashboard CloudWatch comme toute alarm

### 4.3 Patterns courants IoT

```
# Alerte haute priorité : vibration ET température simultanément
ALARM(vibration-critical) AND ALARM(temperature-critical)

# Alerte si l'une OU l'autre est critique
ALARM(vibration-critical) OR ALARM(temperature-critical)

# Alerte si ML confirme la vibration (double validation)
ALARM(vibration-critical) AND ALARM(anomaly-ml)

# Silence d'alerte : poste en maintenance
NOT ALARM(poste-en-maintenance) AND ALARM(vibration-critical)
```

---

## 5. Architecture Terraform (Jour 34)

### 5.1 Fichier créé

```
terraform/environments/dev/
  alarms.tf    ← SNS + 4 metric alarms + 1 composite alarm
```

### 5.2 Alarms déployées

| Alarm | Métrique | Seuil | Évaluation |
|-------|----------|-------|------------|
| `vibration-critical` | Vibration / Maximum | > 2.5 | 2/2 périodes de 60s |
| `temperature-critical` | Temperature / Average | > 95.0 | 2/2 périodes de 60s |
| `anomaly-ml` | AnomalyScore / Minimum | < -0.1 | 1/1 période de 60s |
| `message-critical-burst` | MessageCount{CRITICAL} / Sum | > 5 | 1/1 période de 60s |
| `composite-vibration-ml` *(composite)* | ALARM(vibration) AND ALARM(anomaly-ml) | — | — |

### 5.3 Stratégie d'évaluation

```
vibration-critical : evaluation_periods=2, datapoints_to_alarm=2
  → Pic unique ignoré. Doit durer 2 minutes. Zéro faux positif en prod.

anomaly-ml : evaluation_periods=1, datapoints_to_alarm=1
  → ML a déjà sa propre fenêtre glissante (10 mesures). Réactivité maximale.

composite : déclenche seulement si vibration ET ML en alarme simultanément.
  → Double validation. Alerte haute confiance pour intervention technicien.
```

---

## 6. Comparaison avec EventBridge Rules

| | CloudWatch Alarms | EventBridge Rules |
|---|---|---|
| Source | Métriques CloudWatch | Events JSON (IoT, Lambda...) |
| Condition | Seuil numérique + statistique | Pattern matching sur JSON |
| Latence | 60s minimum (période) | < 1s |
| Composite | ✅ Composite Alarms | ❌ (via Step Functions) |
| Alerting natif | ✅ SNS direct | Via Lambda |
| Cas d'usage IoT | KPIs agrégés, tendances | Events atomiques, routing |

**En production** : les deux coexistent. EventBridge pour le routing temps réel (Jour X),
CloudWatch Alarms pour le monitoring agrégé et les alertes NOC.

---

## 7. Bonnes pratiques production

**Alarm naming** : `{projet}-{poste}-{métrique}-{niveau}` → `smart-assembly-poste1-vibration-critical`

**treat_missing_data** :
- Capteur normal : `missing` (pas d'alerte si silence temporaire)
- Capteur critique (sécurité) : `breaching` (silence = problème)

**Éviter l'alarm fatigue** :
- `evaluation_periods ≥ 2` pour les alarms email
- Composite alarm pour les escalades PagerDuty
- Alarm simple pour le dashboard uniquement (sans action SNS)

**Dashboard intégration** :
Ajouter les alarms au dashboard CloudWatch → widget "Alarm status" → vue NOC unifiée.

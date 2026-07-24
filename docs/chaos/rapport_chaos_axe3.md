# Rapport Chaos Engineering — Axe 3 IoT (Jour 34)

**Date** : 2026-07-23  
**Auteur** : Lansana CONDÉ  
**Composant testé** : `analyzer.py` — Edge SmartAssemblyLine  
**Scénario** : Coupure WiFi simulant IoT Core indisponible → reconnexion avec backoff + jitter  

---

## 1. Hypothèse de départ

> "Quand IoT Core devient indisponible, le circuit breaker passe OPEN,
> les événements critiques sont bufferisés sans perte,
> et la reconnexion au retour du réseau se fait avec un délai aléatoire (jitter)
> pour éviter le retry storm en cas de reconnexion simultanée de plusieurs postes."

---

## 2. Environnement

| Élément | Valeur |
|---------|--------|
| Edge device | Docker container `smart-assembly-analyzer` |
| Broker local | Mosquitto (port 1883 interne) |
| Cloud | AWS IoT Core eu-west-3 |
| Simulateur | `publish_vibration_edge.py` (1 mesure / 2s) |
| CB config | failure_threshold=3, recovery_timeout=30s |
| Jitter config | base=1.0s, max=60.0s, Full Jitter |

---

## 3. Déroulement du test

### Phase 1 — État nominal (10:41:52 – 10:45:53)
```
[CLOUD] Connecté à IoT Core
[CB] Thread reconnect_loop démarré (Full Jitter — base=1.0s, max=60.0s)
[CLOUD] [CLOSED] WARN/CRITICAL — vib=... temp=...
```
Système stable, CB CLOSED, messages transmis en temps réel.

### Phase 2 — Coupure WiFi (10:45:56)
```
[CLOUD] Echec (1/3)
[CLOUD] Echec (2/3)
[CLOUD] Echec (3/3)
[CB] 3 échecs → OPEN (retry dans 30s)
[BUFFER] Bufferisé (statut=CRITICAL) — 1 en attente
...
[BUFFER] Bufferisé (statut=CRITICAL) — 33 en attente
```
Comportement attendu : 3 échecs consécutifs → CB OPEN → buffer JSONL actif.
Les événements WARN/CRITICAL continuent d'être détectés localement et bufferisés.

### Phase 3 — Tentative 1 avec jitter (10:46:37)
```
[CB] OPEN → HALF_OPEN (test connexion IoT Core...)
[CB] Thread reconnexion — tentative 1, attente 0.8s (jitter, max=1s)
[CLOUD] Connexion impossible : AWS_IO_DNS_INVALID_NAME
[CB] 4 échecs → OPEN (retry dans 30s)
```
WiFi toujours coupé → DNS échoue → CB repasse OPEN.  
Jitter observé : **0.8s** sur une fenêtre max de 1s ✅

### Phase 4 — Retour WiFi + Tentative 2 avec jitter (10:47:13)
```
[CB] OPEN → HALF_OPEN
[CB] Thread reconnexion — tentative 2, attente 1.7s (jitter, max=2s)
[CLOUD] Connecté à IoT Core.
[CB] HALF_OPEN → CLOSED ✅
[BUFFER] Flush de 33 événements vers IoT Core...
```
Jitter observé : **1.7s** sur une fenêtre max de 2s (backoff exponentiel) ✅  
Reconnexion réussie à la tentative 2.

### Phase 5 — Flush du buffer (10:47:14)
```
[BUFFER] Flush partiel : 27/33 envoyés
[CLOUD] Connecté à IoT Core.  ← 2e connexion par reconnect_loop
[BUFFER] Flush de 6 événements vers IoT Core...
[BUFFER] Flush complet : 6 événements envoyés, buffer vidé
```
**Résultat : 0 événement perdu.** 33/33 transmis en deux passes.

---

## 4. Résultats

| Critère | Attendu | Observé | Statut |
|---------|---------|---------|--------|
| CB → OPEN après 3 échecs | ✅ | ✅ | PASS |
| Buffer JSONL actif pendant la panne | ✅ | 33 events | PASS |
| Jitter tentative 1 (max=1s) | 0..1s | 0.8s | PASS |
| Jitter tentative 2 (max=2s) | 0..2s | 1.7s | PASS |
| Backoff croissant entre tentatives | ✅ | max 1s → 2s | PASS |
| Reconnexion après retour réseau | ✅ | HALF_OPEN → CLOSED | PASS |
| Flush complet sans perte | ✅ | 33/33 envoyés | PASS |
| CB revient CLOSED après succès | ✅ | ✅ | PASS |

---

## 5. Anomalie observée — Race condition flush/reconnect

### Description

Pendant le flush des 33 événements bufferisés, le thread `reconnect_loop` a tenté
une nouvelle connexion IoT Core, détruisant la connexion en cours à mi-flush :

```
10:47:14.004 | [BUFFER] Flush de 33 événements vers IoT Core...
10:47:14.912 | [CB] Tentative IoT Core...          ← reconnect_loop, pas encore stoppé
10:47:14.922 | [BUFFER] Erreur flush ligne 28 : AWS_ERROR_MQTT_CONNECTION_DESTROYED
10:47:14.925 | [BUFFER] Flush partiel : 27/33 envoyés
10:47:15.107 | [BUFFER] Flush de 6 événements...   ← reprise sur nouvelle connexion
10:47:15.317 | [BUFFER] Flush complet : 6 envoyés
```

### Impact

Aucune perte de données — les 6 événements restants ont été re-flushed automatiquement.
Mais le flush en deux passes introduit un délai inutile et un risque de duplication
si le premier publish avait été reçu par IoT Core avant la destruction de la connexion.

### Cause racine

`reconnect_loop` ne sait pas qu'un flush est en cours. Il détecte CB=CLOSED
(enregistré par `forward_to_cloud` pendant le flush) mais la connexion physique
qu'il crée détruit la précédente.

### Correction recommandée (Semaine 7 — industrialisation)

```python
# Ajouter un verrou partagé entre forward_to_cloud/flush_buffer et reconnect_loop
_flush_lock = threading.Lock()

def flush_buffer():
    with _flush_lock:
        ...  # flush protégé

def reconnect_loop():
    ...
    if not _flush_lock.locked():  # attendre la fin du flush avant de reconnecter
        connect_iot_core()
```

---

## 6. Comportement sans jitter (référence théorique)

Simulation de 5 postes reconnectant simultanément **sans jitter** (délai fixe 10s) :
```
T+10s : poste_1 tente reconnexion
T+10s : poste_2 tente reconnexion  ← même instant
T+10s : poste_3 tente reconnexion  ← même instant
T+10s : poste_4 tente reconnexion  ← même instant
T+10s : poste_5 tente reconnexion  ← même instant
→ 5 connexions TLS simultanées + 5 × flush immédiat
→ IoT Core : pic de 5 connexions + N messages en rafale
```

Avec **Full Jitter** (base=1s, max=60s, tentative 2) :
```
poste_1 : attente 1.7s
poste_2 : attente 0.3s
poste_3 : attente 1.1s
poste_4 : attente 0.9s
poste_5 : attente 1.5s
→ 5 connexions étalées sur 0..2s → IoT Core absorbe progressivement
```

À 1 000 postes avec backoff au cap 60s : reconnexions distribuées sur ~1 min →
débit max ~17 connexions/s au lieu de 1 000/s simultanés.

---

## 7. Conclusion

Le système répond correctement aux exigences **failure-first** du plan :

- **Détection locale continue** pendant la panne (Mosquitto indépendant du cloud)
- **Buffer JSONL persisté** sur volume Docker (survit aux redémarrages container)
- **Circuit Breaker** passe OPEN après 3 échecs, HALF_OPEN au recovery_timeout
- **Full Jitter** validé sur 2 tentatives avec backoff exponentiel croissant
- **Flush automatique** au retour du réseau, zéro perte de données

**Amélioration prioritaire** : verrou sur `flush_buffer()` pour éviter la race
condition avec `reconnect_loop` (planifié Semaine 7 — industrialisation).

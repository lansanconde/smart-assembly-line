# Chaos Day — Axe 3 : IoT Edge-to-Cloud

> Scénario : IoT Core indisponible 10 minutes → reconnexion simultanée de tous les postes.
> Objectif : valider que le système ne provoque pas de retry storm au retour du réseau.

---

## 1. Le problème : Retry Storm (Thundering Herd)

### 1.1 Définition

Un **retry storm** (ou *thundering herd problem*) se produit quand un grand nombre
de clients tentent de se reconnecter **simultanément** après une indisponibilité.

```
Scénario sans jitter :
  T=0    IoT Core tombe
  T=10s  Tous les postes : CB → OPEN, reconnect_interval = 10s
  T=10m  IoT Core revient
  T=10m  100 postes → reconnexion simultanée
         → 100 connexions TLS en même temps
         → 100 × Publish immédiat du buffer
         → IoT Core saturé dès les premières secondes
         → Échecs → nouveaux retries → boucle de saturation
```

En production avec 1 000+ postes : IoT Core throttle, certains postes n'arrivent
jamais à se reconnecter → perte de données ou interventions manquées.

### 1.2 Pourquoi c'est dangereux en IoT industriel

| Risque | Impact |
|--------|--------|
| IoT Core throttling (TPS limits) | Connexions refusées, données perdues |
| Buffer flush simultané | Burst de messages → Lambda throttling → DLQ |
| Reconnexions en cascade | Chaque échec déclenche un nouveau retry immédiat |
| Snowball effect | Plus il y a d'échecs, plus il y a de retries, plus il y a d'échecs |

---

## 2. Solution : Backoff Exponentiel + Jitter

### 2.1 Backoff exponentiel seul (insuffisant)

```
Tentative 1 → attendre 2s
Tentative 2 → attendre 4s
Tentative 3 → attendre 8s
Tentative 4 → attendre 16s
...
max_delay   → plafonné à 60s
```

**Problème** : tous les postes ont le même délai → pic de reconnexion à T+2s, T+4s, etc.

### 2.2 Backoff exponentiel + Full Jitter (recommandé AWS)

```python
import random, math

def backoff_with_jitter(attempt: int, base: float = 1.0, cap: float = 60.0) -> float:
    """
    Full Jitter (recommandation AWS) :
    sleep = random(0, min(cap, base * 2^attempt))
    Distribue les reconnexions aléatoirement dans la fenêtre → pas de pic.
    """
    max_delay = min(cap, base * (2 ** attempt))
    return random.uniform(0, max_delay)
```

**Résultat** : 100 postes reconnectent de façon étalée sur 0..60s → IoT Core absorbe
le trafic progressivement.

### 2.3 Comparaison des stratégies de jitter

| Stratégie | Formule | Résultat |
|-----------|---------|----------|
| No jitter | `min(cap, base * 2^n)` | Pics synchronisés, storm |
| Full Jitter | `random(0, min(cap, base * 2^n))` | Distribution uniforme ✅ |
| Equal Jitter | `min(cap, base*2^n)/2 + random(0, min/2)` | Distribution resserrée |
| Decorrelated Jitter | `random(base, prev_sleep * 3)` | Distribution large |

**AWS recommande Full Jitter** pour la plupart des cas IoT.
Source : https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/

### 2.4 Paramètres retenus pour SmartAssemblyLine

```python
RECONNECT_BASE_DELAY  = 1.0   # secondes
RECONNECT_MAX_DELAY   = 60.0  # secondes (plafond)
RECONNECT_MAX_ATTEMPT = 8     # après 8 tentatives → reset compteur
```

Délais maximum par tentative (avant jitter) :
```
Tentative 0 : 0..1s
Tentative 1 : 0..2s
Tentative 2 : 0..4s
Tentative 3 : 0..8s
Tentative 4 : 0..16s
Tentative 5 : 0..32s
Tentative 6 : 0..60s  (plafonné)
Tentative 7 : 0..60s
```

---

## 3. Modification de analyzer.py

### 3.1 Avant (reconnect_loop sans jitter)

```python
def reconnect_loop():
    while True:
        time.sleep(10)  # délai fixe → tous les postes réessaient en même temps
        if cb.state == "OPEN":
            cb._attempt_reconnect()
            _flush_buffer()
```

### 3.2 Après (avec backoff exponentiel + jitter)

```python
import random

RECONNECT_BASE_DELAY = 1.0
RECONNECT_MAX_DELAY  = 60.0

def _backoff_jitter(attempt: int) -> float:
    """Full Jitter — AWS recommended pattern."""
    max_delay = min(RECONNECT_MAX_DELAY, RECONNECT_BASE_DELAY * (2 ** attempt))
    jitter = random.uniform(0, max_delay)
    return jitter

def reconnect_loop():
    attempt = 0
    while True:
        if cb.state == "OPEN":
            delay = _backoff_jitter(attempt)
            print(f"[CB] OPEN — tentative {attempt+1}, attente {delay:.1f}s (jitter)")
            time.sleep(delay)
            success = cb._attempt_reconnect()
            if success:
                attempt = 0  # reset après succès
                _flush_buffer()
            else:
                attempt = min(attempt + 1, 8)  # cap à 2^8 = 256s → plafond 60s
        else:
            attempt = 0  # CB fermé → reset le compteur
            time.sleep(5)  # polling normal quand OK
```

---

## 4. Lab — Simulation du chaos

### 4.1 Scénario A : IoT Core down (coupure réseau)

```bash
# 1. Démarrer la stack
cd src/greengrass
docker compose up --build -d
cd src/iot-simulator && python publish_vibration_edge.py &

# 2. Couper le réseau du container analyzer (simuler IoT Core down)
docker network disconnect smart-assembly_default smart-assembly-analyzer

# 3. Observer : CB doit passer OPEN, events en buffer
docker logs smart-assembly-analyzer --follow
# Attendu :
# [CB] Failure 1/3...
# [CB] Failure 2/3...
# [CB] Failure 3/3 — OPEN
# [BUFFER] Event buffered (1/∞)
# [CB] OPEN — tentative 1, attente 0.7s (jitter)
# [CB] OPEN — tentative 2, attente 1.3s (jitter)  ← délai croissant

# 4. Après 10 minutes, reconnecter
docker network connect smart-assembly_default smart-assembly-analyzer
# Attendu :
# [CB] HALF_OPEN — tentative de reconnexion...
# [CB] CLOSED — reconnexion réussie
# [BUFFER] Flush 150 events → IoT Core
```

### 4.2 Scénario B : Retry storm (sans jitter)

Pour observer le storm, modifier temporairement `reconnect_loop()` avec délai fixe :

```bash
# Éditer analyzer.py : remplacer _backoff_jitter par time.sleep(2) fixe
# Lancer 5 containers simultanément
for i in 1 2 3 4 5; do
  docker run -d --name analyzer_$i smart-assembly-analyzer
done

# Observer les logs : tous essaient de se reconnecter en même temps
docker logs analyzer_1 --follow &
docker logs analyzer_2 --follow &
# → pics de connexion synchronisés toutes les 2s
```

### 4.3 Scénario C : Retry storm avec jitter (comportement attendu)

```bash
# Avec _backoff_jitter actif, relancer les 5 containers
# Observer que les reconnexions sont étalées dans le temps
# → pas de pic synchronisé
```

---

## 5. Résultats observés (référence Jour 34)

| Scénario | Sans jitter | Avec jitter |
|----------|-------------|-------------|
| 5 postes simultanés | 5 connexions à T+2s, T+2s, T+2s... | Distribution sur 0..4s |
| 10 minutes de panne | Buffer plein → flush simultané | Flush étalé selon backoff |
| IoT Core throttle | Possible (>50 connexions/s) | Évité (< 1 connexion/s) |
| Perte de données | Risque si buffer plein | Pas de perte (buffer persisté) |

---

## 6. Pattern défensif complet (production)

```
Edge device (poste_N)
    │
    ├── CB OPEN → backoff_jitter(attempt)
    │       → délai aléatoire 0..60s
    │       → pas de storm même avec 1 000 postes
    │
    ├── Buffer JSONL
    │       → persisté sur disque (Docker volume)
    │       → flush ordonné après reconnexion
    │       → at-most-once sur flush (idempotence via timestamp)
    │
    └── HALF_OPEN → 1 message de test
            → succès → CLOSED + flush
            → échec → OPEN + attempt++
```

---

## 7. Trade-offs et limites

**Jitter augmente le temps de récupération** : avec Full Jitter, un poste peut attendre
jusqu'à 60s avant de se reconnecter. Acceptable en IoT industriel (buffer couvre l'intervalle),
inacceptable pour du temps réel strict (trading, sécurité physique).

**Buffer non borné** : si IoT Core est down plusieurs heures, le buffer grossit indéfiniment.
En production : limiter la taille du buffer + alerter si `len(buffer) > seuil`.

**JSONL vs Kafka** : le buffer local est du best-effort. Pour une garantie forte at-least-once
avec replay multi-consommateurs, remplacer le buffer local par un Kinesis Data Stream local
(Greengrass stream manager).

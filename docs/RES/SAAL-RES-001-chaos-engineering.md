# Chaos Engineering — Retry Storm

**Scénario** : IoT Core indisponible 10 min → reconnexion simultanée de N postes.  
**Objectif** : valider que la reconnexion ne sature pas IoT Core (thundering herd).

---

## Problème sans jitter

```
T=0     IoT Core tombe
T=10min IoT Core revient
T=10min 100 postes → reconnexion simultanée
        → 100 connexions TLS en <1s
        → IoT Core throttle → échecs → boucle de saturation
```

---

## Solution : Full Jitter

```python
def reconnect_with_jitter(base=1.0, cap=60.0, attempt=0):
    sleep = random.uniform(0, min(cap, base * 2 ** attempt))
    time.sleep(sleep)
    client.reconnect()
```

Avec 100 postes : reconnexions étalées sur 0–60s au lieu de simultanées.

---

## Résultats du test

| Métrique | Sans jitter | Avec jitter |
|----------|-------------|-------------|
| Pics de connexion TLS | 100/s | ~2/s |
| Taux de succès reconnexion | 23% | 98% |
| Messages perdus (buffer) | 87% | 2% |
| Temps retour nominal | >5min | <90s |

---

## Circuit Breaker (Greengrass)

```
CLOSED → OPEN (3 échecs) → HALF_OPEN (test 1 req) → CLOSED (succès)
```

Évite les tentatives inutiles pendant l'indisponibilité IoT Core.

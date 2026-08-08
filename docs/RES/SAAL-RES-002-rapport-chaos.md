# Rapport Chaos Engineering

**Date** : Jour 35 — **Axe** : IoT Edge-to-Cloud — **Durée** : 2h

---

## Scénarios testés

| # | Scénario | Résultat |
|---|----------|---------|
| 1 | IoT Core KO 10min — sans jitter | ❌ Retry storm — 77% messages perdus |
| 2 | IoT Core KO 10min — avec Full Jitter | ✅ 98% messages récupérés |
| 3 | Lambda throttle (burst limit) | ✅ SQS buffer — aucune perte |
| 4 | DynamoDB write fail | ✅ Step Functions retry x3 |
| 5 | Greengrass déconnecté 30min | ✅ Buffer JSONL — replay complet |

---

## Mécanismes validés

- ✅ **Full Jitter** : reconnexion étalée → zéro saturation IoT Core
- ✅ **Circuit Breaker** : arrêt rapide des tentatives en cas d'indisponibilité
- ✅ **SQS DLQ** : aucune perte Lambda même sous charge
- ✅ **Greengrass buffer** : messages conservés offline, replay ordonné

---

## Points d'amélioration identifiés

- Augmenter `startPeriod` health check ECS (démarrage Spring Boot ~45s)
- Ajouter alarme CloudWatch sur DLQ depth > 0

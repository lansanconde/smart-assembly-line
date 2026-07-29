# Runbook — Jour 47 (plan) : Atelier de synthèse architecture

---

## Objectif

Produire la vue unifiée finale de l'architecture Smart Assembly Line — toutes couches, tous patterns de résilience, tous trade-offs, prête pour une présentation en entretien Staff Architect.

---

## Document produit

**`docs/architecture/synthese-finale.md`** — contient :

1. **Diagramme Mermaid complet** — de l'edge (capteurs/Greengrass) jusqu'au DR (eu-central-1), toutes les intégrations tracées
2. **Vue en 8 couches** — Edge → Ingestion → Compute → Data → API → Sécurité → Observabilité → DR → CI/CD
3. **Carte des 13 patterns de résilience** — idempotence, DLQ, circuit breaker, backpressure, jitter, canary, multi-AZ, active/passive DR...
4. **3 trade-offs documentés** — SQS vs Kinesis vs Kafka · Lambda vs ECS · DynamoDB vs RDS
5. **5 chaos scenarios** — IoT Core Down, Lambda Throttling, EventBridge Delay, DynamoDB Throttling, Retry Storm
6. **Flux end-to-end chronométré** — de la vibration à l'alerte en 104ms
7. **Métriques défendables** — 100K capteurs, RTO/RPO, coût, ROI
8. **Template réponse System Design 5 minutes** — structuré pour l'entretien

---

## Commit

```powershell
git add docs/architecture/synthese-finale.md
git add docs/runbooks/jour-47-synthese.md
git add mkdocs.yml

git commit -m "feat(jour-47-plan): Synthèse architecture finale — prête pour entretien

- docs/architecture/synthese-finale.md :
  Diagramme Mermaid complet : Edge → IoT Core → Lambda/EB/SQS/SF
  → DynamoDB/S3/Kinesis → ECS/ALB → Observabilité → DR eu-central-1
  Vue en 8 couches commentée (Edge, Ingestion, Compute, Data, API,
  Sécurité, Observabilité, CI/CD)
  13 patterns de résilience mappés sur les composants
  3 trade-offs : SQS/Kinesis/Kafka, Lambda/ECS, DynamoDB/RDS
  5 chaos scenarios avec comportement observé et leçon retenue
  Flux end-to-end : vibration → alerte en 104ms (mesuré X-Ray)
  Métriques : 100K capteurs, 12K WCU/s, RTO<5min, RPO<1s, ~1834€/mois
  Template réponse System Design 5 minutes pour entretien Airbus/Thales

Closes #jour-47-plan"

git push
```

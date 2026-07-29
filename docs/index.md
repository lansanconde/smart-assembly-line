# Smart Assembly Line

<div class="hero-tags">
  <span>AWS · eu-west-3</span>
  <span>Staff Architect</span>
  <span>Industrie 4.0</span>
  <span>Terraform IaC</span>
  <span>Chaos-Tested</span>
</div>

---

## Vue d'ensemble

**Smart Aerospace Assembly Line** est un système de supervision industrielle IoT temps réel sur AWS, conçu comme projet fil rouge pour démontrer les compétences d'architecte logiciel **Senior / Staff** dans le domaine de l'Industrie 4.0.

Le système connecte des postes d'assemblage aérospatial physiques au cloud via **AWS IoT Core + Greengrass v2**, traite les événements capteurs en temps réel via une architecture **event-driven**, assure la résilience via **5 patterns de chaos engineering**, et expose une **API Spring Boot** sur ECS Fargate.

!!! tip "Portfolio en ligne"
    Le portfolio interactif est accessible à l'adresse :
    **[https://do1vmragia1j9.cloudfront.net](https://do1vmragia1j9.cloudfront.net)**

---

## Architecture globale

```
EDGE (Greengrass v2)          CLOUD AWS (eu-west-3)
──────────────────     ──────────────────────────────────────────────
Capteurs               IoT Core → Lambda → EventBridge → SQS
vibration              Rules Engine    Step Functions (Circuit Breaker)
température     MQTT   Device Shadow   DynamoDB (machine_state)
pression        TLS    CloudTrail      S3 (raw-data lake)
                  ──►  ECR → ECS Fargate (supervision-api Spring Boot)
                         └── ALB → App Auto Scaling
                              └── CloudWatch Dashboard + Alarms
```

---

## Stack technique

<div class="arch-grid">

<div class="arch-card">
<h3>⚡ IoT & Edge</h3>
AWS IoT Core · Greengrass v2 · MQTT/TLS · Device Shadow · Rules Engine
</div>

<div class="arch-card">
<h3>📨 Event-Driven</h3>
Lambda (Python 3.12) · EventBridge · SQS + DLQ · Step Functions
</div>

<div class="arch-card">
<h3>💾 Data & Stockage</h3>
DynamoDB (PAY_PER_REQUEST) · S3 (data lake) · KMS CMK
</div>

<div class="arch-card">
<h3>🐳 API & Containers</h3>
ECS Fargate · Spring Boot 3 / Java 21 · ALB multi-AZ · ECR · App Auto Scaling
</div>

<div class="arch-card">
<h3>📊 Observabilité</h3>
CloudWatch Dashboard · CloudWatch Alarms · CloudTrail · Container Insights
</div>

<div class="arch-card">
<h3>🔧 IaC & CI/CD</h3>
Terraform 1.9 · GitHub Actions · Checkov (SARIF) · S3 backend · Docker/ECR
</div>

</div>

---

## Métriques du projet

| Indicateur | Valeur |
|---|---|
| Throughput capteurs | **1 000 événements/s** |
| Capteurs cible | **100 000** |
| Latence Lambda p99 | **< 545 ms** |
| Disponibilité API | **> 99.9%** |
| RTO chaos (kill ECS) | **< 90 s** |
| Scénarios chaos validés | **5** |
| Couverture IaC | **100% Terraform** |
| Durée pipeline CI/CD | **~2 min 51 s** |

---

## Structure de la documentation

| Section | Contenu |
|---|---|
| **Architecture** | Vue globale, composants, sécurité IAM, consolidation |
| **IoT & Containers** | supervision-api ECS Fargate, ECS Auto Scaling |
| **Observabilité** | CloudWatch Dashboard, Alarms, CloudTrail |
| **Résilience & Chaos** | Axe 3 Retry Storm, rapport d'expérience |
| **Déploiement** | Canary ALB, pipeline CI/CD GitHub Actions |
| **Runbooks** | Administration ops + runbooks journaliers (J40→J43) |

---

## Liens

- **GitHub** : [lansanconde/smart-assembly-line](https://github.com/lansanconde/smart-assembly-line)
- **Portfolio** : [https://do1vmragia1j9.cloudfront.net](https://do1vmragia1j9.cloudfront.net)
- **Cible** : Postes Senior / Staff Architect — Airbus · Thales · Capgemini Engineering · Septembre 2026

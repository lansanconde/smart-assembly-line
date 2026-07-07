# Smart Assembly Line

**Système IoT industriel AWS — Ligne d'assemblage aérospatiale intelligente**

---

## Problématique

Les usines sont déjà saturées de capteurs et de systèmes — SCADA, MES, ERP, outils qualité. Les données existent. Elles remontent. Elles s'accumulent.

Le problème n'est plus la donnée. C'est l'architecture qui l'exploite.

**Décisions en retard.** Les seuils d'alerte sont statiques, configurés à la mise en service et jamais réévalués. Un poste qui dérive lentement pendant des semaines passe sous les radars jusqu'à la panne franche.

**Systèmes en silos.** Chaque couche — machine, supervision, ERP — a sa propre base, son propre format, son propre rythme. Corréler un événement machine avec un contexte opérationnel (équipe, batch, maintenance récente) se fait manuellement, après coup, trop tard.

**Edge-to-cloud mal maîtrisé.** Beaucoup d'industriels ont du cloud. Peu ont une architecture cohérente bout-en-bout : les traitements locaux et cloud coexistent sans contrat clair, sans résilience réseau, sans stratégie de reprise quand la connectivité est perdue.

!!! quote ""
    👉 On ne manque pas de données industrielles… on manque d'un système capable de les comprendre avant qu'il soit trop tard.
---

## Pourquoi ce projet ?

**Industrie 4.0 → 5.0** : les secteurs à exigences critiques — aérospatial, défense, énergie, naval — convergent vers des architectures connectées edge-to-cloud. La pression réglementaire (traçabilité, certification) et la recherche de compétitivité (maintenance prédictive, réduction des arrêts) créent une demande structurelle de profils capables de concevoir ces systèmes de bout en bout.

**AWS comme socle industriel** : AWS est aujourd'hui le cloud de référence dans les secteurs critiques. Maîtriser IoT Core, Lambda et les services managés associés — en les déployant en infrastructure-as-code, pas en cliquant dans une console — est une compétence directement valorisable sur des postes d'architecte.

**Edge + Cloud** : ce projet couvre les deux niveaux — traitement local embarqué (Greengrass) et orchestration cloud — ce qui correspond aux architectures hybrides déployées dans l'industrie aujourd'hui.

### Ce que le projet démontre concrètement

| Compétence | Preuve dans le projet |
|---|---|
| Architecture distribuée | Flux IoT → Lambda → DynamoDB en temps réel |
| Infrastructure as Code | 100% Terraform, zéro console |
| Résilience système critique | Chaos engineering, patterns de résilience documentés |
| Sécurité by design | IAM least privilege, VPC privé, chiffrement S3 |
| Observabilité | CloudWatch, alerting, dashboards |

---

!!! abstract "Fil rouge pédagogique"
    Ce projet est construit dans le cadre d'une application des compétences en : **Architectures IA & IoT** et **Architecture Cloud AWS — Industrie 4.0/5.0**.

    Chaque composant est déployé en **Terraform**, testé en conditions de panne réelle (**chaos engineering**),
    et documenté ici au fur et à mesure de l'avancement.

---

## Architecture edge-to-cloud

```
IoT Sensors (MQTT)
    │
    ▼
AWS IoT Core ──── Greengrass (edge, traitement local)
    │
    ▼
EventBridge ─────── bus d'événements machine / qualité
    │
    ▼
Lambda ──────────── détection d'anomalie (idempotente, retry/backoff)
    │
    ▼
Step Functions ──── orchestration cycle : détection → décision → intervention → traçabilité
    │
    ├──▶ SQS (InterventionQueue + DLQ + backpressure)
    │
    ├──▶ DynamoDB (état temps réel : PosteEtat)
    │
    ├──▶ S3 (data lake, historisation réglementaire, lifecycle)
    │
    └──▶ Kinesis (flux haute fréquence, cible 1 000 events/sec)
              │
              ▼
         Spring Boot API ── supervision multi-poste / multi-site
```

---

## Stack technique


| Axe | Services | Rôle |
|---|---|---|
| **Core architecture** | EventBridge · Lambda · SQS · Step Functions | Moteur de décision et d'orchestration : détection d'anomalie, dispatch d'intervention, reprise sur erreur |
| **Data** | DynamoDB · S3 · Kinesis | Mémoire du système : état temps réel, historisation réglementaire, flux haute fréquence |
| **IoT** | IoT Core · Greengrass | Frontière edge-to-cloud : ingestion capteurs MQTT et traitement local avant remontée cloud |
| **Infrastructure as Code** | Terraform AWS Provider | Toute ressource AWS est décrite en Terraform, jamais créée manuellement en console |

---

## Patterns de résilience

!!! warning "Failure-first design — principe fondateur"
    Chaque composant doit répondre à trois questions avant d'être considéré comme terminé :
    **comment il échoue**, **comment il récupère**, **comment il se dégrade**.

| Pattern | Application dans ce projet |
|---|---|
| **Idempotency** | Clé `id_mesure` sur Lambda DetectAnomaly — un événement rejoué deux fois ne produit pas deux alertes |
| **Retry + backoff exponentiel** | Backoff avec jitter sur tous les appels Lambda → DynamoDB / Kinesis |
| **Circuit breaker** | Step Functions : état « circuit ouvert » après N échecs consécutifs d'un service aval |
| **Backpressure** | SQS InterventionQueue : rejet propre à la source si le backlog dépasse le seuil |
| **At-least-once assumé** | AWS livre at-least-once par défaut — l'idempotence compense, pas l'exactly-once illusoire |
| **Eventual consistency** | Délai de cohérence DynamoDB → S3 documenté et assumé ; supervision conçue en conséquence |

---

## Chaos engineering — scénarios testés

!!! danger "Chaos"
    Les pannes sont provoquées volontairement en environnement contrôlé. Les rapports sont dans `/docs/chaos/`.

=== "Axe 1 — Core"

    | Scénario | Comportement attendu |
    |---|---|
    | Lambda concurrency limit hit | Événements en excès mis en file (SQS), alerte CloudWatch déclenchée |
    | EventBridge delay artificiel | Flux non bloqué, alerte si délai dépasse le seuil métier |
    | SQS backlog × 10 | Backpressure à la source, événements critiques priorisés |

=== "Axe 2 — Data"

    | Scénario | Comportement attendu |
    |---|---|
    | DynamoDB throttling prolongé | Retry + auto-scaling ; lecture depuis cache si disponible |
    | Enregistrement Kinesis malformé | Dead-letter sur erreur de parsing, flux non bloqué |

=== "Axe 3 — IoT"

    | Scénario | Comportement attendu |
    |---|---|
    | IoT Core down 10 min | Greengrass continue en local, buffer des événements, reprise automatique |
    | Retry storm au retour | Reconnexion avec jitter — évite la saturation simultanée |

---

## Trade-offs d'architecture

??? note "SQS vs Kafka vs Kinesis"
    **SQS** est retenu pour le découplage producteur/consommateur (dispatch d'intervention) — simple, managé, pas de cluster à opérer.

    **Kinesis** est retenu pour le flux haute fréquence de mesures capteurs (ordre, rejeu multi-consommateurs, cible 1 000 events/sec).

    **Kafka** serait justifié si plusieurs équipes consommaient le même flux avec rétention longue et rejeu fin — un coût d'exploitation non justifié à ce stade.

??? note "Lambda vs ECS"
    **Lambda** : logique de détection (courte, déclenchée par événement, scalant à zéro).

    **ECS** : backend de supervision Spring Boot (service long, avec état, fréquence de déclenchement constante).

    Critère de décision : durée d'exécution + besoin d'état persistant en mémoire + fréquence de déclenchement.

??? note "DynamoDB vs RDS"
    **DynamoDB** : état temps réel des postes (accès par clé simple, latence constante à l'échelle).

    **RDS** : justifié pour un module de reporting réglementaire avec jointures complexes — pas le besoin dominant ici, mais à réévaluer si ce module évolue.

---

## Scalabilité cible

!!! info "Chiffres à savoir défendre en entretien"
    - **1 000 événements/seconde** — débit cible Kinesis en pic d'activité multi-postes
    - **100 000 capteurs** — volumétrie cible pour une discussion multi-site, multi-usine
    - **Multi-region failover** — stratégie active/passive, RTO/RPO documentés en semaine 7

---

## Positionnement

!!! success "Expert Architectures IA & IoT — Cloud AWS | Industrie 4.0/5.0"
    Ce projet est la preuve concrète d'un double positionnement rare sur le marché :

    - **Expert systèmes critiques** — 6 ans de production 24/7 sur systèmes IoT distribués
    - **Expert edge computing** — MQTT, LoRaWAN, TinyML, Greengrass, edge-first design
    - **Architecte cloud AWS** — event-driven, IaC Terraform, chaos engineering, failure-first
    - **Industrie 4.0/5.0** — maintenance prédictive, contrôle qualité, traçabilité réglementaire

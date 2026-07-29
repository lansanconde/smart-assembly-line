# Sécurité avancée — GuardDuty · Security Hub · AWS Config

---

## Objectif

Passer d'une sécurité **réactive** (CloudTrail + alertes manuelles) à une sécurité **proactive et automatisée** : détection de menaces en temps réel, conformité continue, et posture de sécurité centralisée. Indispensable pour un déploiement industriel conforme NIS2/RGPD.

---

## 1. Les trois piliers de la sécurité AWS avancée

```
┌─────────────────────────────────────────────────────────────────┐
│                    POSTURE DE SÉCURITÉ AWS                       │
├──────────────────┬──────────────────┬───────────────────────────┤
│   DÉTECTION      │   CONFORMITÉ     │   CENTRALISATION          │
│   GuardDuty      │   AWS Config     │   Security Hub            │
│                  │                  │                           │
│ Analyse en       │ Vérifie que les  │ Agrège les findings de    │
│ continu des      │ ressources       │ GuardDuty, Config,        │
│ logs (CloudTrail,│ respectent les   │ Inspector, Macie,         │
│ VPC Flow Logs,   │ règles de        │ IAM Access Analyzer en    │
│ DNS) pour        │ sécurité en      │ un tableau de bord        │
│ détecter des     │ temps réel       │ unique avec score         │
│ comportements    │ (drift detection)│ de sécurité               │
│ anormaux         │                  │                           │
└──────────────────┴──────────────────┴───────────────────────────┘
```

---

## 2. AWS GuardDuty — Détection de menaces

### Fonctionnement

GuardDuty est un service de **threat intelligence** managé. Il analyse en continu trois sources de logs sans aucune configuration d'agent :

```
Sources analysées par GuardDuty :
  1. CloudTrail Management Events
     → Appels API suspects (création IAM, désactivation CloudTrail, etc.)

  2. VPC Flow Logs
     → Trafic réseau anormal (scan de ports, communication C&C)

  3. DNS Query Logs
     → Requêtes vers des domaines malveillants connus

  Optionnel (activation séparée) :
  4. EKS Audit Logs
  5. S3 Data Events
  6. RDS Login Activity
  7. Lambda Network Activity
  8. ECS Runtime (nouveau — 2024)
```

### Catégories de findings

```
FINDING TYPE                    SÉVÉRITÉ   EXEMPLE
───────────────────────────────────────────────────────────────────
UnauthorizedAccess:IAMUser      HIGH       API call depuis une IP TOR
Recon:EC2/PortProbeUnprotectedPort MEDIUM  Scan de ports sur l'instance
CryptoCurrency:EC2/BitcoinTool  HIGH       Minage de crypto sur Fargate
Trojan:EC2/DNSDataExfiltration  HIGH       Exfiltration via DNS
PrivilegeEscalation:IAMUser     HIGH       Tentative d'escalade de privilèges
Stealth:IAMUser/CloudTrailLoggingDisabled HIGH  Désactivation CloudTrail
UnauthorizedAccess:EC2/TorIPCaller MEDIUM  Appel depuis nœud TOR
```

### Intégration avec notre architecture

```
GuardDuty analyse :
  ✓ CloudTrail → Terraform apply, accès DynamoDB, Lambda invocations
  ✓ VPC Flow Logs → Trafic ECS Fargate ↔ DynamoDB, IoT Core ↔ Greengrass
  ✓ DNS → Résolution des endpoints IoT, ECR, CloudWatch

Cas de détection pertinents pour le projet :
  → Une tâche ECS commence à miner du crypto (conso CPU anormale + DNS mining pool)
  → Un accès DynamoDB depuis une IP inconnue hors VPC
  → Désactivation CloudTrail suite à un incident de déploiement Terraform
  → Scan de ports sur l'ALB depuis l'extérieur
```

### Réponse automatisée aux findings

```
GuardDuty Finding
      │
      ▼
EventBridge Rule
  (source: "aws.guardduty")
      │
      ├──► SNS Topic → Email/PagerDuty (notification immédiate)
      │
      └──► Lambda (remediation automatique)
             │
             ├── SÉVÉRITÉ HIGH → Isolation de la ressource
             │   (ECS task stop, SG rule revoke, IAM policy detach)
             │
             └── SÉVÉRITÉ MEDIUM → Ticket d'incident + log enrichi
```

---

## 3. Security Hub — Centralisation et scoring

### Qu'est-ce que Security Hub ?

Security Hub est le **SIEM léger d'AWS**. Il agrège les findings de tous les services de sécurité AWS dans un format normalisé (ASFF — AWS Security Finding Format) et calcule un **score de sécurité** par compte et par région.

```
Sources intégrées nativement :
  ✓ GuardDuty    → Threat detection findings
  ✓ AWS Config   → Conformité rules (failed checks)
  ✓ Inspector    → Vulnerabilités OS et packages (ECR images)
  ✓ Macie        → Données sensibles dans S3 (PII detection)
  ✓ IAM Access Analyzer → Accès non intentionnels (S3, KMS, Lambda)
  ✓ Firewall Manager → Règles WAF centralisées
```

### Standards de sécurité disponibles

```
1. AWS Foundational Security Best Practices (FSBP)
   → 200+ contrôles couvrant tous les services AWS
   → Niveau de base recommandé par AWS

2. CIS AWS Foundations Benchmark v1.4 / v3.0
   → Standard de l'industrie (Center for Internet Security)
   → 4 sections : IAM, Storage, Logging, Monitoring/Networking
   → Requis pour certaines certifications (ISO 27001, SOC 2)

3. NIST SP 800-53 rev5
   → Framework du gouvernement américain
   → Pertinent pour ITAR / FedRAMP

4. PCI DSS v3.2.1
   → Paiements (hors scope notre projet)
```

### Score de sécurité

```
Security Hub calcule un score de 0 à 100% par standard :
  100% = tous les contrôles passent
  0%   = aucun contrôle ne passe

Exemple pour Smart Assembly Line (estimation) :
  AWS FSBP          : ~72% (CloudTrail ✓, KMS ✓, MFA ✗ sur root, GuardDuty non encore activé)
  CIS Benchmark     : ~68% (VPC Flow Logs ✓, Config non activé)

Objectif après Jour 47 : > 85% sur AWS FSBP
```

### Contrôles critiques pour notre architecture

| Contrôle | Standard | Statut actuel | Action |
|---|---|---|---|
| `CloudTrail.1` — CloudTrail activé | FSBP | ✓ PASS | — |
| `CloudTrail.2` — CloudTrail chiffré KMS | FSBP | ✓ PASS | — |
| `KMS.4` — Rotation clé KMS activée | FSBP | ✓ PASS | — |
| `DynamoDB.1` — PITR activé | FSBP | ✓ PASS | — |
| `EC2.2` — SG par défaut sans règles | FSBP | À vérifier | Revue Terraform |
| `GuardDuty.1` — GuardDuty activé | FSBP | ✗ FAIL | Activer Jour 47 |
| `Config.1` — AWS Config activé | FSBP | ✗ FAIL | Activer Jour 47 |
| `IAM.4` — Pas de clé root active | CIS | ✓ PASS | — |
| `IAM.6` — MFA root activé | CIS | À vérifier | Console AWS |
| `VPC.1` — VPC Flow Logs activés | FSBP | ✓ PASS | — |
| `S3.1` — S3 Block Public Access | FSBP | ✓ PASS | — |

---

## 4. AWS Config — Conformité continue

### Rôle d'AWS Config

```
AWS Config résout le problème du "drift" :
  → Tu définis des règles de conformité
  → Config surveille en continu l'état de tes ressources
  → Si une ressource s'écarte de la règle → FINDING "NON_COMPLIANT"

Différence avec Security Hub :
  Security Hub = agrégateur de findings (QUOI est problématique)
  AWS Config   = moteur de règles (POURQUOI c'est non conforme + QUAND ça a changé)
```

### Types de règles Config

```
AWS Managed Rules (prêtes à l'emploi, ~250 disponibles) :
  encrypted-volumes         → Les EBS sont chiffrés
  iam-root-access-key-check → Pas de clé d'accès sur root
  mfa-enabled-for-iam-console-access → MFA sur tous les users IAM console
  vpc-flow-logs-enabled     → VPC Flow Logs actifs
  dynamodb-pitr-enabled     → PITR activé sur DynamoDB
  ecs-task-definition-no-environment-secrets → Pas de secrets en clair dans ECS
  kms-key-rotation-enabled  → Rotation annuelle des clés KMS

Custom Rules (Lambda) :
  → Règle métier spécifique au projet
  → Ex : "Toutes les tâches ECS doivent utiliser le rôle smart-assembly-task-role"
```

### Remediation automatique

```
AWS Config (NON_COMPLIANT)
      │
      ▼
Config Remediation Action
  → SSM Automation Document
      │
      ├── encrypted-volumes → Chiffrer le volume EBS automatiquement
      ├── vpc-flow-logs-enabled → Activer les Flow Logs automatiquement
      └── ecs-task-no-secrets → Alerter + bloquer le déploiement
```

### Config Aggregator (multi-compte / multi-région)

```
Pour un groupe multi-sites (multi-compte AWS Organizations) :
  Config Aggregator collecte les données de conformité de tous les comptes
  → Vue unifiée de la conformité de toute l'organisation
  → Pertinent pour Airbus : 16 sites = potentiellement 16 comptes AWS
```

---

## 5. Zero Trust Architecture

### Principe

```
Modèle traditionnel (Castle & Moat) :
  Tout ce qui est dans le VPC est de confiance
  → Si un attaquant entre dans le VPC, il accède à tout

Zero Trust :
  "Ne jamais faire confiance, toujours vérifier"
  → Chaque requête est authentifiée et autorisée
  → Peu importe l'origine (VPC interne, VPN, Internet)
  → Principe de moindre privilège systématique
```

### Application au Smart Assembly Line

```
IDENTITÉ (IAM) :
  ✓ ECS Task Role avec permissions minimales (principle of least privilege)
  ✓ Lambda Execution Role par fonction
  ✓ Greengrass Certificate par appareil IoT
  ✓ MFA obligatoire pour tous les accès console

RÉSEAU :
  ✓ Sous-réseaux privés (ECS, Lambda)
  ✓ Security Groups restrictifs (port 8080 ECS → ALB seulement)
  ✓ VPC Endpoints (trafic AWS ne sort pas sur Internet)
  ✓ NACLs en dernière ligne de défense

DONNÉES :
  ✓ KMS CMK pour DynamoDB, CloudTrail, ECR
  ✓ TLS 1.2+ partout (ALB, IoT Core MQTT over TLS)
  ✓ S3 Block Public Access
  ✓ Secrets Manager (pas de secrets en dur dans le code)

DÉTECTION :
  ✓ CloudTrail (audit complet)
  ✓ GuardDuty (threat detection)
  ✓ Config (drift detection)
  ✓ Security Hub (scoring continu)
```

---

## 6. Lien avec NIS2 et RGPD

### NIS2 (Directive EU 2022/2555)

```
Article 21 — Mesures de gestion des risques de cybersécurité :

Exigence NIS2                          Implémentation Smart Assembly Line
─────────────────────────────────────────────────────────────────────────
Politiques de sécurité documentées  → Ce document + docs/architecture/security.md
Gestion des incidents                → GuardDuty + SNS + EventBridge remediation
Continuité d'activité                → Multi-région active/passive (Jour 46)
Sécurité de la chaîne d'appros.      → ECR image scanning (Inspector)
Chiffrement                          → KMS CMK sur tous les services
Tests réguliers                      → Chaos engineering (Jour 42-43)
Formation du personnel               → Documentation MkDocs (ce projet)
```

### RGPD — Article 32 — Sécurité du traitement

```
Mesures techniques appropriées :
  ✓ Pseudonymisation (id_poste = "TLS#A320#P12", pas de données personnelles)
  ✓ Chiffrement (KMS CMK)
  ✓ Disponibilité continue (multi-région)
  ✓ Restauration rapide (PITR DynamoDB, S3 CRR)
  ✓ Évaluation régulière (Security Hub score continu)

Note : les données de capteurs (vibration, température, pression) ne sont
pas des données personnelles au sens RGPD (pas de personne physique identifiable).
Le RGPD s'appliquerait si on stockait des données opérateurs (badges, biométrie).
```

---

## 7. Concepts clés retenus

**GuardDuty vs CloudTrail** : CloudTrail enregistre TOUS les appels API (audit trail). GuardDuty ANALYSE ces logs avec de la threat intelligence pour détecter les comportements anormaux. Les deux sont complémentaires : CloudTrail = log brut, GuardDuty = analyse intelligente.

**Security Hub score** : le score de sécurité est une métrique opérationnelle, pas juste un rapport. En Staff Architect, on l'intègre dans le pipeline CI/CD — un score < 80% bloque le déploiement en production.

**AWS Config drift detection** : la capacité à détecter quand une ressource a été modifiée hors Terraform (par un opérateur en urgence, par exemple) est critique en production. Config répond à "qu'est-ce qui a changé et quand ?"

**Remediation automatique** : la différence entre un système résilient et un système simplement monitoré est la remédiation automatique. GuardDuty + EventBridge + Lambda = réponse en secondes plutôt qu'en heures.

**Zero Trust vs Castle & Moat** : le modèle "périmètre réseau = confiance" est obsolète dès qu'on a du multi-cloud, du remote access, ou des partenaires. Zero Trust s'applique même à l'intérieur du VPC — un pod ECS ne devrait pas avoir accès aux secrets d'un autre service.

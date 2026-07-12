# Sécurité — Vue d'ensemble

Ce document synthétise la posture de sécurité du système Smart Assembly Line.
Il couvre les quatre axes : réseau, identité, chiffrement et flux de données sécurisés.
Ce document est mis à jour à chaque évolution de l'architecture.

---

## 1. Zones réseau — Isolation et contrôle du trafic

```mermaid
flowchart TB
    subgraph INTERNET["🌐 Internet"]
        OPS[Opérateurs]
        DEVICE[Simulateur IoT\nposte_1]
    end

    subgraph VPC["VPC — 10.10.0.0/16 (isolé)"]
        IGW[Internet Gateway\nseule porte vers internet]

        subgraph PUBLIC["Subnet Public — 10.10.1.0/24"]
            ALB[ALB\nport 80/443]
            NAT[NAT Gateway\n+ Elastic IP]
        end

        subgraph PRIVATE["Subnet Privé — 10.10.2.0/24\naucune IP publique"]
            LAMBDA[Lambda\nAnalyzeVibration\nStoreMetrics]
            API[Spring Boot API\nà venir]
        end

        subgraph ENDPOINTS["VPC Endpoints — backbone AWS privé"]
            EP_DDB[Endpoint\nDynamoDB]
            EP_S3[Endpoint\nS3]
        end
    end

    subgraph IOTCORE["AWS IoT Core\nendpoint managé AWS"]
        MQTT[Endpoint MQTT\nTLS 1.2 — port 8883]
        RULES[Rules Engine]
    end

    subgraph STORAGE["Stockage"]
        DDB[(DynamoDB\nmachine_state)]
        S3[(S3\nraw-data)]
    end

    DEVICE -->|mTLS X.509\nport 8883| MQTT
    OPS -->|HTTPS| IGW --> ALB --> API
    MQTT --> RULES
    RULES -->|invoke| LAMBDA
    LAMBDA -->|trafic privé| EP_DDB --> DDB
    LAMBDA -->|trafic privé| EP_S3 --> S3
    LAMBDA -->|sortie internet si besoin| NAT --> IGW
```

### Règles d'isolation

| Zone | Trafic entrant | Trafic sortant |
|---|---|---|
| Subnet public | Internet → ALB (80/443) | IGW → Internet |
| Subnet privé | ALB → API (8080) uniquement | NAT → Internet, VPC Endpoints → AWS |
| IoT Core | Device → MQTT (8883) mTLS | Rules Engine → Lambda |
| VPC Endpoints | Lambda → DynamoDB/S3 | Backbone AWS privé |

---

## 2. Identité — Rôles IAM et moindre privilège

```mermaid
flowchart TD
    subgraph ROLES["Rôles IAM"]
        LR[smart-assembly-lambda-role\nAssumeRole: lambda.amazonaws.com]
        IR[smart-assembly-iot-role\nAssumeRole: iot.amazonaws.com]
    end

    subgraph BOUNDARY["Permission Boundary\nsmart-assembly-lambda-boundary"]
        B1[s3:PutObject ✅]
        B2[dynamodb:PutItem\ndynamodb:UpdateItem\ndynamodb:GetItem ✅]
        B3[kms:GenerateDataKey\nkms:Decrypt ✅]
        B4[logs:CreateLogGroup\nlogs:PutLogEvents ✅]
        B5[s3:DeleteObject ❌]
        B6[iam:* ❌]
        B7[s3:GetObject ❌]
    end

    subgraph POLICIES["Policies attachées"]
        P1[lambda-dynamodb-policy\nPutItem · UpdateItem · GetItem]
        P2[lambda-s3-policy\nPutObject uniquement]
        P3[lambda-logs-policy\nCreateLogGroup · PutLogEvents]
    end

    LR --> BOUNDARY
    LR --> P1
    LR --> P2
    LR --> P3
    IR -->|Publish IoT Rules| RULES_P[iot:Publish\niot:Subscribe]
```

### Matrice des permissions effectives

| Action | Rôle Lambda | Rôle IoT | Admin CLI |
|---|---|---|---|
| `s3:PutObject` | ✅ | ❌ | ✅ |
| `s3:GetObject` | ❌ | ❌ | ✅ |
| `s3:DeleteObject` | ❌ | ❌ | ✅ |
| `dynamodb:PutItem` | ✅ | ❌ | ✅ |
| `dynamodb:Scan` | ❌ | ❌ | ✅ |
| `kms:GenerateDataKey` | ✅ | ❌ | ✅ |
| `iam:CreateRole` | ❌ | ❌ | ✅ |
| `iot:Publish` (propre topic) | ❌ | ✅ | ✅ |
| `iot:Publish` (topic autre device) | ❌ | ❌ | ✅ |

---

## 3. Chiffrement — Données en transit et au repos

```mermaid
flowchart LR
    subgraph TRANSIT["Chiffrement en transit"]
        T1[Device → IoT Core\nmTLS X.509 — port 8883\nTLS 1.2 minimum]
        T2[Opérateur → ALB\nHTTPS — port 443\nTLS 1.2 minimum]
        T3[Lambda → DynamoDB/S3\nHTTPS via VPC Endpoint\nTLS natif AWS]
    end

    subgraph REST["Chiffrement au repos"]
        R1[S3 — SSE-KMS\nalias/smart-assembly-key\nEnvelope encryption]
        R2[DynamoDB — SSE-KMS\nalias/smart-assembly-key\nChiffrement transparent]
    end

    subgraph KMS["AWS KMS — CMK"]
        KEY[smart-assembly-key\nRotation annuelle activée\nHSM — non exportable]
        DEK[Data Encryption Key\néphémère — générée à la demande]
    end

    R1 -->|GenerateDataKey| KEY
    R2 -->|GenerateDataKey| KEY
    KEY --> DEK
    DEK -->|chiffre les données| R1
    DEK -->|chiffre les données| R2
```

### Matrice de chiffrement

| Canal / Stockage | Protocole | Clé | Niveau |
|---|---|---|---|
| Device → IoT Core | mTLS / TLS 1.2 | Certificat X.509 par device | Fort |
| Opérateur → ALB | HTTPS / TLS 1.2 | Certificat ACM | Fort |
| Lambda → AWS Services | HTTPS (VPC Endpoint) | TLS natif | Fort |
| S3 (au repos) | SSE-KMS | CMK `smart-assembly-key` | Fort + auditabilité |
| DynamoDB (au repos) | SSE-KMS | CMK `smart-assembly-key` | Fort + auditabilité |

---

## 4. Flux de données sécurisé — Du capteur au data lake

```mermaid
sequenceDiagram
    participant D as Device (poste_1)
    participant I as IoT Core
    participant R as Rules Engine
    participant L1 as Lambda AnalyzeVibration
    participant L2 as Lambda StoreMetrics
    participant DB as DynamoDB
    participant S3 as S3 (chiffré KMS)

    D->>I: MQTT publish [mTLS X.509]
    Note over D,I: Authentification mutuelle<br/>certificat device + CA AWS

    I->>I: Vérification IoT Policy<br/>topic = assembly-line/poste_1/metrics ✅

    I->>R: Message routé vers Rules Engine
    R->>L1: Invoke [IAM role check]
    R->>L2: Invoke [IAM role check]

    L1->>DB: PutItem [HTTPS + KMS]
    Note over L1,DB: Permission boundary vérifie<br/>dynamodb:PutItem ✅

    L2->>S3: PutObject [HTTPS + KMS]
    Note over L2,S3: Bucket Policy vérifie<br/>Principal = lambda-role ✅<br/>KMS chiffre l'objet

    DB-->>L1: 200 OK
    S3-->>L2: 200 OK
```

---

## 5. Synthèse — Niveaux de défense (Defense in Depth)

| Couche | Mécanisme | Composant protégé |
|---|---|---|
| **Réseau** | VPC isolation, subnet privé sans IP publique | Lambda, API backend |
| **Authentification device** | mTLS X.509, certificat par device | IoT Core |
| **Autorisation device** | IoT Policy — publish sur son seul topic | IoT Core |
| **Autorisation service** | IAM roles + least privilege | Lambda, S3, DynamoDB |
| **Plafond de permissions** | Permission Boundary | Rôle Lambda |
| **Contrôle ressource** | S3 Bucket Policy — PutObject uniquement | Data lake |
| **Chiffrement transit** | TLS 1.2 partout | Tous les flux |
| **Chiffrement repos** | SSE-KMS avec CMK | S3, DynamoDB |
| **Auditabilité** | CloudTrail + KMS audit logs | Toutes les actions AWS |

---

## 6. Dette technique — Points à adresser

| Point | Risque | Priorité |
|---|---|---|
| Lambda hors VPC | Lambda appelle DynamoDB/S3 via endpoints publics AWS, pas via VPC Endpoints | Semaine 6 |
| Single-AZ | Pas de résilience zonale sur le subnet privé | Semaine 7 |
| Pas de WAF sur l'ALB | Trafic HTTP non filtré sur le tableau de bord | Semaine 6 |
| CloudTrail non activé | Pas de trace des appels API AWS | Jour 37 |
| Certificats IoT gérés manuellement | Pas de rotation automatique des certs device | Backlog |

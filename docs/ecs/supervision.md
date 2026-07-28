# ECS Fargate — API de Supervision Spring Boot

> Backend de supervision de la ligne d'assemblage aérospatiale.
> Expose une API REST consommant DynamoDB pour afficher l'état temps réel des postes de travail.

---

## 1. Positionnement dans la stack

```
Edge (Greengrass / Docker local)
        │
        ▼ MQTT / IoT Core
AWS Lambda analyze_vibration
        │
        ▼ DynamoDB
   machine_state
        │
        ▼
ECS Fargate — supervision-api (Spring Boot)
        │
        ▼
ALB (Application Load Balancer)
        │
        ▼
  Dashboard / Client REST
```

Les Lambdas **écrivent** dans DynamoDB (traitement temps réel).
L'API Spring Boot **lit** DynamoDB et agrège les données pour la supervision humaine.
Séparation claire des responsabilités : Lambda = ingestion, ECS = consultation.

---

## 2. Concepts ECS

### 2.1 Les 4 objets fondamentaux

```
Cluster          → groupe logique de ressources compute
Task Definition  → blueprint du conteneur (image, CPU, RAM, env vars, ports)
Task             → instance en cours d'exécution d'une Task Definition
Service          → gestionnaire qui maintient N tasks en vie (restart auto)
```

Analogie Kubernetes : Cluster ≈ Cluster, Task Definition ≈ Pod Spec, Service ≈ Deployment.

### 2.2 Fargate vs EC2 launch type

| | Fargate | EC2 |
|--|--|--|
| Gestion serveurs | AWS s'en charge | Toi (patch, AMI, scaling) |
| Facturation | vCPU + RAM à la seconde | Instance EC2 à l'heure |
| Démarrage | ~30s | ~2-3 min (boot EC2) |
| Cas d'usage | APIs, microservices, jobs | Workloads GPU, licences par socket |

Pour ce projet : **Fargate** — pas d'EC2 à gérer, facturation précise, démarrage rapide.

### 2.3 Task Definition — paramètres clés

```json
{
  "family": "supervision-api",
  "cpu": "256",
  "memory": "512",
  "networkMode": "awsvpc",
  "containerDefinitions": [{
    "name": "supervision-api",
    "image": "169237360990.dkr.ecr.eu-west-3.amazonaws.com/supervision-api:latest",
    "portMappings": [{"containerPort": 8080}],
    "environment": [
      {"name": "TABLE_NAME", "value": "machine_state"},
      {"name": "AWS_REGION", "value": "eu-west-3"}
    ],
    "healthCheck": {
      "command": ["CMD-SHELL", "curl -f http://localhost:8080/actuator/health || exit 1"],
      "interval": 30,
      "timeout": 5,
      "retries": 3,
      "startPeriod": 60
    },
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/supervision-api",
        "awslogs-region": "eu-west-3",
        "awslogs-stream-prefix": "ecs"
      }
    }
  }]
}
```

`startPeriod: 60` — Spring Boot met ~6-8s à démarrer. Sans ce paramètre, ECS
pourrait tuer la task avant qu'elle soit prête.

### 2.4 Service ECS

```hcl
resource "aws_ecs_service" "supervision_api" {
  name            = "supervision-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.supervision_api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.ecs_supervision.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.supervision_api.arn
    container_name   = "supervision-api"
    container_port   = 8080
  }
}
```

---

## 3. ECR — Elastic Container Registry

ECR est le registry Docker privé d'AWS. Alternative à Docker Hub, intégré avec IAM.

```
Developer → docker build → docker push → ECR
                                           │
                                           ▼
                                    ECS pull l'image
                                    (via Task Execution Role)
```

### Commandes ECR

```bash
# Authentification
aws ecr get-login-password --region eu-west-3 \
  | docker login --username AWS \
    --password-stdin 169237360990.dkr.ecr.eu-west-3.amazonaws.com

# Build + tag
docker build -t supervision-api .
docker tag supervision-api:latest \
  169237360990.dkr.ecr.eu-west-3.amazonaws.com/supervision-api:latest

# Push
docker push 169237360990.dkr.ecr.eu-west-3.amazonaws.com/supervision-api:latest
```

---

## 4. ALB — Application Load Balancer

```
Internet
    │
    ▼
ALB (port 80)
    │  Listener Rule : /* → Target Group
    ▼
Target Group (port 8080)
    │  Health check : GET /actuator/health → 200 OK
    ▼
ECS Tasks (Fargate)
```

### Pourquoi ALB devant ECS ?

- IP des tasks Fargate change à chaque restart → ALB fournit une IP stable
- Health checks : ALB retire automatiquement une task unhealthy
- SSL termination : HTTPS sur ALB, HTTP en interne (simplification pour le lab)
- Future scalabilité : ajouter desired_count = 3, ALB répartit automatiquement

---

## 5. IAM — deux rôles distincts

C'est un point souvent mal compris, même par des seniors.

### 5.1 Task Execution Role

Utilisé par **ECS lui-même** pour démarrer la task :
- Puller l'image depuis ECR
- Écrire les logs dans CloudWatch
- Lire les secrets depuis Secrets Manager (si utilisé)

```
Policy : AmazonECSTaskExecutionRolePolicy (AWS managed)
```

### 5.2 Task Role

Utilisé par **l'application** dans le conteneur :
- Lire DynamoDB
- Appeler CloudWatch GetMetricData

```hcl
resource "aws_iam_role_policy" "supervision_api_task" {
  role = aws_iam_role.supervision_api_task.id
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:Scan", "dynamodb:GetItem", "dynamodb:Query"]
      Resource = aws_dynamodb_table.machine_state.arn
    }, {
      Effect   = "Allow"
      Action   = ["cloudwatch:DescribeAlarms", "cloudwatch:GetMetricData"]
      Resource = "*"
    }]
  })
}
```

**Règle d'or** : le Task Role ne donne jamais `dynamodb:*` — uniquement les actions
nécessaires. Pas de PutItem, DeleteItem.

---

## 6. Spring Boot sur ECS Fargate

### 6.1 Pourquoi Spring Boot ?

- Standard de fait dans l'industrie aérospatiale / manufacturing (Java)
- Spring Actuator : `/actuator/health` = health check ECS natif, sans code supplémentaire
- AWS SDK v2 for Java : client DynamoDB async performant
- Pattern enterprise reconnu en entretien senior

### 6.2 Dockerfile optimisé (multi-stage)

```dockerfile
# Build stage
FROM maven:3.9-eclipse-temurin-21-alpine AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -q
COPY src ./src
RUN mvn package -DskipTests -q

# Runtime stage
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

Multi-stage build : l'image finale ne contient pas Maven ni les sources (~180 MB).

### 6.3 Endpoints API

```
GET /actuator/health          → {"status": "UP"}  (ECS health check)
GET /api/machines             → liste tous les postes depuis DynamoDB
GET /api/machines/{id_poste}  → détail d'un poste
GET /api/alerts               → postes en statut CRITICAL ou WARN
```

### 6.4 AWS SDK v2 — authentification automatique sur ECS

Sur ECS Fargate, le SDK Java récupère automatiquement les credentials depuis
le Task Metadata Endpoint (ECS injecte un token dans l'environnement).
Aucune clé AWS dans le code — c'est le Task Role qui s'applique.

```java
// Pas de .credentialsProvider() — auto-discovery sur ECS
DynamoDbClient client = DynamoDbClient.builder()
    .region(Region.EU_WEST_3)
    .build();
```

---

## 7. CloudWatch Container Insights

Container Insights collecte automatiquement CPU, RAM, réseau et logs par task.

```hcl
resource "aws_ecs_cluster" "main" {
  name = "smart-assembly-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
```

Visible dans : **CloudWatch → Container Insights → ECS Clusters**

---

## 8. Fichiers créés

```
terraform/environments/dev/
  ecs.tf                    ← cluster, task def, service, ALB, ECR, IAM, SGs

src/supervision-api/
  Dockerfile
  pom.xml
  src/main/java/com/smartassembly/supervision/
    SupervisionApplication.java
    controller/MachineController.java
    service/MachineService.java
    model/MachineState.java
```

---

## 9. Bonnes pratiques senior architect

**Immutabilité des images** : toujours tagger avec le SHA du commit git, jamais
déployer `:latest` en production. En CI/CD : `supervision-api:${GITHUB_SHA}`.

**Secrets** : les variables sensibles ne vont pas dans les Task Definition en clair —
elles vont dans AWS Secrets Manager, référencées par ARN (`valueFrom`).

**Desired count** : en production, `desired_count = 2` minimum avec les tasks
sur deux AZ différentes. Fargate gère la distribution automatiquement.

**Graceful shutdown** : configurer `server.shutdown=graceful` dans
`application.properties`. ECS envoie SIGTERM → attend 30s → SIGKILL.
Sans graceful shutdown, les requêtes en cours sont coupées brutalement.

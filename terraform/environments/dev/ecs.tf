# =============================================================
# ECS Fargate — API de Supervision Spring Boot
# Smart Assembly Line
#
# Ressources :
#   - ECR repository
#   - ECS Cluster + Container Insights
#   - CloudWatch Log Group
#   - IAM Task Execution Role + Task Role
#   - Security Group ECS (ALB → ECS)
#   - Task Definition + Service Fargate
#
# ALB/Listener/Target Group : définis dans alb.tf
# =============================================================

locals {
  supervision_api_name  = "supervision-api"
  supervision_api_port  = 8080
  supervision_api_image = "${aws_ecr_repository.supervision_api.repository_url}:latest"
}

# ──────────────────────────────────────────────
# ECR — Container Registry
# ──────────────────────────────────────────────

resource "aws_ecr_repository" "supervision_api" {
  name                 = local.supervision_api_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "supervision-api"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_ecr_lifecycle_policy" "supervision_api" {
  repository = aws_ecr_repository.supervision_api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Garder les 10 dernières images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ──────────────────────────────────────────────
# ECS Cluster
# ──────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "smart-assembly-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name        = "smart-assembly-cluster"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# ──────────────────────────────────────────────
# CloudWatch Log Group
# ──────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "ecs_supervision" {
  name              = "/ecs/supervision-api"
  retention_in_days = 30

  tags = {
    Name        = "ecs-supervision-api-logs"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

# ──────────────────────────────────────────────
# IAM — Task Execution Role
# Utilisé par ECS pour puller l'image ECR et écrire les logs
# ──────────────────────────────────────────────

resource "aws_iam_role" "ecs_task_execution" {
  name = "smart-assembly-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "ecs-task-execution-role"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ──────────────────────────────────────────────
# IAM — Task Role
# Utilisé par l'application Spring Boot dans le conteneur
# ──────────────────────────────────────────────

resource "aws_iam_role" "supervision_api_task" {
  name = "smart-assembly-supervision-api-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "supervision-api-task-role"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

resource "aws_iam_role_policy" "supervision_api_task" {
  name = "supervision-api-task-policy"
  role = aws_iam_role.supervision_api_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DynamoDBReadOnly"
        Effect   = "Allow"
        Action   = ["dynamodb:Scan", "dynamodb:GetItem", "dynamodb:Query"]
        Resource = aws_dynamodb_table.machine_state.arn
      },
      {
        Sid      = "CloudWatchRead"
        Effect   = "Allow"
        Action   = ["cloudwatch:DescribeAlarms", "cloudwatch:GetMetricData"]
        Resource = "*"
      },
      {
        Sid      = "KMSDecryptDynamoDB"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = "arn:aws:kms:eu-west-3:169237360990:key/7d2fd7d2-6d2a-4ce9-beb3-b61621aa90aa"
      }
    ]
  })
}

# ──────────────────────────────────────────────
# Security Group — ECS Tasks
# N'accepte que le trafic provenant de l'ALB existant
# ──────────────────────────────────────────────

resource "aws_security_group" "ecs_supervision" {
  name        = "smart-assembly-ecs-supervision-sg"
  description = "ECS supervision-api : trafic entrant depuis ALB uniquement"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Depuis ALB uniquement"
    from_port       = local.supervision_api_port
    to_port         = local.supervision_api_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # SG ALB défini dans alb.tf
  }

  egress {
    description = "Vers internet (ECR pull, DynamoDB, CloudWatch via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ecs-supervision-sg"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

# ──────────────────────────────────────────────
# ECS Task Definition
# ──────────────────────────────────────────────

resource "aws_ecs_task_definition" "supervision_api" {
  family                   = local.supervision_api_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.supervision_api_task.arn

  container_definitions = jsonencode([{
    name      = local.supervision_api_name
    image     = local.supervision_api_image
    essential = true

    portMappings = [{
      containerPort = local.supervision_api_port
      protocol      = "tcp"
    }]

    environment = [
      { name = "TABLE_NAME", value = aws_dynamodb_table.machine_state.name },
      { name = "AWS_REGION", value = "eu-west-3" },
      { name = "SERVER_PORT", value = tostring(local.supervision_api_port) }
    ]

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${local.supervision_api_port}/actuator/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_supervision.name
        "awslogs-region"        = "eu-west-3"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = {
    Name        = "supervision-api-task-def"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

# ──────────────────────────────────────────────
# ECS Service
# ──────────────────────────────────────────────

resource "aws_ecs_service" "supervision_api" {
  name            = local.supervision_api_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.supervision_api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private.id]
    security_groups  = [aws_security_group.ecs_supervision.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn # Target group dans alb.tf
    container_name   = local.supervision_api_name
    container_port   = local.supervision_api_port
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.ecs_task_execution,
    aws_iam_role_policy.supervision_api_task,
  ]

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    Name        = "supervision-api-service"
    Project     = "smart-assembly-line"
    Environment = "dev"
  }
}

# ──────────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────────

output "ecr_repository_url" {
  description = "URI ECR pour docker push"
  value       = aws_ecr_repository.supervision_api.repository_url
}

output "alb_dns_name" {
  description = "URL publique de l'API de supervision"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecs_cluster_name" {
  description = "Nom du cluster ECS"
  value       = aws_ecs_cluster.main.name
}

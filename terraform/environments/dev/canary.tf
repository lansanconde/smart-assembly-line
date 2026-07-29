# =============================================================
# Canary Deployment — Smart Assembly Line
#
# Pattern : ALB Weighted Target Groups
#   - Blue  (TG existant) : 90% du trafic → supervision-api stable (v1)
#   - Green (TG canary)   : 10% du trafic → supervision-api canary (v2)
#
# Activation : terraform apply -var="canary_active=true" -var="canary_image_tag=v2"
# Rollback   : terraform apply -var="canary_active=false"
#
# Toutes les ressources canary sont conditionnelles (count = canary_active ? 1 : 0)
# → en mode normal, aucune ressource canary n'existe dans AWS
# =============================================================

# ──────────────────────────────────────────────────────────
# Variables
# ──────────────────────────────────────────────────────────

variable "canary_active" {
  description = "Active le déploiement canary (true = 10% du trafic vers la version canary)"
  type        = bool
  default     = false
}

variable "canary_image_tag" {
  description = "Tag de l'image ECR à déployer en canary (ex: v2, git SHA court)"
  type        = string
  default     = "canary"
}

variable "canary_weight" {
  description = "Pourcentage du trafic dirigé vers le canary (1-99)"
  type        = number
  default     = 10

  validation {
    condition     = var.canary_weight >= 1 && var.canary_weight <= 99
    error_message = "canary_weight doit être entre 1 et 99."
  }
}

# ──────────────────────────────────────────────────────────
# CloudWatch Log Group — canary
# Logs séparés pour isoler les erreurs canary des logs stables
# ──────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "ecs_canary" {
  count             = var.canary_active ? 1 : 0
  name              = "/ecs/supervision-api-canary"
  retention_in_days = 7 # courte rétention : logs temporaires pendant le canary

  tags = {
    Name        = "ecs-supervision-api-canary-logs"
    Project     = "smart-assembly-line"
    Environment = "dev"
    Canary      = "true"
  }
}

# ──────────────────────────────────────────────────────────
# Target Group — Canary (Green)
# TG dédié pour isoler les métriques canary (5xx, latence)
# du TG stable (Blue)
# ──────────────────────────────────────────────────────────

resource "aws_lb_target_group" "canary" {
  count       = var.canary_active ? 1 : 0
  name        = "smart-assembly-canary-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip" # Fargate exige target_type = "ip"

  health_check {
    path                = "/actuator/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = {
    Name        = "smart-assembly-canary-tg"
    Project     = "smart-assembly-line"
    Environment = "dev"
    Canary      = "true"
  }
}

# ──────────────────────────────────────────────────────────
# ECS Task Definition — Canary (v2)
# Identique à la task definition stable mais avec l'image canary
# ──────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "supervision_api_canary" {
  count                    = var.canary_active ? 1 : 0
  family                   = "supervision-api-canary"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.supervision_api_task.arn

  container_definitions = jsonencode([{
    name  = "supervision-api"
    image = "${aws_ecr_repository.supervision_api.repository_url}:${var.canary_image_tag}"

    essential = true

    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]

    environment = [
      { name = "TABLE_NAME", value = aws_dynamodb_table.machine_state.name },
      { name = "AWS_REGION", value = "eu-west-3" },
      { name = "SERVER_PORT", value = "8080" },
      { name = "CANARY_VERSION", value = var.canary_image_tag } # header de debug
    ]

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8080/actuator/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/supervision-api-canary"
        "awslogs-region"        = "eu-west-3"
        "awslogs-stream-prefix" = "canary"
      }
    }
  }])

  tags = {
    Name        = "supervision-api-canary-task-def"
    Project     = "smart-assembly-line"
    Environment = "dev"
    Canary      = "true"
    ImageTag    = var.canary_image_tag
  }
}

# ──────────────────────────────────────────────────────────
# ECS Service — Canary (1 task)
# Tourne en parallèle du service stable
# desired_count = 1 : 1 task canary suffit pour le test initial
# ──────────────────────────────────────────────────────────

resource "aws_ecs_service" "supervision_api_canary" {
  count           = var.canary_active ? 1 : 0
  name            = "supervision-api-canary"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.supervision_api_canary[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private.id]
    security_groups  = [aws_security_group.ecs_supervision.id] # même SG que le service stable
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.canary[0].arn
    container_name   = "supervision-api"
    container_port   = 8080
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  depends_on = [
    aws_lb_listener_rule.canary,
    aws_iam_role_policy_attachment.ecs_task_execution,
    aws_iam_role_policy.supervision_api_task,
  ]

  tags = {
    Name        = "supervision-api-canary-service"
    Project     = "smart-assembly-line"
    Environment = "dev"
    Canary      = "true"
    ImageTag    = var.canary_image_tag
  }
}

# ──────────────────────────────────────────────────────────
# ALB Listener Rule — Weighted Forwarding 90/10
#
# Priority 10 : s'applique AVANT la default_action du listener
# La default_action (100% Blue) reste en place comme fallback
# si la règle canary est supprimée (rollback)
# ──────────────────────────────────────────────────────────

resource "aws_lb_listener_rule" "canary" {
  count        = var.canary_active ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.backend.arn       # Blue (stable)
        weight = 100 - var.canary_weight               # 90 par défaut
      }
      target_group {
        arn    = aws_lb_target_group.canary[0].arn     # Green (canary)
        weight = var.canary_weight                     # 10 par défaut
      }
      stickiness {
        enabled  = false # désactivé : distribution aléatoire pure
        duration = 1
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"] # intercepte toutes les requêtes
    }
  }

  tags = {
    Name        = "canary-weighted-rule"
    Project     = "smart-assembly-line"
    Environment = "dev"
    Canary      = "true"
  }
}

# ──────────────────────────────────────────────────────────
# Outputs canary
# ──────────────────────────────────────────────────────────

output "canary_status" {
  description = "État du déploiement canary"
  value       = var.canary_active ? "ACTIF — ${var.canary_weight}% trafic → ${var.canary_image_tag}" : "INACTIF"
}

output "canary_target_group_arn" {
  description = "ARN du target group canary (Green)"
  value       = var.canary_active ? aws_lb_target_group.canary[0].arn : "n/a"
}

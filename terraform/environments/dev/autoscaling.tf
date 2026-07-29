# =============================================================
# ECS Auto Scaling — Smart Assembly Line
#
# Mise à l'échelle automatique du service supervision-api (ECS Fargate)
# via Application Auto Scaling + Target Tracking Policy sur CPU.
#
# Comportement :
#   CPU moyen > 60% → scale out (jusqu'à 4 tasks)
#   CPU moyen << 60% après 300s → scale in  (minimum 1 task)
#
# Les alarmes CloudWatch scale-out / scale-in sont créées
# automatiquement par AWS — pas besoin de les provisionner.
# =============================================================

# ──────────────────────────────────────────────────────────
# 1. Scalable Target
#    Enregistre le service ECS auprès d'Application Auto Scaling
# ──────────────────────────────────────────────────────────
resource "aws_appautoscaling_target" "supervision_api" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.supervision_api.name}"
  scalable_dimension = "ecs:service:DesiredCount"

  min_capacity = 1 # jamais en dessous de 1 task (API toujours disponible)
  max_capacity = 4 # plafond : évite les coûts incontrôlés en cas de bug
}

# ──────────────────────────────────────────────────────────
# 2. Target Tracking Policy — CPU
#    Maintient le CPU moyen du service autour de 60%
#    AWS crée automatiquement les alarmes CloudWatch associées
# ──────────────────────────────────────────────────────────
resource "aws_appautoscaling_policy" "supervision_api_cpu" {
  name               = "smart-assembly-supervision-api-cpu-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.supervision_api.resource_id
  scalable_dimension = aws_appautoscaling_target.supervision_api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.supervision_api.service_namespace

  target_tracking_scaling_policy_configuration {
    # Métrique prédéfinie : CPU moyen sur tous les tasks du service
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value = 60.0 # % CPU cible

    # Cooldown scale-out : attendre 60s entre deux scale-out successifs
    # (Fargate met ~60s à démarrer un nouveau container Spring Boot)
    scale_out_cooldown = 60

    # Cooldown scale-in : attendre 5 min avant de supprimer un task
    # (conservateur : évite l'oscillation scale-out/scale-in)
    scale_in_cooldown = 300

    # disable_scale_in = false (défaut) : le scale-in est activé
    # Mettre à true pour des services où on préfère ne jamais réduire la capacité
    disable_scale_in = false
  }
}

# ──────────────────────────────────────────────────────────
# 3. Target Tracking Policy — Mémoire (secondaire)
#    Si la mémoire dépasse 80%, scale out indépendamment du CPU
#    Utile si l'API est CPU-bound mais pas memory-bound (ou inversement)
# ──────────────────────────────────────────────────────────
resource "aws_appautoscaling_policy" "supervision_api_memory" {
  name               = "smart-assembly-supervision-api-memory-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.supervision_api.resource_id
  scalable_dimension = aws_appautoscaling_target.supervision_api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.supervision_api.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = 75.0 # % mémoire cible (512 MB alloués → seuil à 384 MB)
    scale_out_cooldown = 60
    scale_in_cooldown  = 300
    disable_scale_in   = false
  }
}

# ──────────────────────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────────────────────
output "autoscaling_target_resource_id" {
  description = "Resource ID du scalable target ECS"
  value       = aws_appautoscaling_target.supervision_api.resource_id
}

output "autoscaling_min_capacity" {
  description = "Nombre minimum de tasks ECS"
  value       = aws_appautoscaling_target.supervision_api.min_capacity
}

output "autoscaling_max_capacity" {
  description = "Nombre maximum de tasks ECS"
  value       = aws_appautoscaling_target.supervision_api.max_capacity
}

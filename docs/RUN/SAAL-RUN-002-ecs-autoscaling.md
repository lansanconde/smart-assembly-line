# Runbook — ECS Auto Scaling

## Déploiement
```bash
terraform apply -target=aws_appautoscaling_target.ecs \
                -target=aws_appautoscaling_policy.cpu_scale_out \
                -target=aws_appautoscaling_policy.cpu_scale_in
```

## Vérification
```bash
aws application-autoscaling describe-scalable-targets \
  --service-namespace ecs --region eu-west-3
```

## Désactivation temporaire
```bash
aws application-autoscaling deregister-scalable-target \
  --service-namespace ecs \
  --resource-id service/smart-assembly-cluster/supervision-api \
  --scalable-dimension ecs:service:DesiredCount \
  --region eu-west-3
```

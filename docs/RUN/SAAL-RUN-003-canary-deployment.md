# Runbook — Canary Deployment

## Prérequis
- 2 Target Groups ALB : Blue (stable) + Green (canary)
- ECS service canary : `supervision-api-canary`

## Déploiement canary (10%)
```bash
aws elbv2 modify-rule --rule-arn $RULE_ARN \
  --actions '[{"Type":"forward","ForwardConfig":{"TargetGroups":[
    {"TargetGroupArn":"'$TG_BLUE'","Weight":90},
    {"TargetGroupArn":"'$TG_GREEN'","Weight":10}]}}]'
```

## Rollback immédiat
```bash
aws elbv2 modify-rule --rule-arn $RULE_ARN \
  --actions '[{"Type":"forward","TargetGroupArn":"'$TG_BLUE'"}]'
```

## Promotion (100% Green)
```bash
# Même commande avec Weight: Green=100, Blue=0
# Puis arrêter ECS Blue task
```

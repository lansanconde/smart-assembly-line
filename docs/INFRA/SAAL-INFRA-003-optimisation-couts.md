# Coûts AWS — Smart Assembly Line

---

## Coût mensuel estimé (août 2026, après optimisations)

| Service | Coût/mois |
|---------|-----------|
| ALB | ~$13 |
| ECS Fargate (1 task 24/7) | ~$12 |
| DynamoDB | ~$2 |
| S3 | ~$0.5 |
| KMS (2 CMK) | ~$2 |
| CloudWatch | ~$0.5 |
| **Total** | **~$30** |

> ECS arrêté (`desired_count=0`) → économie $12/mois → **~$18/mois**

---

## Crédits AWS (état août 2026)

| Indicateur | Valeur |
|------------|--------|
| Crédits restants | $117.19 |
| Après août (estimé) | ~$84.83 |
| Durée restante à $18/mois | ~4.7 mois → **janvier 2027** ✅ |

---

## Optimisations réalisées

| Action | Économie |
|--------|----------|
| Suppression 4 NAT Gateways orphelines | ~$128/mois |
| ECS → subnet public (`assign_public_ip=true`) | $32/mois (NAT ECS supprimée) |
| `ignore_changes = [desired_count]` | Stop/start manuel sans drift Terraform |

---

## Auto-expiry 31 décembre 2026

EventBridge Scheduler → Lambda `cf_expiry` → `desired_count=0` + CloudFront API désactivé.

# CloudTrail — Audit

Enregistre tous les appels API AWS — qui a fait quoi, quand.

---

## Config déployée

| Paramètre | Valeur |
|-----------|--------|
| Trail name | `smart-assembly-trail` |
| Région | Global (toutes régions) |
| Stockage logs | S3 bucket dédié + chiffrement KMS |
| Rétention | 90 jours |
| Log File Validation | ✅ activée (intégrité garantie) |
| Événements | Management events (read + write) |

---

## Exemples d'événements tracés

```
2026-08-06 terraform apply     → CreateFunction, PutItem, UpdateService
2026-08-07 NAT supprimée       → DeleteNatGateway, ReleaseAddress
2026-08-08 ECS desired=0       → UpdateService (userAgent: aws-cli)
```

---

## Accès

Console AWS → CloudTrail → Event history  
Ou query Athena sur le bucket S3 pour des recherches avancées.

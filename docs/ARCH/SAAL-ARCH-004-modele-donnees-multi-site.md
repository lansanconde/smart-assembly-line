# Modèle de données — DynamoDB

---

## Table `machine_state` (actuelle)

| Attribut | Type | Exemple |
|----------|------|---------|
| `id_poste` (PK) | String | `"poste-1"` |
| `statut` | String | `"OK"` / `"WARN"` / `"CRITICAL"` |
| `vibration` | Number | `1.24` |
| `temperature` | Number | `72.3` |
| `pression` | Number | `4.2` |
| `timestamp` | String | `"2026-08-06T10:00:00Z"` |

**Chiffrement** : KMS CMK `7d2fd7d2-6d2a-4ce9-beb3-b61621aa90aa`

---

## Accès

| Opération | Qui | Permission IAM |
|-----------|-----|---------------|
| Write | Lambda `analyze_vibration` | `dynamodb:PutItem` |
| Read | ECS `supervision-api` | `dynamodb:Scan`, `Query`, `GetItem` |
| Decrypt | ECS task role | `kms:Decrypt`, `kms:DescribeKey` |

---

## Pattern d'évolution multi-site

```
Actuel    → PK: id_poste  = "poste-1"
Cible     → PK: site_id   = "toulouse"
             SK: poste_id  = "ligne-a320#poste-12"
```

Permet le query `site_id = "toulouse"` pour afficher tous les postes d'un site.

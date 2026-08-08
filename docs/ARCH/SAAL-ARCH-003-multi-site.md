# Architecture multi-site — Cible 100K capteurs

> Architecture cible de montée en charge. Non déployée en production.

---

## Hiérarchie industrielle

```
Groupe (ex: Airbus)
  └── Région (Europe / Amériques / Asie)
        └── Site (Toulouse / Hambourg / Mobile)
              └── Ligne (A320 / A350)
                    └── Poste (Assemblage fuselage #12)
                          └── Capteur (vibration, temp, pression)
```

---

## Évolutions clés vs architecture actuelle

| Composant | Actuel (mono-site) | Multi-site cible |
|-----------|-------------------|-----------------|
| DynamoDB PK | `id_poste` | `site_id#poste_id` |
| IoT Thing Group | Flat | Hiérarchie site/ligne/poste |
| EventBridge | 1 bus global | 1 bus par site |
| Greengrass | Local | 1 instance par site |
| Capacité | ~10 postes | 100K capteurs |

---

## Modèle DynamoDB cible

```
PK: site_id        = "toulouse"
SK: poste_id       = "ligne-a320#poste-12"
GSI: statut_index  = "CRITICAL" → query par statut cross-site
TTL: 30 jours      → purge automatique
```

---

## Scalabilité IoT Core

- **Thing Groups** : segmentation par site → policies isolées par site
- **Topic hiérarchique** : `{groupe}/{region}/{site}/{ligne}/{poste}/metrics`
- **Rules Engine** : 1 règle par niveau de hiérarchie, pas 1 par poste

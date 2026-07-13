import json
import logging
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    """
    Dernière étape du workflow Step Functions.
    Produit un log structuré JSON pour l'audit de l'intervention.
    CloudWatch Logs Insights peut ensuite requêter :
    "toutes les interventions CRITICAL sur poste_1 cette semaine"
    """
    logger.info(json.dumps({
        "fonction":               "LogIntervention",
        "id_poste":               event.get("id_poste"),
        "statut":                 "EN_INTERVENTION",
        "regle":                  event.get("regle"),
        "mesures":                event.get("mesures"),
        "timestamp_intervention": datetime.now(timezone.utc).isoformat(),
    }))

    return {
        "statusCode": 200,
        "id_poste":  event.get("id_poste"),
        "action":    "intervention_logged",
    }
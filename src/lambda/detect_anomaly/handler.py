import json
import boto3
import os
import logging
from datetime import datetime, timezone

# Logs structurés JSON
logger = logging.getLogger()
logger.setLevel(logging.INFO)

eventbridge = boto3.client("events")
dynamodb = boto3.resource("dynamodb")

EVENT_BUS_NAME = os.environ.get("EVENT_BUS_NAME", "smart-assembly-events")
TABLE_NAME     = os.environ.get("TABLE_NAME", "machine_state")

# ──────────────────────────────────────────────
# Seuils par métrique
# ──────────────────────────────────────────────
THRESHOLDS = {
    "vibration":   {"WARN": 1.5,  "CRITICAL": 2.5},
    "temperature": {"WARN": 80.0, "CRITICAL": 95.0},
    "pression":    {"WARN": 5.0,  "CRITICAL": 6.5},
}


def evaluate_rules(payload: dict) -> tuple[str, str, str]:
    """
    Évalue les règles métier combinées.
    Retourne (statut, regle_declenchee, detail).

    Priorité des règles :
    1. Seuil CRITICAL sur une seule métrique
    2. Combo dangereux : vibration WARN + température WARN simultanées
    3. Seuil WARN sur une seule métrique
    4. OK
    """
    vib  = float(payload.get("vibration", 0))
    temp = float(payload.get("temperature", 0))
    pres = float(payload.get("pression", 0))

    # Règle 1 — CRITICAL individuel (priorité maximale)
    if vib >= THRESHOLDS["vibration"]["CRITICAL"]:
        return "CRITICAL", "vibration.critique", f"vibration={vib} >= {THRESHOLDS['vibration']['CRITICAL']}"
    if temp >= THRESHOLDS["temperature"]["CRITICAL"]:
        return "CRITICAL", "temperature.critique", f"temperature={temp} >= {THRESHOLDS['temperature']['CRITICAL']}"
    if pres >= THRESHOLDS["pression"]["CRITICAL"]:
        return "CRITICAL", "pression.critique", f"pression={pres} >= {THRESHOLDS['pression']['CRITICAL']}"

    # Règle 2 — Combo dangereux : deux métriques en WARN simultanément
    warn_count = sum([
        vib  >= THRESHOLDS["vibration"]["WARN"],
        temp >= THRESHOLDS["temperature"]["WARN"],
        pres >= THRESHOLDS["pression"]["WARN"],
    ])
    if warn_count >= 2:
        return "CRITICAL", "combo.dangereux", f"multi-warn: vib={vib}, temp={temp}, pres={pres}"

    # Règle 3 — WARN individuel
    if vib >= THRESHOLDS["vibration"]["WARN"]:
        return "WARN", "vibration.warn", f"vibration={vib}"
    if temp >= THRESHOLDS["temperature"]["WARN"]:
        return "WARN", "temperature.warn", f"temperature={temp}"
    if pres >= THRESHOLDS["pression"]["WARN"]:
        return "WARN", "pression.warn", f"pression={pres}"

    # Règle 4 — OK
    return "OK", "mesure.normale", "aucun seuil depasse"


def is_duplicate(id_poste: str, timestamp: str) -> bool:
    """
    Idempotence : vérifie si cet événement a déjà été traité.
    Compare le timestamp_last dans DynamoDB avec le timestamp courant.
    """
    try:
        table = dynamodb.Table(TABLE_NAME)
        response = table.get_item(Key={"id_poste": id_poste})
        item = response.get("Item", {})
        return item.get("timestamp_last") == timestamp
    except Exception as e:
        logger.warning(f"[DetectAnomaly] Vérification idempotence échouée : {e} — on continue")
        return False


def publish_event(id_poste: str, statut: str, regle: str, detail: str, payload: dict) -> None:
    """
    Publie l'événement sur EventBridge.
    Le detail-type encode la sévérité pour le routing des règles EventBridge.
    """
    detail_type_map = {
        "CRITICAL": "anomalie.critique",
        "WARN":     "anomalie.warn",
        "OK":       "mesure.normale",
    }

    eventbridge.put_events(Entries=[{
        "Source":       "smart-assembly.iot",
        "DetailType":   detail_type_map[statut],
        "EventBusName": EVENT_BUS_NAME,
        "Detail": json.dumps({
            "id_poste":  id_poste,
            "statut":    statut,
            "regle":     regle,
            "detail":    detail,
            "mesures": {
                "vibration":   payload.get("vibration"),
                "temperature": payload.get("temperature"),
                "pression":    payload.get("pression"),
            },
            "timestamp": payload.get("timestamp"),
        }),
    }])


def lambda_handler(event, context):
    """
    Déclenchée par l'IoT Rules Engine sur assembly-line/+/metrics.
    Évalue les règles métier combinées et publie sur EventBridge.
    Idempotente : un même message reçu deux fois ne publie qu'un seul événement.
    """
    id_poste  = event.get("id_poste")
    timestamp = event.get("timestamp", datetime.now(timezone.utc).isoformat())

    if not id_poste:
        raise ValueError("Champ 'id_poste' manquant dans le payload MQTT")

    # Idempotence — ne pas retraiter un message déjà vu
    if is_duplicate(id_poste, timestamp):
        logger.info(json.dumps({
            "fonction": "DetectAnomaly",
            "action":   "skip_duplicate",
            "id_poste": id_poste,
            "timestamp": timestamp,
        }))
        return {"statusCode": 200, "action": "duplicate_skipped"}

    # Évaluation des règles métier
    statut, regle, detail = evaluate_rules(event)

    # Publication EventBridge
    publish_event(id_poste, statut, regle, detail, event)

    # Log structuré JSON — queryable via CloudWatch Logs Insights
    logger.info(json.dumps({
        "fonction":  "DetectAnomaly",
        "id_poste":  id_poste,
        "statut":    statut,
        "regle":     regle,
        "detail":    detail,
        "timestamp": timestamp,
    }))

    return {
        "statusCode": 200,
        "id_poste":   id_poste,
        "statut":     statut,
        "regle":      regle,
    }

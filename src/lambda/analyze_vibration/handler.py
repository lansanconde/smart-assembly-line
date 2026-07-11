import json
import boto3
import os
from datetime import datetime, timezone

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ.get("TABLE_NAME", "machine_state")

# Seuils d'anomalie par métrique
THRESHOLDS = {
    "vibration":   {"WARN": 1.5,  "CRITICAL": 2.5},
    "temperature": {"WARN": 80.0, "CRITICAL": 95.0},
    "pression":    {"WARN": 5.0,  "CRITICAL": 6.5},
}


def evaluate_status(payload: dict) -> tuple[str, str | None]:
    """
    Évalue le statut global du poste en fonction des seuils.
    Retourne (statut, anomalie_type) : statut = OK | WARN | CRITICAL
    CRITICAL a la priorité sur WARN.
    """
    status = "OK"
    anomalie_type = None

    for metric, levels in THRESHOLDS.items():
        value = float(payload.get(metric, 0))
        if value >= levels["CRITICAL"]:
            return "CRITICAL", metric.upper()
        elif value >= levels["WARN"]:
            status = "WARN"
            anomalie_type = metric.upper()

    return status, anomalie_type


def lambda_handler(event, context):
    """
    Déclenchée par l'IoT Rules Engine sur assembly-line/+/metrics.
    Met à jour l'état courant du poste dans DynamoDB (machine_state).
    Un seul item par poste — écrasement à chaque message (vue courante, pas historique).
    """
    print(f"[AnalyzeVibration] Event reçu : {json.dumps(event)}")

    id_poste    = event.get("id_poste")
    vibration   = event.get("vibration")
    temperature = event.get("temperature")
    pression    = event.get("pression")
    timestamp   = event.get("timestamp", datetime.now(timezone.utc).isoformat())

    if not id_poste:
        raise ValueError("Champ 'id_poste' manquant dans le payload MQTT")

    status, anomalie_type = evaluate_status(event)

    table = dynamodb.Table(TABLE_NAME)
    table.put_item(Item={
        "id_poste":         id_poste,
        "statut":           status,
        "vibration_last":   str(vibration),
        "temperature_last": str(temperature),
        "pression_last":    str(pression),
        "timestamp_last":   timestamp,
        "anomalie_type":    anomalie_type or "null",
    })

    print(f"[AnalyzeVibration] {id_poste} → {status} | anomalie: {anomalie_type}")
    return {"statusCode": 200, "statut": status, "id_poste": id_poste}

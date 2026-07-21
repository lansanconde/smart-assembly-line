import json
import boto3
import os
from datetime import datetime, timezone

dynamodb   = boto3.resource("dynamodb")
cloudwatch = boto3.client("cloudwatch")

TABLE_NAME = os.environ.get("TABLE_NAME", "machine_state")
CW_NAMESPACE = "SmartAssemblyLine"

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


def publish_cloudwatch_metrics(payload: dict, statut: str):
    """
    Publie les métriques capteurs dans CloudWatch pour Grafana.
    Namespace : SmartAssemblyLine
    """
    id_poste = payload.get("id_poste", "unknown")
    try:
        cloudwatch.put_metric_data(
            Namespace=CW_NAMESPACE,
            MetricData=[
                {
                    "MetricName": "Vibration",
                    "Dimensions": [{"Name": "Poste", "Value": id_poste}],
                    "Value": float(payload.get("vibration", 0)),
                    "Unit": "None",
                },
                {
                    "MetricName": "Temperature",
                    "Dimensions": [{"Name": "Poste", "Value": id_poste}],
                    "Value": float(payload.get("temperature", 0)),
                    "Unit": "None",
                },
                {
                    "MetricName": "Pression",
                    "Dimensions": [{"Name": "Poste", "Value": id_poste}],
                    "Value": float(payload.get("pression", 0)),
                    "Unit": "None",
                },
                {
                    "MetricName": "MessageCount",
                    "Dimensions": [
                        {"Name": "Poste",  "Value": id_poste},
                        {"Name": "Statut", "Value": statut},
                    ],
                    "Value": 1,
                    "Unit": "Count",
                },
            ],
        )
        # AnomalyScore ML si présent dans le payload
        if payload.get("ml_detected") is not None:
            cloudwatch.put_metric_data(
                Namespace=CW_NAMESPACE,
                MetricData=[{
                    "MetricName": "AnomalyScore",
                    "Dimensions": [{"Name": "Poste", "Value": id_poste}],
                    "Value": float(payload.get("anomaly_score", 0)),
                    "Unit": "None",
                }],
            )
    except Exception as e:
        # Ne pas bloquer le pipeline si CloudWatch échoue
        print(f"[CloudWatch] Erreur publication métriques : {e}")


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

    # Publication métriques CloudWatch pour Grafana
    publish_cloudwatch_metrics(event, status)

    print(f"[AnalyzeVibration] {id_poste} → {status} | anomalie: {anomalie_type}")
    return {"statusCode": 200, "statut": status, "id_poste": id_poste}

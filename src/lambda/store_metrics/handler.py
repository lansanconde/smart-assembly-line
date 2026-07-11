import json
import boto3
import os
from datetime import datetime, timezone

s3 = boto3.client("s3")
BUCKET_NAME = os.environ.get("BUCKET_NAME", "smart-assembly-raw-data-169237360990")


def build_s3_key(id_poste: str, timestamp: str) -> str:
    """
    Construit la clé S3 partitionnée par date/heure.
    Format : 2026/07/09/20/poste_1_1720555464.json
    Permet à Athena de scanner uniquement la partition pertinente.
    """
    try:
        dt = datetime.fromisoformat(timestamp)
    except Exception:
        dt = datetime.now(timezone.utc)

    epoch = int(dt.timestamp())
    return f"{dt.year}/{dt.month:02d}/{dt.day:02d}/{dt.hour:02d}/{id_poste}_{epoch}.json"


def lambda_handler(event, context):
    """
    Déclenchée par l'IoT Rules Engine sur assembly-line/+/metrics.
    Stocke le message brut dans S3 (data lake) sous une clé partitionnée par date.
    Idempotent : deux livraisons du même message écrasent le même objet S3
    avec un contenu identique — pas d'effet de bord.
    """
    print(f"[StoreMetrics] Event reçu : {json.dumps(event)}")

    id_poste  = event.get("id_poste")
    timestamp = event.get("timestamp", datetime.now(timezone.utc).isoformat())

    if not id_poste:
        raise ValueError("Champ 'id_poste' manquant dans le payload MQTT")

    key  = build_s3_key(id_poste, timestamp)
    body = json.dumps(event, ensure_ascii=False, indent=2)

    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=key,
        Body=body.encode("utf-8"),
        ContentType="application/json",
    )

    print(f"[StoreMetrics] Stocké → s3://{BUCKET_NAME}/{key}")
    return {"statusCode": 200, "s3_key": key}

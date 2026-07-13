"""
Simulateur de capteurs — Poste d'assemblage industriel
Publie des mesures de vibration, température et pression
sur AWS IoT Core via MQTT/TLS toutes les 2 secondes.
"""

import json
import time
import random
from datetime import datetime, timezone
from awsiot import mqtt_connection_builder
from awscrt import mqtt

# ── Configuration ──────────────────────────────────────────
ENDPOINT   = "aood9gt2q2oe5-ats.iot.eu-west-3.amazonaws.com"
CLIENT_ID  = "poste_1"
TOPIC      = f"assembly-line/{CLIENT_ID}/metrics"
CERT_DIR   = "certs"

# Seuils normaux — au-delà = anomalie
SEUILS = {
    "vibration":   2.0,   # m/s²
    "temperature": 80.0,  # °C
    "pression":    5.0,   # bar
}
# ───────────────────────────────────────────────────────────


def on_connection_interrupted(connection, error, **kwargs):
    print(f"[WARN] Connexion interrompue : {error}")


def on_connection_resumed(connection, return_code, session_present, **kwargs):
    print(f"[INFO] Connexion rétablie (return_code={return_code})")


def build_payload() -> dict:
    """Force des valeurs en zone WARN/CRITICAL pour le test pipeline."""
    vibration   = round(random.uniform(1.6, 3.2), 2)   # toujours > 1.5 WARN
    temperature = round(random.uniform(81.0, 98.0), 1)  # toujours > 80 WARN
    pression    = round(random.uniform(3.5, 5.5), 2)

    return {
        "id_poste":    CLIENT_ID,
        "vibration":   vibration,
        "temperature": temperature,
        "pression":    pression,
        "timestamp":   datetime.now(timezone.utc).isoformat(),
    }


def main():
    print(f"[INFO] Connexion à {ENDPOINT}...")

    connection = mqtt_connection_builder.mtls_from_path(
        endpoint        = ENDPOINT,
        cert_filepath   = f"{CERT_DIR}/certificate.pem",
        pri_key_filepath= f"{CERT_DIR}/private.key",
        ca_filepath     = f"{CERT_DIR}/AmazonRootCA1.pem",
        client_id       = CLIENT_ID,
        on_connection_interrupted = on_connection_interrupted,
        on_connection_resumed     = on_connection_resumed,
        clean_session   = False,
        keep_alive_secs = 30,
    )

    connect_future = connection.connect()
    connect_future.result()
    print(f"[INFO] Connecté. Publication sur '{TOPIC}' toutes les 2s.")
    print("[INFO] Ctrl+C pour arrêter.\n")

    try:
        while True:
            payload = build_payload()
            connection.publish(
                topic   = TOPIC,
                payload = json.dumps(payload),
                qos     = mqtt.QoS.AT_LEAST_ONCE,
            )
            statut_label = "⚠ CRIT" if payload["vibration"] >= 2.5 else "⚠ WARN"
            print(f"[{statut_label}] vib={payload['vibration']} temp={payload['temperature']} pres={payload['pression']}")
            time.sleep(2)

    except KeyboardInterrupt:
        print("\n[INFO] Arrêt demandé.")
    finally:
        disconnect_future = connection.disconnect()
        disconnect_future.result()
        print("[INFO] Déconnecté proprement.")


if __name__ == "__main__":
    main()
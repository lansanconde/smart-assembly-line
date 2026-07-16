"""
Simulateur de capteurs — Poste d'assemblage industriel
Publie des mesures de vibration, température et pression
sur AWS IoT Core via MQTT/TLS toutes les 2 secondes.
Met à jour le Device Shadow avec l'état courant (reported).
S'abonne au Shadow delta pour recevoir les changements de seuils à chaud.
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
SHADOW_UPDATE_TOPIC = f"$aws/things/{CLIENT_ID}/shadow/update"
SHADOW_DELTA_TOPIC  = f"$aws/things/{CLIENT_ID}/shadow/update/delta"
CERT_DIR   = "certs"

# Seuils — modifiables à chaud via Device Shadow desired
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


def on_shadow_delta(topic, payload, **kwargs):
    """Reçoit les changements de configuration depuis le Shadow desired."""
    delta = json.loads(payload).get("state", {})
    print(f"\n[SHADOW] Delta reçu : {delta}")
    if "seuil_vibration" in delta:
        SEUILS["vibration"] = delta["seuil_vibration"]
        print(f"[SHADOW] Seuil vibration mis à jour → {SEUILS['vibration']} m/s²")
    if "seuil_temperature" in delta:
        SEUILS["temperature"] = delta["seuil_temperature"]
        print(f"[SHADOW] Seuil température mis à jour → {SEUILS['temperature']} °C")


def build_payload() -> dict:
    """Génère des mesures en zone WARN/CRITICAL pour le test pipeline."""
    vibration   = round(random.uniform(1.6, 3.2), 2)
    temperature = round(random.uniform(81.0, 98.0), 1)
    pression    = round(random.uniform(3.5, 5.5), 2)
    return {
        "id_poste":    CLIENT_ID,
        "vibration":   vibration,
        "temperature": temperature,
        "pression":    pression,
        "timestamp":   datetime.now(timezone.utc).isoformat(),
    }


def get_statut(payload: dict) -> tuple[str, str]:
    """Détermine le statut selon les seuils courants (modifiables via Shadow)."""
    vib  = payload["vibration"]
    temp = payload["temperature"]
    if vib >= SEUILS["vibration"] * 1.25 or temp >= SEUILS["temperature"] * 1.2:
        return "CRITICAL", "⚠ CRIT"
    elif vib >= SEUILS["vibration"] or temp >= SEUILS["temperature"]:
        return "WARN", "⚠ WARN"
    return "OK", "✓ OK  "


def update_shadow(connection, payload: dict, statut: str):
    """Met à jour le Device Shadow reported avec l'état courant du poste."""
    shadow_payload = {
        "state": {
            "reported": {
                "vibration":         payload["vibration"],
                "temperature":       payload["temperature"],
                "pression":          payload["pression"],
                "statut":            statut,
                "seuil_vibration":   SEUILS["vibration"],
                "seuil_temperature": SEUILS["temperature"],
                "timestamp":         payload["timestamp"],
            }
        }
    }
    connection.publish(
        topic   = SHADOW_UPDATE_TOPIC,
        payload = json.dumps(shadow_payload),
        qos     = mqtt.QoS.AT_LEAST_ONCE,
    )


def main():
    print(f"[INFO] Connexion à {ENDPOINT}...")

    connection = mqtt_connection_builder.mtls_from_path(
        endpoint         = ENDPOINT,
        cert_filepath    = f"{CERT_DIR}/certificate.pem",
        pri_key_filepath = f"{CERT_DIR}/private.key",
        ca_filepath      = f"{CERT_DIR}/AmazonRootCA1.pem",
        client_id        = CLIENT_ID,
        on_connection_interrupted = on_connection_interrupted,
        on_connection_resumed     = on_connection_resumed,
        clean_session    = False,
        keep_alive_secs  = 30,
    )

    connect_future = connection.connect()
    connect_future.result()
    print(f"[INFO] Connecté. Publication sur '{TOPIC}' toutes les 2s.")

    # Abonnement au delta pour recevoir les changements de config à chaud
    subscribe_future, _ = connection.subscribe(
        topic    = SHADOW_DELTA_TOPIC,
        qos      = mqtt.QoS.AT_LEAST_ONCE,
        callback = on_shadow_delta,
    )
    subscribe_future.result()
    print(f"[INFO] Shadow delta abonné : {SHADOW_DELTA_TOPIC}")
    print(f"[INFO] Seuils initiaux : vib={SEUILS['vibration']} temp={SEUILS['temperature']}")
    print("[INFO] Ctrl+C pour arrêter.\n")

    try:
        while True:
            payload = build_payload()
            statut, label = get_statut(payload)

            # 1. Publier les métriques sur le topic MQTT
            connection.publish(
                topic   = TOPIC,
                payload = json.dumps(payload),
                qos     = mqtt.QoS.AT_LEAST_ONCE,
            )

            # 2. Mettre à jour le Device Shadow reported
            update_shadow(connection, payload, statut)

            print(
                f"[{label}] vib={payload['vibration']} "
                f"temp={payload['temperature']} "
                f"pres={payload['pression']} "
                f"| seuils vib={SEUILS['vibration']} temp={SEUILS['temperature']}"
            )
            time.sleep(2)

    except KeyboardInterrupt:
        print("\n[INFO] Arrêt demandé.")
    finally:
        disconnect_future = connection.disconnect()
        disconnect_future.result()
        print("[INFO] Déconnecté proprement.")


if __name__ == "__main__":
    main()

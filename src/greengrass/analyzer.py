"""
analyzer.py — Component edge "smart-assembly-analyzer"
Jour 30 — Edge Computing (équivalent component Greengrass)

Rôle :
  1. S'abonne au broker Mosquitto LOCAL (port 1883)
  2. Analyse chaque mesure localement (vibration, température)
  3. Ne transfère vers IoT Core (cloud) QUE les événements WARN/CRITICAL
  → Réduction estimée : 80-90% du trafic cloud supprimé

Flux :
  publish_vibration.py → Mosquitto:1883 → analyzer.py
                                               └── WARN/CRITICAL → IoT Core MQTT
"""

import json
import time
import paho.mqtt.client as mqtt
from awsiot import mqtt_connection_builder
from awscrt import mqtt as aws_mqtt

# ── Configuration locale (Mosquitto) ───────────────────────
# LOCAL_BROKER = "mosquitto" dans Docker (nom du service)
# LOCAL_BROKER = "localhost" en dehors de Docker (dev local)
import os
LOCAL_BROKER   = os.environ.get("LOCAL_BROKER", "localhost")
LOCAL_PORT     = int(os.environ.get("LOCAL_PORT", 1883))
LOCAL_TOPIC    = "assembly-line/+/metrics"

# ── Configuration cloud (IoT Core) ─────────────────────────
IOT_ENDPOINT   = "aood9gt2q2oe5-ats.iot.eu-west-3.amazonaws.com"
IOT_CLIENT_ID  = "greengrass-core-poste"
CERT_DIR       = "certs"
CLOUD_TOPIC    = "assembly-line/{id_poste}/metrics"  # même topic que le pipeline existant

# ── Seuils d'alerte ────────────────────────────────────────
SEUILS = {
    "vibration":   2.0,   # m/s²
    "temperature": 80.0,  # °C
}

# Compteurs pour mesurer l'efficacité du filtrage
stats = {"total": 0, "forwarded": 0}

# Connexion IoT Core (initialisée une fois au démarrage)
iot_connection = None


def connect_iot_core():
    """Établit la connexion MQTT persistante vers IoT Core."""
    global iot_connection
    print(f"[CLOUD] Connexion à IoT Core : {IOT_ENDPOINT}")
    iot_connection = mqtt_connection_builder.mtls_from_path(
        endpoint         = IOT_ENDPOINT,
        cert_filepath    = f"{CERT_DIR}/device.pem.crt",
        pri_key_filepath = f"{CERT_DIR}/private.pem.key",
        ca_filepath      = f"{CERT_DIR}/AmazonRootCA1.pem",
        client_id        = IOT_CLIENT_ID,
        clean_session    = False,
        keep_alive_secs  = 30,
    )
    future = iot_connection.connect()
    future.result()
    print("[CLOUD] Connecté à IoT Core.")


def get_statut(payload: dict) -> str:
    """Analyse locale — retourne OK / WARN / CRITICAL."""
    vib  = payload.get("vibration", 0)
    temp = payload.get("temperature", 0)
    if vib >= SEUILS["vibration"] * 1.25 or temp >= SEUILS["temperature"] * 1.2:
        return "CRITICAL"
    elif vib >= SEUILS["vibration"] or temp >= SEUILS["temperature"]:
        return "WARN"
    return "OK"


def forward_to_cloud(payload: dict, statut: str):
    """Publie vers IoT Core uniquement si WARN ou CRITICAL."""
    alert = {**payload, "statut": statut, "edge_filtered": True}
    topic = CLOUD_TOPIC.format(id_poste=payload.get("id_poste", "unknown"))
    iot_connection.publish(
        topic   = topic,
        payload = json.dumps(alert),
        qos     = aws_mqtt.QoS.AT_LEAST_ONCE,
    )
    print(f"[CLOUD ↑] {statut} — {topic} | vib={payload['vibration']} temp={payload['temperature']}")


def on_local_message(client, userdata, msg):
    """Callback — reçoit chaque mesure depuis Mosquitto local."""
    stats["total"] += 1
    try:
        payload = json.loads(msg.payload.decode())
        statut  = get_statut(payload)

        if statut in ("WARN", "CRITICAL"):
            stats["forwarded"] += 1
            forward_to_cloud(payload, statut)
        else:
            # Mesure OK — ignorée, ne remonte pas au cloud
            print(f"[EDGE  ✓] OK filtré — vib={payload['vibration']} temp={payload['temperature']} (non envoyé)")

        # Afficher les stats de filtrage toutes les 10 mesures
        if stats["total"] % 10 == 0:
            pct = (1 - stats["forwarded"] / stats["total"]) * 100
            print(f"\n[STATS] {stats['total']} mesures | {stats['forwarded']} envoyées au cloud | {pct:.0f}% filtrées localement\n")

    except Exception as e:
        print(f"[ERROR] Impossible de traiter le message : {e}")


def on_local_connect(client, userdata, flags, rc):
    if rc == 0:
        print(f"[LOCAL] Connecté à Mosquitto ({LOCAL_BROKER}:{LOCAL_PORT})")
        client.subscribe(LOCAL_TOPIC)
        print(f"[LOCAL] Abonné à : {LOCAL_TOPIC}")
    else:
        print(f"[LOCAL] Échec connexion Mosquitto (rc={rc})")


def main():
    # 1. Connexion IoT Core (cloud) — persistante
    connect_iot_core()

    # 2. Connexion Mosquitto local — écoute les capteurs
    local_client = mqtt.Client(client_id="edge-analyzer")
    local_client.on_connect = on_local_connect
    local_client.on_message = on_local_message

    print(f"[LOCAL] Connexion à Mosquitto {LOCAL_BROKER}:{LOCAL_PORT}...")
    local_client.connect(LOCAL_BROKER, LOCAL_PORT, keepalive=60)

    print("[INFO] Analyzer démarré. Ctrl+C pour arrêter.\n")
    try:
        local_client.loop_forever()
    except KeyboardInterrupt:
        print("\n[INFO] Arrêt demandé.")
    finally:
        local_client.disconnect()
        if iot_connection:
            iot_connection.disconnect().result()
        total = stats["total"]
        fwd   = stats["forwarded"]
        if total > 0:
            print(f"\n[BILAN] {total} mesures reçues | {fwd} envoyées au cloud | {(1-fwd/total)*100:.0f}% filtrées")


if __name__ == "__main__":
    main()

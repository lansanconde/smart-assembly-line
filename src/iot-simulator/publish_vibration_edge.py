"""
publish_vibration_edge.py — Simulateur capteur (mode edge)
Edge Computing

Différence avec publish_vibration.py :
  - Publie vers Mosquitto LOCAL (port 1883, pas de TLS)
  - Ne se connecte PAS à IoT Core directement
  - L'analyzer.py se charge du filtrage et de l'envoi vers le cloud
"""

import json
import time
import random
from datetime import datetime, timezone
import paho.mqtt.client as mqtt

# ── Configuration ───────────────────────────────────────────
LOCAL_BROKER = "localhost"
LOCAL_PORT   = 1885
CLIENT_ID    = "poste_1"
TOPIC        = f"assembly-line/{CLIENT_ID}/metrics"

SEUILS = {
    "vibration":   2.0,
    "temperature": 80.0,
    "pression":    5.0,
}
# ────────────────────────────────────────────────────────────


def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print(f"[INFO] Connecté à Mosquitto ({LOCAL_BROKER}:{LOCAL_PORT})")
        print(f"[INFO] Publication sur '{TOPIC}' toutes les 2s.")
        print("[INFO] Ctrl+C pour arrêter.\n")
    else:
        print(f"[ERROR] Échec connexion Mosquitto (rc={rc})")


def build_payload() -> dict:
    vibration   = round(random.uniform(1.6, 3.2), 2)
    temperature = round(random.uniform(75.0, 98.0), 1)
    pression    = round(random.uniform(3.5, 5.5), 2)
    return {
        "id_poste":    CLIENT_ID,
        "vibration":   vibration,
        "temperature": temperature,
        "pression":    pression,
        "timestamp":   datetime.now(timezone.utc).isoformat(),
    }


def main():
    client = mqtt.Client(client_id=f"sim-{CLIENT_ID}")
    client.on_connect = on_connect

    print(f"[INFO] Connexion à Mosquitto {LOCAL_BROKER}:{LOCAL_PORT}...")
    client.connect(LOCAL_BROKER, LOCAL_PORT, keepalive=60)
    client.loop_start()

    try:
        while True:
            payload = build_payload()
            client.publish(TOPIC, json.dumps(payload), qos=1)

            # Déterminer statut pour affichage local uniquement
            vib  = payload["vibration"]
            temp = payload["temperature"]
            if vib >= SEUILS["vibration"] * 1.25 or temp >= SEUILS["temperature"] * 1.2:
                label = "⚠ CRIT"
            elif vib >= SEUILS["vibration"] or temp >= SEUILS["temperature"]:
                label = "⚠ WARN"
            else:
                label = "✓ OK  "

            print(f"[{label}] → Mosquitto | vib={vib} temp={temp} pres={payload['pression']}")
            time.sleep(2)

    except KeyboardInterrupt:
        print("\n[INFO] Arrêt demandé.")
    finally:
        client.loop_stop()
        client.disconnect()
        print("[INFO] Déconnecté.")


if __name__ == "__main__":
    main()

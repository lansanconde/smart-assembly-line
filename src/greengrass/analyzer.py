"""
analyzer.py — Component edge "smart-assembly-analyzer"
Jour 31 — Circuit Breaker + Buffer local JSONL

Circuit Breaker états :
  CLOSED    : envoi normal vers IoT Core
  OPEN      : buffer local JSONL, aucune tentative cloud
  HALF_OPEN : teste un message, flush buffer si succès

Flux :
  publish_vibration_edge.py → Mosquitto:1883 → analyzer.py
                                                    ├── OK       → ignoré
                                                    └── WARN/CRITICAL
                                                          ├── CB CLOSED/HALF_OPEN → IoT Core
                                                          └── CB OPEN             → buffer JSONL
"""

import json
import os
import time
import threading
import paho.mqtt.client as mqtt
from awsiot import mqtt_connection_builder
from awscrt import mqtt as aws_mqtt

# ── Configuration locale (Mosquitto) ───────────────────────
LOCAL_BROKER = os.environ.get("LOCAL_BROKER", "localhost")
LOCAL_PORT   = int(os.environ.get("LOCAL_PORT", 1883))
LOCAL_TOPIC  = "assembly-line/+/metrics"

# ── Configuration cloud (IoT Core) ─────────────────────────
IOT_ENDPOINT  = "aood9gt2q2oe5-ats.iot.eu-west-3.amazonaws.com"
IOT_CLIENT_ID = "greengrass-core-poste"
CERT_DIR      = "certs"
CLOUD_TOPIC   = "assembly-line/{id_poste}/metrics"

# ── Seuils d'alerte ────────────────────────────────────────
SEUILS = {
    "vibration":   2.0,   # m/s²
    "temperature": 80.0,  # °C
}

# ── Buffer JSONL ───────────────────────────────────────────
BUFFER_DIR  = "buffer"
BUFFER_FILE = f"{BUFFER_DIR}/events_buffer.jsonl"

# ── Compteurs ──────────────────────────────────────────────
stats = {"total": 0, "forwarded": 0, "buffered": 0}

iot_connection = None


# ════════════════════════════════════════════════════════════
# Circuit Breaker
# ════════════════════════════════════════════════════════════

class CircuitBreaker:
    CLOSED    = "CLOSED"
    OPEN      = "OPEN"
    HALF_OPEN = "HALF_OPEN"

    def __init__(self, failure_threshold=3, recovery_timeout=30):
        self.state             = self.CLOSED
        self.failure_count     = 0
        self.failure_threshold = failure_threshold
        self.recovery_timeout  = recovery_timeout
        self.last_failure_time = None

    def record_success(self):
        prev = self.state
        self.state         = self.CLOSED
        self.failure_count = 0
        if prev != self.CLOSED:
            print(f"[CB] {prev} → CLOSED ✅")

    def record_failure(self):
        self.failure_count += 1
        self.last_failure_time = time.time()
        if self.failure_count >= self.failure_threshold:
            if self.state != self.OPEN:
                print(f"[CB] {self.failure_count} échecs → OPEN (retry dans {self.recovery_timeout}s)")
            self.state = self.OPEN

    def can_attempt(self) -> bool:
        if self.state == self.CLOSED:
            return True
        if self.state == self.OPEN:
            elapsed = time.time() - (self.last_failure_time or 0)
            if elapsed >= self.recovery_timeout:
                self.state = self.HALF_OPEN
                print(f"[CB] OPEN → HALF_OPEN (test connexion IoT Core...)")
                return True
            remaining = int(self.recovery_timeout - elapsed)
            return False
        return True  # HALF_OPEN

    @property
    def label(self):
        icons = {self.CLOSED: "CLOSED", self.OPEN: "OPEN", self.HALF_OPEN: "HALF_OPEN"}
        return icons[self.state]


cb = CircuitBreaker(failure_threshold=3, recovery_timeout=30)


# ════════════════════════════════════════════════════════════
# Buffer JSONL
# ════════════════════════════════════════════════════════════

def buffer_event(event: dict):
    """Persiste un événement localement (survit aux redémarrages Docker)."""
    os.makedirs(BUFFER_DIR, exist_ok=True)
    event["buffered_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with open(BUFFER_FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps(event) + "\n")
    stats["buffered"] += 1
    print(f"[BUFFER] Bufferisé (statut={event.get('statut')}) — {stats['buffered']} en attente")


def flush_buffer():
    """Envoie tous les événements bufferisés vers IoT Core dans l'ordre chronologique."""
    if not os.path.exists(BUFFER_FILE):
        return
    with open(BUFFER_FILE, "r", encoding="utf-8") as f:
        lines = [l.strip() for l in f.readlines() if l.strip()]
    if not lines:
        return

    print(f"[BUFFER] Flush de {len(lines)} événements vers IoT Core...")
    sent = 0
    for line in lines:
        try:
            event = json.loads(line)
            topic = CLOUD_TOPIC.format(id_poste=event.get("id_poste", "unknown"))
            future, _ = iot_connection.publish(
                topic   = topic,
                payload = json.dumps(event),
                qos     = aws_mqtt.QoS.AT_LEAST_ONCE,
            )
            future.result(timeout=5)
            sent += 1
        except Exception as e:
            print(f"[BUFFER] Erreur flush ligne {sent + 1} : {e}")
            break

    # Conserver les lignes non envoyées
    remaining = lines[sent:]
    if remaining:
        with open(BUFFER_FILE, "w", encoding="utf-8") as f:
            f.write("\n".join(remaining) + "\n")
        print(f"[BUFFER] Flush partiel : {sent}/{len(lines)} envoyés")
    else:
        os.remove(BUFFER_FILE)
        print(f"[BUFFER] Flush complet : {sent} événements envoyés, buffer vidé")


# ════════════════════════════════════════════════════════════
# Thread de reconnexion proactive
# ════════════════════════════════════════════════════════════

def reconnect_loop():
    """
    Thread daemon : vérifie toutes les 10s si le circuit est OPEN.
    Si le recovery_timeout est écoulé, tente de reconnecter IoT Core
    et flush le buffer — même si aucun message MQTT local n'arrive.
    """
    while True:
        time.sleep(10)
        if cb.state == CircuitBreaker.OPEN:
            if cb.can_attempt():  # passe HALF_OPEN si timeout écoulé
                print("[CB] Thread reconnexion : tentative IoT Core...")
                if connect_iot_core():
                    cb.record_success()
                    flush_buffer()
                else:
                    cb.record_failure()


# ════════════════════════════════════════════════════════════
# IoT Core
# ════════════════════════════════════════════════════════════

def connect_iot_core() -> bool:
    """Tente une connexion IoT Core. Retourne True si succès."""
    global iot_connection
    print(f"[CLOUD] Connexion à IoT Core : {IOT_ENDPOINT}")
    try:
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
        future.result(timeout=10)
        print("[CLOUD] Connecté à IoT Core.")
        return True
    except Exception as e:
        print(f"[CLOUD] Connexion impossible : {e}")
        iot_connection = None
        return False


def forward_to_cloud(payload: dict, statut: str):
    """Envoie vers IoT Core si le circuit est fermé, sinon bufferise."""
    global iot_connection

    alert = {**payload, "statut": statut, "edge_filtered": True}
    topic = CLOUD_TOPIC.format(id_poste=payload.get("id_poste", "unknown"))

    # Circuit OPEN : buffer direct sans tentative
    if not cb.can_attempt():
        buffer_event(alert)
        return

    # Circuit CLOSED ou HALF_OPEN : tentative d'envoi
    try:
        if iot_connection is None:
            if not connect_iot_core():
                cb.record_failure()
                buffer_event(alert)
                return

        future, _ = iot_connection.publish(
            topic   = topic,
            payload = json.dumps(alert),
            qos     = aws_mqtt.QoS.AT_LEAST_ONCE,
        )
        future.result(timeout=5)

        print(f"[CLOUD] [{cb.label}] {statut} — vib={payload['vibration']} temp={payload['temperature']}")

        # Succès : fermer le circuit et flusher si on revenait de OPEN
        was_half_open = (cb.state == CircuitBreaker.HALF_OPEN)
        cb.record_success()
        if was_half_open:
            flush_buffer()

    except Exception as e:
        print(f"[CLOUD] Echec ({cb.failure_count + 1}/{cb.failure_threshold}) : {e}")
        cb.record_failure()
        buffer_event(alert)


# ════════════════════════════════════════════════════════════
# MQTT local
# ════════════════════════════════════════════════════════════

def get_statut(payload: dict) -> str:
    vib  = payload.get("vibration", 0)
    temp = payload.get("temperature", 0)
    if vib >= SEUILS["vibration"] * 1.25 or temp >= SEUILS["temperature"] * 1.2:
        return "CRITICAL"
    elif vib >= SEUILS["vibration"] or temp >= SEUILS["temperature"]:
        return "WARN"
    return "OK"


def on_local_message(client, userdata, msg):
    stats["total"] += 1
    try:
        payload = json.loads(msg.payload.decode())
        statut  = get_statut(payload)

        if statut in ("WARN", "CRITICAL"):
            stats["forwarded"] += 1
            forward_to_cloud(payload, statut)
        else:
            print(f"[EDGE] OK filtré — vib={payload['vibration']} temp={payload['temperature']}")

        if stats["total"] % 10 == 0:
            total = stats["total"]
            fwd   = stats["forwarded"]
            buf   = stats["buffered"]
            pct   = (1 - fwd / total) * 100 if total else 0
            print(f"\n[STATS] {total} mesures | {fwd} cloud | {buf} buffer | {pct:.0f}% filtrées | CB:{cb.label}\n")

    except Exception as e:
        print(f"[ERROR] {e}")


def on_local_connect(client, userdata, flags, rc):
    if rc == 0:
        print(f"[LOCAL] Connecté à Mosquitto ({LOCAL_BROKER}:{LOCAL_PORT})")
        client.subscribe(LOCAL_TOPIC)
        print(f"[LOCAL] Abonné à : {LOCAL_TOPIC}")
    else:
        print(f"[LOCAL] Echec connexion Mosquitto (rc={rc})")


# ════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════

def main():
    # 1. Connexion IoT Core — si échec, démarre en mode dégradé (OPEN)
    if not connect_iot_core():
        for _ in range(cb.failure_threshold):
            cb.record_failure()
        print(f"[CB] Démarrage en mode dégradé : {cb.label}")
    else:
        cb.record_success()

    # 2. Thread de reconnexion proactive (flush buffer même sans messages entrants)
    t = threading.Thread(target=reconnect_loop, daemon=True)
    t.start()

    # 3. Connexion Mosquitto local
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
        buf   = stats["buffered"]
        if total > 0:
            print(f"\n[BILAN] {total} mesures | {fwd} cloud | {buf} buffer | CB:{cb.label}")


if __name__ == "__main__":
    main()

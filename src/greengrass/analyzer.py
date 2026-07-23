"""
analyzer.py — Orchestrateur edge "smart-assembly-analyzer"
TinyML : Isolation Forest + Circuit Breaker + Buffer JSONL
Anti retry storm : backoff exponentiel + Full Jitter sur reconnect_loop()

Responsabilité : orchestration uniquement.
  - Reçoit les messages Mosquitto
  - Délègue la détection ML à detector.py (AnomalyDetector)
  - Applique les seuils statiques (WARN/CRITICAL)
  - Gère le circuit breaker et le buffer JSONL
  - Envoie vers IoT Core

Flux :
  publish_vibration_edge.py → Mosquitto:1883 → analyzer.py
                                                    ├── detector.update()  → ML (Isolation Forest)
                                                    ├── get_statut()       → seuils statiques
                                                    └── WARN/CRITICAL/ANOMALY
                                                          ├── CB CLOSED/HALF_OPEN → IoT Core
                                                          └── CB OPEN             → buffer JSONL
"""

import json
import os
import random
import time
import threading
import paho.mqtt.client as mqtt
from awsiot import mqtt_connection_builder
from awscrt import mqtt as aws_mqtt
from detector import AnomalyDetector

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

# ── Jitter config (Jour 34 — anti retry storm) ─────────────
RECONNECT_BASE_DELAY  = 1.0   # secondes
RECONNECT_MAX_DELAY   = 60.0  # plafond
RECONNECT_MAX_ATTEMPT = 8     # cap de l'exposant

# ── Buffer JSONL ───────────────────────────────────────────
BUFFER_DIR  = "buffer"
BUFFER_FILE = f"{BUFFER_DIR}/events_buffer.jsonl"

# ── Compteurs ──────────────────────────────────────────────
stats = {"total": 0, "forwarded": 0, "buffered": 0, "ml_anomalies": 0}

iot_connection = None

# ── Détecteur TinyML ───────────────────────────────────────
detector = AnomalyDetector(warmup_size=200, contamination=0.05, threshold=-0.1)


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
# Jitter (Jour 34 — anti retry storm)
# ════════════════════════════════════════════════════════════

def _backoff_jitter(attempt: int) -> float:
    """
    Full Jitter — pattern recommandé par AWS.
    sleep = random(0, min(cap, base * 2^attempt))

    Distribue les reconnexions aléatoirement dans la fenêtre de backoff,
    évitant que tous les postes reconnectent simultanément après une panne IoT Core.
    Source : https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
    """
    max_delay = min(RECONNECT_MAX_DELAY, RECONNECT_BASE_DELAY * (2 ** attempt))
    return random.uniform(0, max_delay)


# ════════════════════════════════════════════════════════════
# Thread de reconnexion proactive
# ════════════════════════════════════════════════════════════

def reconnect_loop():
    """
    Thread daemon : reconnexion proactive avec backoff exponentiel + Full Jitter.
    Remplace le time.sleep(10) fixe par _backoff_jitter(attempt)
    pour éviter le retry storm lors de la reconnexion simultanée de plusieurs postes.
    """
    attempt = 0
    while True:
        if cb.state in (CircuitBreaker.OPEN, CircuitBreaker.HALF_OPEN):
            if cb.can_attempt():  # passe HALF_OPEN si recovery_timeout écoulé
                delay = _backoff_jitter(attempt)
                print(f"[CB] Thread reconnexion — tentative {attempt + 1}, "
                      f"attente {delay:.1f}s (jitter, max={min(RECONNECT_MAX_DELAY, RECONNECT_BASE_DELAY * (2**attempt)):.0f}s)")
                time.sleep(delay)
                print("[CB] Tentative IoT Core...")
                if connect_iot_core():
                    cb.record_success()
                    attempt = 0  # reset après succès
                    flush_buffer()
                else:
                    cb.record_failure()
                    attempt = min(attempt + 1, RECONNECT_MAX_ATTEMPT)
            else:
                time.sleep(5)  # pas encore prêt à retenter
        else:
            attempt = 0  # CB fermé → reset le compteur de backoff
            time.sleep(5)


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

        # ── Détection ML (Isolation Forest) ────────────────
        ml_result = detector.update(payload)
        ml_detected = ml_result.get("ml_detected", False)
        ml_score    = ml_result.get("score", None)

        if ml_result["ready"] and ml_detected:
            stats["ml_anomalies"] += 1
            print(f"[ML] ANOMALY détectée — score={ml_score} "
                  f"vib={payload['vibration']} temp={payload['temperature']}")

        # ── Détection seuils statiques ──────────────────────
        statut = get_statut(payload)

        # Décision d'envoi : WARN/CRITICAL OU anomalie ML
        doit_envoyer = statut in ("WARN", "CRITICAL") or (ml_result["ready"] and ml_detected)

        if doit_envoyer:
            stats["forwarded"] += 1
            # Enrichir le payload avec les champs ML
            payload_enrichi = {
                **payload,
                "ml_detected":   ml_detected,
                "anomaly_score": ml_score,
                "ml_ready":      ml_result["ready"],
            }
            forward_to_cloud(payload_enrichi, statut if statut != "OK" else "ANOMALY")
        else:
            warmup_info = "" if ml_result["ready"] else f" [ML warm-up {len(detector._warmup_data)}/{detector.warmup_size}]"
            print(f"[EDGE] OK filtré — vib={payload['vibration']} temp={payload['temperature']}{warmup_info}")

        if stats["total"] % 10 == 0:
            total = stats["total"]
            fwd   = stats["forwarded"]
            buf   = stats["buffered"]
            ml    = stats["ml_anomalies"]
            pct   = (1 - fwd / total) * 100 if total else 0
            print(f"\n[STATS] {total} mesures | {fwd} cloud | {buf} buffer | "
                  f"{ml} ML anomalies | {pct:.0f}% filtrées | CB:{cb.label}\n")

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

    # 2. Thread de reconnexion proactive avec jitter (Jour 34)
    t = threading.Thread(target=reconnect_loop, daemon=True)
    t.start()
    print(f"[CB] Thread reconnect_loop démarré (Full Jitter — base={RECONNECT_BASE_DELAY}s, max={RECONNECT_MAX_DELAY}s)")

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

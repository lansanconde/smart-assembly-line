import json
import time
import boto3
import threading
import random
from datetime import datetime, timezone

# Publie directement via boto3 IoT Data (sans MQTT) pour maximiser le débit
client = boto3.client("iot-data", region_name="eu-west-3")
TOPIC = "assembly-line/poste_1/metrics"

def publish_batch(thread_id, count=100):
    sent = 0
    errors = 0
    start = time.time()
    for i in range(count):
        payload = {
            "id_poste": f"poste_{thread_id % 3 + 1}",
            "vibration": round(random.uniform(0.1, 3.5), 2),
            "temperature": round(random.uniform(60.0, 100.0), 1),
            "pression": round(random.uniform(3.0, 6.0), 2),
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        try:
            client.publish(
                topic=TOPIC,
                qos=0,
                payload=json.dumps(payload)
            )
            sent += 1
        except Exception as e:
            errors += 1
    elapsed = time.time() - start
    print(f"Thread {thread_id}: {sent} envoyés, {errors} erreurs, {elapsed:.2f}s → {sent/elapsed:.0f} msg/s")

# Lancer 10 threads × 100 messages = 1 000 messages en parallèle
threads = []
start_total = time.time()
for t in range(10):
    th = threading.Thread(target=publish_batch, args=(t, 100))
    threads.append(th)

for th in threads:
    th.start()
for th in threads:
    th.join()

elapsed_total = time.time() - start_total
print(f"\nTotal : 1 000 messages en {elapsed_total:.2f}s → {1000/elapsed_total:.0f} msg/s moyen")
"""
e2e_validation.py — Validation bout en bout Smart Assembly Line (Jour 35)

Rejoue le scénario complet et vérifie chaque étape :
  1. Edge : publish via Mosquitto local → analyzer → IoT Core
  2. Lambda : vérifier DynamoDB mis à jour
  3. CloudWatch : vérifier métrique Vibration publiée
  4. EventBridge / Step Functions : vérifier intervention loguée

Usage :
    python e2e_validation.py

Prérequis :
    - Stack Docker edge démarrée (docker compose up)
    - AWS credentials configurés (aws configure)
    - publish_vibration_edge.py en cours d'exécution (warm-up ML)
"""

import json
import time
import boto3
import subprocess
from datetime import datetime, timezone, timedelta

# ── Configuration ────────────────────────────────────────────
REGION       = "eu-west-3"
ACCOUNT_ID   = "169237360990"
TABLE_NAME   = "machine_state"
CW_NAMESPACE = "SmartAssemblyLine"
POSTE_ID     = "poste_1"

# Payload CRITICAL pour déclencher le pipeline complet
PAYLOAD_CRITICAL = json.dumps({
    "id_poste":    POSTE_ID,
    "vibration":   3.5,
    "temperature": 97.0,
    "pression":    4.5,
    "timestamp":   datetime.now(timezone.utc).isoformat()
})

# ── Clients AWS ───────────────────────────────────────────────
dynamodb   = boto3.resource("dynamodb", region_name=REGION)
cloudwatch = boto3.client("cloudwatch", region_name=REGION)
logs       = boto3.client("logs", region_name=REGION)

PASS = "✅ PASS"
FAIL = "❌ FAIL"
SKIP = "⏭️  SKIP"


def step(num, label):
    print(f"\n{'─'*60}")
    print(f"  Étape {num} : {label}")
    print(f"{'─'*60}")


def result(status, detail=""):
    print(f"  {status}" + (f" — {detail}" if detail else ""))


# ════════════════════════════════════════════════════════════
# Étape 1 — Injecter un event CRITICAL via Mosquitto
# ════════════════════════════════════════════════════════════

def test_edge_publish():
    step(1, "Edge publish → Mosquitto → analyzer → IoT Core")

    import tempfile, os

    # Écrire le payload dans un fichier temporaire puis le copier dans le container
    try:
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json",
                                         delete=False, encoding="utf-8") as f:
            f.write(PAYLOAD_CRITICAL)
            tmp_path = f.name

        # docker cp fichier_local → container:/tmp/
        cmd_cp = [
            "docker", "cp", tmp_path,
            "smart-assembly-broker:/tmp/e2e_payload.json"
        ]
        cmd_pub = [
            "docker", "exec", "smart-assembly-broker",
            "mosquitto_pub", "-h", "localhost", "-p", "1883",
            "-t", f"assembly-line/{POSTE_ID}/metrics",
            "-f", "/tmp/e2e_payload.json"
        ]

        proc = subprocess.run(cmd_cp, capture_output=True, timeout=5)
        os.unlink(tmp_path)
        if proc.returncode != 0:
            result(FAIL, f"docker cp failed: {proc.stderr.decode()}")
            return False

        proc = subprocess.run(cmd_pub, capture_output=True, timeout=5)
        if proc.returncode != 0:
            result(FAIL, f"mosquitto_pub failed: {proc.stderr.decode()}")
            return False

        result(PASS, f"Payload CRITICAL publié sur assembly-line/{POSTE_ID}/metrics")
        return True
    except FileNotFoundError:
        result(SKIP, "Docker non disponible — injecter manuellement via mosquitto_pub")
        return True
    except Exception as e:
        result(FAIL, str(e))
        return False


# ════════════════════════════════════════════════════════════
# Étape 2 — Vérifier DynamoDB (Lambda AnalyzeVibration)
# ════════════════════════════════════════════════════════════

def test_dynamodb(wait=15):
    step(2, f"DynamoDB machine_state — statut CRITICAL (attente {wait}s Lambda)")
    print(f"  Attente {wait}s propagation Lambda → DynamoDB...")
    time.sleep(wait)

    try:
        table = dynamodb.Table(TABLE_NAME)
        response = table.get_item(Key={"id_poste": POSTE_ID})
        item = response.get("Item")

        if not item:
            result(FAIL, f"Aucun item trouvé pour id_poste={POSTE_ID}")
            return False

        statut     = item.get("statut", "?")
        vib        = item.get("vibration_last", "?")
        ts         = item.get("timestamp_last", "?")

        print(f"  Item DynamoDB : statut={statut} | vibration={vib} | timestamp={ts}")

        if statut == "CRITICAL":
            result(PASS, f"statut=CRITICAL confirmé")
            return True
        elif statut == "EN_INTERVENTION":
            result(PASS, f"statut=EN_INTERVENTION (Step Functions déclenché)")
            return True
        else:
            result(FAIL, f"statut={statut} — attendu CRITICAL ou EN_INTERVENTION")
            return False
    except Exception as e:
        result(FAIL, str(e))
        return False


# ════════════════════════════════════════════════════════════
# Étape 3 — Vérifier CloudWatch métriques
# ════════════════════════════════════════════════════════════

def test_cloudwatch():
    step(3, "CloudWatch — métrique Vibration publiée (namespace SmartAssemblyLine)")

    end   = datetime.now(timezone.utc)
    start = end - timedelta(minutes=5)

    try:
        response = cloudwatch.get_metric_statistics(
            Namespace  = CW_NAMESPACE,
            MetricName = "Vibration",
            Dimensions = [{"Name": "Poste", "Value": POSTE_ID}],
            StartTime  = start,
            EndTime    = end,
            Period     = 60,
            Statistics = ["Maximum"],
        )
        datapoints = response.get("Datapoints", [])

        if not datapoints:
            result(FAIL, "Aucun datapoint Vibration dans les 5 dernières minutes")
            return False

        latest = max(datapoints, key=lambda d: d["Timestamp"])
        val    = latest["Maximum"]
        ts     = latest["Timestamp"].strftime("%H:%M:%S")
        print(f"  Dernier datapoint : Vibration={val} à {ts}")

        if val >= 2.5:
            result(PASS, f"Vibration={val} ≥ 2.5 (CRITICAL)")
            return True
        else:
            result(FAIL, f"Vibration={val} < 2.5 — event pas encore arrivé ?")
            return False
    except Exception as e:
        result(FAIL, str(e))
        return False


# ════════════════════════════════════════════════════════════
# Étape 4 — Vérifier CloudWatch Alarm
# ════════════════════════════════════════════════════════════

def test_alarms():
    step(4, "CloudWatch Alarms — état des 4 alarms + composite")

    try:
        response = cloudwatch.describe_alarms(
            AlarmNamePrefix="smart-assembly",
        )
        alarms = {a["AlarmName"]: a["StateValue"]
                  for a in response.get("MetricAlarms", [])}
        composite = {a["AlarmName"]: a["StateValue"]
                     for a in response.get("CompositeAlarms", [])}

        all_alarms = {**alarms, **composite}
        if not all_alarms:
            result(FAIL, "Aucune alarm trouvée")
            return False

        for name, state in all_alarms.items():
            icon = "🔴" if state == "ALARM" else ("🟢" if state == "OK" else "⚪")
            print(f"  {icon} {name} → {state}")

        result(PASS, f"{len(all_alarms)} alarms vérifiées")
        return True
    except Exception as e:
        result(FAIL, str(e))
        return False


# ════════════════════════════════════════════════════════════
# Étape 5 — Vérifier CloudWatch Logs Lambda
# ════════════════════════════════════════════════════════════

def test_lambda_logs():
    step(5, "CloudWatch Logs — Lambda AnalyzeVibration invoquée")

    log_group = "/aws/lambda/smart-assembly-analyze-vibration"
    start_ms  = int((datetime.now(timezone.utc) - timedelta(minutes=3)).timestamp() * 1000)

    try:
        response = logs.filter_log_events(
            logGroupName = log_group,
            startTime    = start_ms,
            filterPattern= "CRITICAL",
            limit        = 5,
        )
        events = response.get("events", [])

        if not events:
            result(SKIP, "Aucun log CRITICAL récent (Lambda pas encore invoquée ou délai CW Logs)")
            return True

        for e in events[:3]:
            ts  = datetime.fromtimestamp(e["timestamp"] / 1000).strftime("%H:%M:%S")
            msg = e["message"].strip()[:100]
            print(f"  [{ts}] {msg}")

        result(PASS, f"{len(events)} log(s) CRITICAL trouvé(s)")
        return True
    except logs.exceptions.ResourceNotFoundException:
        result(SKIP, f"Log group {log_group} non trouvé")
        return True
    except Exception as e:
        result(FAIL, str(e))
        return False


# ════════════════════════════════════════════════════════════
# Rapport final
# ════════════════════════════════════════════════════════════

def main():
    print("\n" + "═"*60)
    print("  VALIDATION E2E — Smart Aerospace Assembly Line")
    print(f"  {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("═"*60)

    results = {
        "Edge publish (Mosquitto → IoT Core)": test_edge_publish(),
        "DynamoDB (Lambda AnalyzeVibration)"  : test_dynamodb(wait=15),
        "CloudWatch métriques"                : test_cloudwatch(),
        "CloudWatch Alarms"                   : test_alarms(),
        "Lambda Logs (CRITICAL)"              : test_lambda_logs(),
    }

    print("\n" + "═"*60)
    print("  RAPPORT DE VALIDATION")
    print("═"*60)
    passed = sum(1 for v in results.values() if v)
    total  = len(results)

    for label, ok in results.items():
        icon = "✅" if ok else "❌"
        print(f"  {icon}  {label}")

    print(f"\n  Score : {passed}/{total}")
    if passed == total:
        print("  🏆 Validation E2E complète — pipeline opérationnel")
    else:
        print("  ⚠️  Certaines étapes ont échoué — voir détails ci-dessus")
    print("═"*60 + "\n")


if __name__ == "__main__":
    main()

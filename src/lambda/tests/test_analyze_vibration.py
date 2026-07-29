"""
Tests unitaires — analyze_vibration_handler.py (CI/CD)

Teste les vraies fonctions du handler Lambda :
  - evaluate_status()          : logique de seuils (pure, pas d'AWS)
  - lambda_handler()           : pipeline complet (DynamoDB + CloudWatch via moto)
  - publish_cloudwatch_metrics(): publication métriques (CloudWatch via moto)
"""

import json
import boto3
import pytest
from datetime import datetime, timezone
from moto import mock_aws

# sys.path et os.environ configurés dans conftest.py (chargé automatiquement par pytest)
import handler as handler  # noqa: E402


# ── Helper ───────────────────────────────────────────────────

def make_event(vibration=1.2, temperature=65.0, pression=3.5,
               id_poste="poste_1", **kwargs) -> dict:
    return {
        "id_poste": id_poste,
        "vibration": vibration,
        "temperature": temperature,
        "pression": pression,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        **kwargs,
    }


# ═══════════════════════════════════════════════════════════════
# 1 — evaluate_status() : logique pure, pas d'AWS
# ═══════════════════════════════════════════════════════════════

class TestEvaluateStatus:
    """Teste la vraie fonction evaluate_status du handler."""

    def test_ok_nominal(self):
        status, anomalie = handler.evaluate_status(make_event(vibration=1.0))
        assert status == "OK"
        assert anomalie is None

    def test_warn_vibration(self):
        status, anomalie = handler.evaluate_status(make_event(vibration=2.0))
        assert status == "WARN"
        assert anomalie == "VIBRATION"

    def test_critical_vibration(self):
        status, anomalie = handler.evaluate_status(make_event(vibration=3.1))
        assert status == "CRITICAL"
        assert anomalie == "VIBRATION"

    def test_critical_temperature(self):
        """Temperature ≥ 95 → CRITICAL même si vibration OK."""
        status, anomalie = handler.evaluate_status(
            make_event(vibration=1.0, temperature=97.0)
        )
        assert status == "CRITICAL"
        assert anomalie == "TEMPERATURE"

    def test_warn_temperature(self):
        status, anomalie = handler.evaluate_status(
            make_event(vibration=1.0, temperature=82.0)
        )
        assert status == "WARN"
        assert anomalie == "TEMPERATURE"

    def test_critical_pression(self):
        status, anomalie = handler.evaluate_status(
            make_event(vibration=1.0, temperature=65.0, pression=7.0)
        )
        assert status == "CRITICAL"
        assert anomalie == "PRESSION"

    def test_critical_priority_over_warn(self):
        """CRITICAL a la priorité — retourne dès le premier CRITICAL trouvé."""
        status, anomalie = handler.evaluate_status(
            make_event(vibration=3.1, temperature=97.0)
        )
        assert status == "CRITICAL"

    def test_missing_id_poste_raises(self):
        """id_poste manquant → ValueError dans lambda_handler."""
        # evaluate_status ne lève pas d'erreur (pas son rôle)
        # c'est lambda_handler qui valide id_poste
        status, _ = handler.evaluate_status({"vibration": 1.0})
        assert status == "OK"  # evaluate_status ne plante pas


# ═══════════════════════════════════════════════════════════════
# 2 — lambda_handler() : pipeline complet avec moto
# ═══════════════════════════════════════════════════════════════

@pytest.fixture
def aws_moto():
    """Démarre moto et crée les ressources AWS nécessaires."""
    with mock_aws():
        # Patcher les clients module-level du handler avec des clients moto
        handler.dynamodb = boto3.resource("dynamodb", region_name="eu-west-3")
        handler.cloudwatch = boto3.client("cloudwatch", region_name="eu-west-3")

        # Créer la table DynamoDB
        table = handler.dynamodb.create_table(
            TableName="machine_state",
            KeySchema=[{"AttributeName": "id_poste", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "id_poste", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        yield {"table": table, "cloudwatch": handler.cloudwatch}


class TestLambdaHandler:
    """Teste le handler complet avec DynamoDB et CloudWatch mockés."""

    def test_handler_ok_writes_dynamodb(self, aws_moto):
        """Payload nominal → DynamoDB statut=OK."""
        event = make_event(vibration=1.0, temperature=65.0)
        result = handler.lambda_handler(event, None)

        assert result["statusCode"] == 200
        assert result["statut"] == "OK"

        item = aws_moto["table"].get_item(Key={"id_poste": "poste_1"})["Item"]
        assert item["statut"] == "OK"
        assert item["vibration_last"] == "1.0"

    def test_handler_critical_writes_dynamodb(self, aws_moto):
        """Payload CRITICAL → DynamoDB statut=CRITICAL."""
        event = make_event(vibration=3.1, temperature=72.0)
        result = handler.lambda_handler(event, None)

        assert result["statut"] == "CRITICAL"

        item = aws_moto["table"].get_item(Key={"id_poste": "poste_1"})["Item"]
        assert item["statut"] == "CRITICAL"
        assert item["anomalie_type"] == "VIBRATION"

    def test_handler_missing_id_poste_raises(self, aws_moto):
        """id_poste manquant → ValueError."""
        with pytest.raises(ValueError, match="id_poste"):
            handler.lambda_handler({"vibration": 3.0}, None)

    def test_handler_overwrites_previous_state(self, aws_moto):
        """Deux events successifs → seul le dernier est dans DynamoDB."""
        handler.lambda_handler(make_event(vibration=3.1), None)  # CRITICAL
        handler.lambda_handler(make_event(vibration=1.0), None)  # OK

        item = aws_moto["table"].get_item(Key={"id_poste": "poste_1"})["Item"]
        assert item["statut"] == "OK"  # écrasé par le second event

    def test_handler_returns_id_poste(self, aws_moto):
        """Le handler retourne l'id_poste dans la réponse."""
        event = make_event(id_poste="poste_42", vibration=1.0)
        result = handler.lambda_handler(event, None)
        assert result["id_poste"] == "poste_42"


# ═══════════════════════════════════════════════════════════════
# 3 — publish_cloudwatch_metrics() : métriques avec moto
# ═══════════════════════════════════════════════════════════════

class TestPublishCloudWatchMetrics:
    """Teste que les métriques sont bien publiées dans CloudWatch."""

    def test_all_metrics_published(self, aws_moto):
        """Vibration, Temperature, Pression et MessageCount sont publiés."""
        event = make_event(vibration=3.1, temperature=72.0, pression=4.1)
        handler.publish_cloudwatch_metrics(event, "CRITICAL")

        cw = aws_moto["cloudwatch"]
        metrics = cw.list_metrics(Namespace="SmartAssemblyLine")["Metrics"]
        names = {m["MetricName"] for m in metrics}

        assert "Vibration" in names
        assert "Temperature" in names
        assert "Pression" in names
        assert "MessageCount" in names

    def test_anomaly_score_published_when_present(self, aws_moto):
        """AnomalyScore publié si ml_detected présent dans le payload."""
        event = make_event(vibration=1.0, ml_detected=True, anomaly_score=-0.15)
        handler.publish_cloudwatch_metrics(event, "OK")

        cw = aws_moto["cloudwatch"]
        metrics = cw.list_metrics(Namespace="SmartAssemblyLine")["Metrics"]
        names = {m["MetricName"] for m in metrics}

        assert "AnomalyScore" in names

    def test_cloudwatch_does_not_raise_on_error(self, aws_moto):
        """Une erreur CloudWatch ne fait pas planter le pipeline."""
        from unittest.mock import patch, MagicMock
        mock_cw = MagicMock()
        mock_cw.put_metric_data.side_effect = Exception("CloudWatch down")

        with patch.object(handler, "cloudwatch", mock_cw):
            # Ne doit pas lever d'exception
            handler.publish_cloudwatch_metrics(make_event(), "OK")

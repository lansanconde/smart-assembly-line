"""
detector.py — Module TinyML : détection d'anomalies edge
Isolation Forest

Responsabilité unique : feature engineering + warm-up + entraînement + inférence.
Aucune dépendance MQTT, IoT Core ou circuit breaker — testable indépendamment.

Interface publique :
    detector = AnomalyDetector(warmup_size=200)
    result   = detector.update(payload)
    # result = {"ready": False}                                  — pendant warm-up
    # result = {"ready": True, "ml_detected": bool, "score": float}  — après
"""

import numpy as np
import joblib
import os
from collections import deque
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler



# ── Noms des features (pour model card et logs) ────────────
FEATURE_NAMES = [
    "vibration",
    "temperature",
    "pression",
    "vib_mean_10",
    "vib_std_10",
    "vib_max_10",
    "temp_mean_10",
    "temp_std_10",
    "vib_x_temp",   # corrélation instantanée
    "vib_cv",       # coefficient de variation (instabilité relative)
]


class AnomalyDetector:
    """
    Détecteur d'anomalies basé sur Isolation Forest.

    Cycle de vie :
      1. WARM-UP  : collecte les `warmup_size` premières mesures
      2. TRAINING : entraîne le modèle sur ces mesures (< 1s)
      3. INFÉRENCE: prédit NORMAL ou ANOMALY sur chaque nouvelle mesure

    Usage :
        detector = AnomalyDetector(warmup_size=200)
        result = detector.update(payload)
        if result["ready"] and result["ml_detected"]:
            print(f"Anomalie ML détectée — score={result['score']}")
    """

    def __init__(
        self,
        warmup_size: int = 200,
        contamination: float = 0.05,
        threshold: float = -0.1,
        window_size: int = 10,
    ):
        self.warmup_size   = warmup_size
        self.contamination = contamination
        self.threshold     = threshold   # score < threshold → anomalie

        self._window       = deque(maxlen=window_size)
        self._warmup_data  = []
        self._model        = None
        self._scaler       = None
        self.ready         = False
        self.n_train       = 0

    # ── API publique ────────────────────────────────────────

    def update(self, payload: dict) -> dict:
        """
        Ingère une nouvelle mesure.
        Retourne {"ready": False} pendant le warm-up,
        puis {"ready": True, "ml_detected": bool, "score": float}.
        """
        features = self._extract_features(payload)
        if features is None:
            return {"ready": False}

        if not self.ready:
            return self._warmup_step(features)

        return self._predict(features)

    def save(self, path: str = "models/model_current.pkl"):
        """Sérialise le modèle entraîné (joblib)."""
        if not self.ready:
            print("[ML] Impossible de sauvegarder : modèle non encore entraîné.")
            return
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        joblib.dump({
            "model":         self._model,
            "scaler":        self._scaler,
            "warmup_size":   self.warmup_size,
            "contamination": self.contamination,
            "threshold":     self.threshold,
            "n_train":       self.n_train,
            "features":      FEATURE_NAMES,
        }, path)
        print(f"[ML] Modèle sauvegardé → {path} ({os.path.getsize(path) // 1024} Ko)")

    @classmethod
    def load(cls, path: str = "models/model_current.pkl") -> "AnomalyDetector":
        """Charge un modèle sérialisé depuis le disque."""
        data = joblib.load(path)
        detector = cls(
            warmup_size   = data["warmup_size"],
            contamination = data["contamination"],
            threshold     = data["threshold"],
        )
        detector._model   = data["model"]
        detector._scaler  = data["scaler"]
        detector.n_train  = data["n_train"]
        detector.ready    = True
        print(f"[ML] Modèle chargé depuis {path} (entraîné sur {detector.n_train} mesures)")
        return detector

    # ── Feature engineering ─────────────────────────────────

    def _extract_features(self, payload: dict):
        """
        Construit le vecteur de features à partir du payload courant
        et de la fenêtre glissante des 10 dernières mesures.
        Retourne None si la fenêtre n'est pas encore suffisante.
        """
        vib  = float(payload.get("vibration",   0))
        temp = float(payload.get("temperature", 0))
        pres = float(payload.get("pression",    0))

        self._window.append({"vib": vib, "temp": temp})

        if len(self._window) < 2:
            return None  # pas encore assez de données pour les rolling stats

        vibs  = [w["vib"]  for w in self._window]
        temps = [w["temp"] for w in self._window]

        vib_mean = float(np.mean(vibs))
        vib_std  = float(np.std(vibs))
        vib_max  = float(np.max(vibs))
        temp_mean = float(np.mean(temps))
        temp_std  = float(np.std(temps))
        vib_cv   = vib_std / vib_mean if vib_mean > 0 else 0.0

        return [
            vib, temp, pres,
            vib_mean, vib_std, vib_max,
            temp_mean, temp_std,
            vib * temp,
            vib_cv,
        ]

    # ── Warm-up et entraînement ─────────────────────────────

    def _warmup_step(self, features: list) -> dict:
        self._warmup_data.append(features)
        collected = len(self._warmup_data)

        if collected % 50 == 0:
            print(f"[ML] Warm-up : {collected}/{self.warmup_size} mesures collectées...")

        if collected >= self.warmup_size:
            self._train()

        return {"ready": False}

    def _train(self):

        print(f"[ML] Entraînement Isolation Forest sur {len(self._warmup_data)} mesures...")
        X = np.array(self._warmup_data)

        self._scaler = StandardScaler()
        X_scaled = self._scaler.fit_transform(X)

        self._model = IsolationForest(
            n_estimators  = 100,
            contamination = self.contamination,
            max_samples   = "auto",
            random_state  = 42,
        )
        self._model.fit(X_scaled)
        self.n_train = len(self._warmup_data)
        self.ready   = True

        # Évaluation rapide sur les données d'entraînement
        preds = self._model.predict(X_scaled)
        fp_rate = (preds == -1).sum() / len(preds)
        print(f"[ML] Modèle prêt. Taux faux positifs (train) : {fp_rate:.1%} "
              f"(cible < {self.contamination:.0%})")
        print(f"[ML] Seuil décision : {self.threshold} | Features : {len(FEATURE_NAMES)}")

    # ── Inférence ───────────────────────────────────────────

    def _predict(self, features: list) -> dict:
        X = np.array([features])
        X_scaled  = self._scaler.transform(X)
        score     = float(self._model.decision_function(X_scaled)[0])
        ml_detected = score < self.threshold
        return {
            "ready":       True,
            "ml_detected": ml_detected,
            "score":       round(score, 4),
        }

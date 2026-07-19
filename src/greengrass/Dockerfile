# ============================================================
# Dockerfile — smart-assembly-analyzer (component edge)
# Edge Computing
# TinyML : Isolation Forest
# ============================================================

FROM python:3.11-slim

WORKDIR /app

# Dépendances Python
RUN pip install --no-cache-dir \
    paho-mqtt==1.6.1 \
    awsiotsdk \
    scikit-learn \
    numpy \
    joblib

# Code du component
COPY analyzer.py .
COPY detector.py .

# Les certs sont montés en volume au runtime (pas copiés dans l'image)
# → src/greengrass/certs/ monté dans /app/certs/
# Le buffer est monté en volume : src/greengrass/buffer/ → /app/buffer/
# Les modèles sérialisés (Semaine 7) : src/greengrass/models/ → /app/models/

CMD ["python", "-u", "analyzer.py"]

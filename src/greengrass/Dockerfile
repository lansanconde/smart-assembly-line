# ============================================================
# Dockerfile — smart-assembly-analyzer (component edge)
# Jour 30 — Edge Computing
# ============================================================

FROM python:3.11-slim

WORKDIR /app

# Dépendances Python
RUN pip install --no-cache-dir \
    paho-mqtt==1.6.1 \
    awsiotsdk

# Code du component
COPY analyzer.py .

# Les certs sont montés en volume au runtime (pas copiés dans l'image)
# → src/greengrass/certs/ monté dans /app/certs/

CMD ["python", "-u", "analyzer.py"]

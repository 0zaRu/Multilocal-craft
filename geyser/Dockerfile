# Geyser bajo demanda: Java (para Geyser Standalone) + Python (para el vigilante)
ARG JAVA_VERSION=25
FROM eclipse-temurin:${JAVA_VERSION}-jre
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 \
 && rm -rf /var/lib/apt/lists/*
COPY geyser-bajo-demanda.py /app/geyser-bajo-demanda.py
ENTRYPOINT ["python3", "-u", "/app/geyser-bajo-demanda.py", "--java", "java", "--dir", "/data/geyser", "--key", "/data/plugins/floodgate/key.pem"]

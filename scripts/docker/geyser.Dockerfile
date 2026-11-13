# Geyser (conexión para Bedrock): Java para Geyser Standalone + Python para el vigilante.
# GEYSER_MODE=ondemand|siempre y MLC_IP (IP de ZeroTier que se anuncia) llegan desde docker-compose.yml.
# MLC_ANUNCIAR (opcional): dirección que se anuncia a Bedrock (p. ej. el dominio público); si no, MLC_IP.
# MLC_PROXY_PROTOCOL (opcional, no vacío) = el servidor exige PROXY protocol (proxy Gate delante, solo central).
ARG JAVA_VERSION=25
FROM eclipse-temurin:${JAVA_VERSION}-jre
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 \
 && rm -rf /var/lib/apt/lists/*
COPY scripts/geyser-bajo-demanda.py /app/geyser-bajo-demanda.py
ENTRYPOINT ["sh", "-c", "A=${MLC_ANUNCIAR:-$MLC_IP}; exec python3 -u /app/geyser-bajo-demanda.py --java java --dir /data/geyser --key /data/plugins/floodgate/key.pem --java-address mc-server ${A:+--anunciar $A} ${MLC_PROXY_PROTOCOL:+--proxy-protocol} $( [ \"$GEYSER_MODE\" = siempre ] && echo --siempre )"]

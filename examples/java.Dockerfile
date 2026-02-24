# Example: Adding Java 21 to safe-ai
#
# Build: docker build -f examples/java.Dockerfile -t safe-ai-java .
# Use:   Replace sandbox image in docker-compose.override.yaml

FROM safe-ai-sandbox:latest

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       gpg \
       apt-transport-https \
    && curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
       | gpg --dearmor -o /usr/share/keyrings/adoptium.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb noble main" \
       > /etc/apt/sources.list.d/adoptium.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends temurin-21-jdk \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"

USER dev
WORKDIR /workspace

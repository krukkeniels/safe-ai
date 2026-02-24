# Example: Adding Java 21 to a Codex sandbox (chained build)
#
# Requires: safe-ai-codex:latest (build codex.Dockerfile first)
# Build:    docker build -f examples/codex-java.Dockerfile -t safe-ai-codex-java .
# Use:      Replace sandbox image in docker-compose.override.yaml
#
# Layer chain: safe-ai-sandbox → safe-ai-node → safe-ai-codex → safe-ai-codex-java
#
# This demonstrates chaining: instead of re-installing Node.js and Codex,
# this image extends safe-ai-codex and only adds Java 21.
#
# Set your API key via environment:
#   environment:
#     - OPENAI_API_KEY=${OPENAI_API_KEY}

FROM safe-ai-codex:latest

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

# Example: Adding OpenAI Codex CLI to safe-ai
#
# Requires: safe-ai-node:latest (build node.Dockerfile first)
# Build:    docker build -f examples/codex.Dockerfile -t safe-ai-codex .
# Use:      Replace sandbox image in docker-compose.override.yaml
#
# Layer chain: safe-ai-sandbox → safe-ai-node → safe-ai-codex
#
# Set your API key via environment:
#   environment:
#     - OPENAI_API_KEY=${OPENAI_API_KEY}
#
# Mount your Codex config at runtime (do not bake into image):
#   volumes:
#     - ./codex-config.toml:/home/dev/.codex/config.toml:ro
#
# See examples/codex-config.toml for a starter configuration.

FROM safe-ai-node:latest

USER root

RUN npm install -g @openai/codex

# Prepare config directory for runtime volume mount
RUN mkdir -p /home/dev/.codex \
    && chown dev:dev /home/dev/.codex

USER dev
WORKDIR /workspace

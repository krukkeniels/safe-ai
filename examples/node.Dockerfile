# Shared Node.js 22 runtime layer for safe-ai
#
# Build: docker build -f examples/node.Dockerfile -t safe-ai-node .
# Use:   Base image for Node.js tools (Claude Code, Codex, etc.)
#
# Layer chain: safe-ai-sandbox → safe-ai-node

FROM safe-ai-sandbox:latest

USER root

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

USER dev
WORKDIR /workspace

# Example: Adding Claude Code CLI to safe-ai
#
# Requires: safe-ai-node:latest (build node.Dockerfile first)
# Build:    docker build -f examples/claude-code.Dockerfile -t safe-ai-claude .
# Use:      Replace sandbox image in docker-compose.override.yaml
#
# Layer chain: safe-ai-sandbox → safe-ai-node → safe-ai-claude
#
# Set your API key via environment:
#   environment:
#     - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}

FROM safe-ai-node:latest

USER root

RUN npm install -g @anthropic-ai/claude-code

WORKDIR /workspace
# Note: do NOT set USER dev here — the base sandbox entrypoint
# needs root to start sshd, then drops to dev for SSH sessions.

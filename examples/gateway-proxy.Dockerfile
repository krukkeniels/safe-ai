# Example: Proxy with org gateway token baked in
#
# Orgs build this image with their gateway credentials and distribute
# it to developers. The token is never exposed in .env or docker-compose.
#
# Build:
#   docker build -f examples/gateway-proxy.Dockerfile \
#     --build-arg SAFE_AI_GATEWAY_DOMAIN=llm-gateway.example.com \
#     --build-arg SAFE_AI_GATEWAY_TOKEN=org-secret-here \
#     -t org-registry/safe-ai-proxy:latest .
#
# Use: Replace proxy image in docker-compose.override.yaml:
#   services:
#     proxy:
#       image: org-registry/safe-ai-proxy:latest
#
# The proxy injects an X-Safe-AI-Token header on requests to the
# gateway domain. The agent inside the sandbox never sees the token.

FROM safe-ai-proxy:latest

ARG SAFE_AI_GATEWAY_DOMAIN
ARG SAFE_AI_GATEWAY_TOKEN

RUN if [ -n "$SAFE_AI_GATEWAY_DOMAIN" ] && [ -n "$SAFE_AI_GATEWAY_TOKEN" ]; then \
      printf 'domain=%s\ntoken=%s\n' \
        "$SAFE_AI_GATEWAY_DOMAIN" "$SAFE_AI_GATEWAY_TOKEN" \
        > /etc/safe-ai/gateway.conf && \
      chmod 600 /etc/safe-ai/gateway.conf; \
    else \
      echo "ERROR: Both SAFE_AI_GATEWAY_DOMAIN and SAFE_AI_GATEWAY_TOKEN required" >&2; \
      exit 1; \
    fi

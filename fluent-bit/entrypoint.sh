#!/bin/sh
set -eu

# Parse SAFE_AI_LOKI_URL into components for Fluent Bit.
# Format: https://user:pass@host:port  or  http://host:port
# Defaults to local Loki container when unset.

URL="${SAFE_AI_LOKI_URL:-http://loki:3100}"

# Extract scheme
SCHEME="${URL%%://*}"

# Strip scheme
REMAINDER="${URL#*://}"

# Extract credentials if present (user:pass@host)
SAFE_AI_LOKI_USER=""
SAFE_AI_LOKI_PASS=""
if echo "$REMAINDER" | grep -q '@'; then
    CREDS="${REMAINDER%%@*}"
    REMAINDER="${REMAINDER#*@}"
    SAFE_AI_LOKI_USER="${CREDS%%:*}"
    SAFE_AI_LOKI_PASS="${CREDS#*:}"
fi

# Extract host and port
SAFE_AI_LOKI_HOST="${REMAINDER%%:*}"
SAFE_AI_LOKI_PORT="${REMAINDER#*:}"
# Remove trailing path if any
SAFE_AI_LOKI_HOST="${SAFE_AI_LOKI_HOST%%/*}"
SAFE_AI_LOKI_PORT="${SAFE_AI_LOKI_PORT%%/*}"

# Default port based on scheme
if [ "$SAFE_AI_LOKI_HOST" = "$SAFE_AI_LOKI_PORT" ]; then
    # No port specified
    if [ "$SCHEME" = "https" ]; then
        SAFE_AI_LOKI_PORT=443
    else
        SAFE_AI_LOKI_PORT=3100
    fi
fi

# TLS based on scheme
if [ "$SCHEME" = "https" ]; then
    SAFE_AI_LOKI_TLS="On"
else
    SAFE_AI_LOKI_TLS="Off"
fi

# Hostname for log labels
SAFE_AI_HOSTNAME="${SAFE_AI_HOSTNAME:-$(hostname)}"

export SAFE_AI_LOKI_HOST SAFE_AI_LOKI_PORT SAFE_AI_LOKI_TLS
export SAFE_AI_LOKI_USER SAFE_AI_LOKI_PASS SAFE_AI_HOSTNAME

echo "[safe-ai] Fluent Bit shipping to ${SCHEME}://${SAFE_AI_LOKI_HOST}:${SAFE_AI_LOKI_PORT}"

exec /fluent-bit/bin/fluent-bit -c /fluent-bit/etc/fluent-bit.conf

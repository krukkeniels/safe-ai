#!/usr/bin/env bash
set -euo pipefail

# safe-ai smoke test
# Verifies sandbox isolation is working correctly.
# Requires: docker compose up -d (containers must be running)

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAIL=$((FAIL + 1)); }

CONTAINER="safe-ai-sandbox"

# Check containers are running
if ! docker compose ps --status running | grep -q sandbox; then
    echo "Error: sandbox container is not running."
    echo "Start it first: docker compose up -d"
    exit 1
fi

echo "safe-ai smoke test"
echo "==================="
echo ""

# Test 1: Allowlisted domain resolves (any HTTP response = connectivity works)
HTTP_CODE=$(docker exec "$CONTAINER" curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://api.anthropic.com 2>/dev/null || true)
if [ -n "$HTTP_CODE" ] && [ "$HTTP_CODE" != "000" ]; then
    pass "Allowlisted domain (api.anthropic.com) is reachable (HTTP $HTTP_CODE)"
else
    fail "Allowlisted domain (api.anthropic.com) is NOT reachable"
fi

# Test 2: Blocked domain is denied
if docker exec "$CONTAINER" curl -sf --max-time 10 -o /dev/null https://example.com 2>/dev/null; then
    fail "Blocked domain (example.com) is reachable — isolation broken!"
else
    pass "Blocked domain (example.com) is denied"
fi

# Test 3: Read-only root filesystem
if docker exec "$CONTAINER" touch /etc/test-readonly 2>/dev/null; then
    fail "Root filesystem is writable — should be read-only!"
    docker exec "$CONTAINER" rm -f /etc/test-readonly 2>/dev/null
else
    pass "Root filesystem is read-only"
fi

# Test 4: /tmp exists and is writable (tmpfs)
if docker exec "$CONTAINER" touch /tmp/test-tmpfs 2>/dev/null; then
    pass "/tmp is writable (tmpfs)"
    docker exec "$CONTAINER" rm -f /tmp/test-tmpfs 2>/dev/null
else
    fail "/tmp is NOT writable"
fi

# Test 5: Dangerous capabilities dropped (can't mount filesystems)
if docker exec "$CONTAINER" mount -t tmpfs none /mnt 2>/dev/null; then
    fail "Capabilities not dropped — mount succeeded!"
else
    pass "Dangerous capabilities dropped (mount denied)"
fi

# Test 6: gVisor runtime (if enabled)
RUNTIME=$(docker inspect --format='{{.HostConfig.Runtime}}' "$CONTAINER" 2>/dev/null || echo "unknown")
if [ "$RUNTIME" = "runsc" ]; then
    pass "gVisor runtime active (kernel-level isolation)"
elif [ "${SAFE_AI_RUNTIME:-runc}" = "runsc" ]; then
    fail "gVisor requested (SAFE_AI_RUNTIME=runsc) but container running with: $RUNTIME"
else
    echo -e "INFO: gVisor not enabled (using ${RUNTIME:-runc}). Set SAFE_AI_RUNTIME=runsc for kernel-level isolation."
fi

# Test 7: Audit logging (only when logging profile is active)
if docker compose ps --status running 2>/dev/null | grep -q fluent-bit; then
    # Fluent Bit health check
    FB_HEALTH=$(docker exec safe-ai-fluent-bit wget -q -O - http://localhost:2020/api/v1/health 2>/dev/null || true)
    if echo "$FB_HEALTH" | grep -qi "ok"; then
        pass "Fluent Bit is healthy"
    else
        fail "Fluent Bit health check failed"
    fi

    # Verify JSON-structured access log
    # Trigger a request to generate a log entry
    docker exec "$CONTAINER" curl -sf --max-time 5 -o /dev/null https://api.anthropic.com 2>/dev/null || true
    sleep 2
    LOG_LINE=$(docker exec safe-ai-proxy tail -1 /var/log/squid/access.log 2>/dev/null || true)
    if echo "$LOG_LINE" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        pass "Squid access log is valid JSON"
    elif echo "$LOG_LINE" | grep -q '"squid_action"'; then
        pass "Squid access log is JSON-structured"
    else
        fail "Squid access log is not JSON-structured"
    fi

    # Check Loki has data (only if local Loki is running)
    if docker compose ps --status running 2>/dev/null | grep -q loki; then
        LOKI_QUERY=$(docker exec safe-ai-loki wget -q -O - 'http://localhost:3100/loki/api/v1/query?query={job="safe-ai"}&limit=1' 2>/dev/null || true)
        if echo "$LOKI_QUERY" | grep -q '"result"'; then
            pass "Loki is receiving logs"
        else
            fail "Loki has no safe-ai logs"
        fi
    fi
else
    echo "INFO: Audit logging not enabled (--profile logging). Skipping logging tests."
fi

# Summary
echo ""
echo "==================="
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

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

pass() { echo -e "${GREEN}PASS${NC}: $1"; ((PASS++)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; ((FAIL++)); }

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

# Test 1: Allowlisted domain resolves
if docker exec "$CONTAINER" curl -sf --max-time 10 -o /dev/null https://api.anthropic.com 2>/dev/null; then
    pass "Allowlisted domain (api.anthropic.com) is reachable"
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

# Test 5: No capabilities (can't change ownership)
if docker exec "$CONTAINER" chown root:root /tmp 2>/dev/null; then
    fail "Capabilities not dropped — chown succeeded!"
else
    pass "Capabilities dropped (chown denied)"
fi

# Summary
echo ""
echo "==================="
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

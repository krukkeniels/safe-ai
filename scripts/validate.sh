#!/usr/bin/env bash
set -euo pipefail

FAIL=0
WARN=0

echo "=== safe-ai Security Baseline Validation ==="
echo ""

SANDBOX=$(docker ps --filter "name=sandbox" --format '{{.Names}}' | head -1)
PROXY=$(docker ps --filter "name=proxy" --format '{{.Names}}' | head -1)

if [ -z "$SANDBOX" ] || [ -z "$PROXY" ]; then
    echo "ERROR: sandbox or proxy container not running"
    exit 1
fi

echo -n "1. Read-only root filesystem... "
RO=$(docker inspect "$SANDBOX" --format '{{.HostConfig.ReadonlyRootfs}}')
if [ "$RO" = "true" ]; then echo "PASS"; else echo "FAIL"; FAIL=1; fi

echo -n "2. Capabilities (no extra caps)... "
CAPS=$(docker inspect "$SANDBOX" --format '{{.HostConfig.CapAdd}}')
EXPECTED="[SETUID SETGID SYS_CHROOT NET_BIND_SERVICE CHOWN]"
if [ "$CAPS" = "$EXPECTED" ]; then echo "PASS"; else echo "FAIL (got: $CAPS)"; FAIL=1; fi

echo -n "3. No-new-privileges... "
SECOPT=$(docker inspect "$SANDBOX" --format '{{.HostConfig.SecurityOpt}}')
if echo "$SECOPT" | grep -q "no-new-privileges"; then echo "PASS"; else echo "FAIL"; FAIL=1; fi

echo -n "4. Seccomp profile active... "
if echo "$SECOPT" | grep -q "seccomp"; then echo "PASS"; else echo "FAIL"; FAIL=1; fi

echo -n "5. Internal network isolation... "
NETWORKS=$(docker inspect "$SANDBOX" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}')
if echo "$NETWORKS" | grep -q "internal" && ! echo "$NETWORKS" | grep -q "external"; then
    echo "PASS"
else
    echo "FAIL (networks: $NETWORKS)"
    FAIL=1
fi

echo -n "6. PID limit enforced... "
PID_LIMIT=$(docker inspect "$SANDBOX" --format '{{.HostConfig.PidsLimit}}')
if [ "$PID_LIMIT" -le 512 ] && [ "$PID_LIMIT" -gt 0 ]; then
    echo "PASS (limit: $PID_LIMIT)"
else
    echo "FAIL (limit: $PID_LIMIT)"
    FAIL=1
fi

echo -n "7. Proxy DAC_OVERRIDE removed... "
PROXY_CAPS=$(docker inspect "$PROXY" --format '{{.HostConfig.CapAdd}}')
if echo "$PROXY_CAPS" | grep -q "DAC_OVERRIDE"; then
    echo "WARN (DAC_OVERRIDE still present)"
    WARN=$((WARN + 1))
else
    echo "PASS"
fi

echo -n "8. No dangerous override file... "
if [ -f "docker-compose.override.yaml" ]; then
    if grep -qE "privileged|docker.sock|SYS_ADMIN|SYS_PTRACE" docker-compose.override.yaml 2>/dev/null; then
        echo "FAIL (dangerous overrides detected)"
        FAIL=1
    else
        echo "WARN (override file exists, review manually)"
        WARN=$((WARN + 1))
    fi
else
    echo "PASS (no override file)"
fi

echo -n "9. Logging profile active... "
FLUENTBIT=$(docker ps --filter "name=fluent-bit" --format '{{.Names}}' | head -1)
if [ -n "$FLUENTBIT" ]; then
    echo "PASS"
else
    echo "WARN (logging profile not active -- required for enterprise)"
    WARN=$((WARN + 1))
fi

echo ""
echo "=== Results ==="
if [ $FAIL -gt 0 ]; then
    echo "FAILED: $FAIL check(s) failed"
    exit 1
elif [ $WARN -gt 0 ]; then
    echo "PASSED with $WARN warning(s)"
    exit 0
else
    echo "ALL CHECKS PASSED"
    exit 0
fi

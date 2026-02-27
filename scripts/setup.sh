#!/usr/bin/env bash
set -euo pipefail

# safe-ai first-time setup
# Run once after cloning: ./scripts/setup.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[ok]${NC}    $1"; }
warn() { echo -e "${YELLOW}[warn]${NC}  $1"; }
fail() { echo -e "${RED}[fail]${NC}  $1"; exit 1; }

WSL2_WARNINGS=0
wsl_warn() { echo -e "${YELLOW}[wsl2]${NC}  $1"; WSL2_WARNINGS=$((WSL2_WARNINGS + 1)); }
wsl_fail() { echo -e "${RED}[wsl2]${NC}  $1"; WSL2_WARNINGS=$((WSL2_WARNINGS + 1)); HAS_WSL2_ERRORS=1; }

echo "safe-ai setup"
echo "============="
echo ""

# Check Docker
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    ok "Docker ${DOCKER_VERSION}"
else
    fail "Docker not found. Install: https://docs.docker.com/get-docker/"
fi

# Check Docker Compose
if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "unknown")
    ok "Docker Compose ${COMPOSE_VERSION}"
else
    fail "Docker Compose not found. Install: https://docs.docker.com/compose/install/"
fi

# Check SSH key
SSH_KEY="${SAFE_AI_SSH_KEY:-${HOME}/.ssh/id_ed25519.pub}"
if [ -f "$SSH_KEY" ]; then
    ok "SSH key: ${SSH_KEY}"
else
    warn "SSH key not found: ${SSH_KEY}"
    echo "       Generate one: ssh-keygen -t ed25519"
    echo "       Or set SAFE_AI_SSH_KEY in .env to point to your key."
fi

# Check gVisor (optional, for kernel-level isolation)
if command -v runsc &> /dev/null; then
    RUNSC_VERSION=$(runsc --version 2>/dev/null | head -1 || echo "unknown")
    ok "gVisor (runsc): ${RUNSC_VERSION}"
else
    warn "gVisor not installed (optional — prevents kernel-level container escapes)"
    echo "       Install: sudo ./scripts/install-gvisor.sh"
    echo "       Then set SAFE_AI_RUNTIME=runsc in .env"
fi

# Check audit logging config (optional)
if [ -n "${SAFE_AI_LOKI_URL:-}" ]; then
    # Validate URL format
    if echo "$SAFE_AI_LOKI_URL" | grep -qE '^https?://'; then
        ok "Audit logging: SAFE_AI_LOKI_URL=${SAFE_AI_LOKI_URL}"
        # Try to reach Loki
        LOKI_READY=$(curl -sf --max-time 5 "${SAFE_AI_LOKI_URL}/ready" 2>/dev/null || true)
        if [ -n "$LOKI_READY" ]; then
            ok "Central Loki is reachable"
        else
            warn "Central Loki is not reachable at ${SAFE_AI_LOKI_URL}"
            echo "       Logs will buffer locally until Loki becomes available."
        fi
    else
        warn "SAFE_AI_LOKI_URL has invalid format: ${SAFE_AI_LOKI_URL}"
        echo "       Expected: https://host:port or http://host:port"
    fi
else
    echo "INFO: Audit logging not configured. Enable with:"
    echo "       docker compose --profile logging up -d"
fi

# Create .env if it doesn't exist
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        ok "Created .env from .env.example"
    else
        warn ".env.example not found — skipping .env creation"
    fi
else
    ok ".env already exists"
fi

# WSL2 checks
if grep -qi microsoft /proc/version 2>/dev/null; then
    echo ""
    echo "WSL2 detected — running platform checks..."
    HAS_WSL2_ERRORS=0

    # Check 1: Project should be on WSL2 native filesystem, not NTFS
    if [[ "$PWD" == /mnt/* ]]; then
        wsl_fail "Project is on Windows filesystem ($PWD)"
        echo "       NTFS does not support Linux permissions and is 2-5x slower."
        echo "       Move the project to the WSL2 filesystem:"
        echo "         mkdir -p ~/projects"
        echo "         cp -r $PWD ~/projects/safe-ai"
        echo "         cd ~/projects/safe-ai"
    else
        ok "Project is on WSL2 filesystem"
    fi

    # Check 2: SSH key should be on WSL2 native filesystem
    if [[ "$SSH_KEY" == /mnt/* ]]; then
        wsl_fail "SSH key is on Windows filesystem ($SSH_KEY)"
        echo "       SSH requires strict permissions (600) which NTFS cannot enforce."
        echo "       Copy your key to WSL2:"
        echo "         cp $SSH_KEY ~/.ssh/"
        echo "         chmod 600 ~/.ssh/$(basename "$SSH_KEY" .pub)"
        echo "         chmod 644 ~/.ssh/$(basename "$SSH_KEY")"
        echo "       Then set SAFE_AI_SSH_KEY=~/.ssh/$(basename "$SSH_KEY") in .env"
    elif [ -f "$SSH_KEY" ]; then
        ok "SSH key is on WSL2 filesystem"
    fi

    # Check 3: Fix CRLF in shell scripts
    CRLF_FILES=""
    for f in sandbox/entrypoint.sh proxy/entrypoint.sh scripts/setup.sh scripts/test.sh; do
        if [ -f "$f" ] && file "$f" | grep -q CRLF; then
            CRLF_FILES="$CRLF_FILES $f"
        fi
    done
    if [ -n "$CRLF_FILES" ]; then
        wsl_warn "CRLF line endings detected in:$CRLF_FILES"
        echo "       Fixing automatically..."
        for f in $CRLF_FILES; do
            sed -i 's/\r$//' "$f"
        done
        ok "Line endings fixed (LF)"
    else
        ok "Shell scripts have correct line endings (LF)"
    fi

    # Check 4: Docker Desktop vs native Engine
    if docker info 2>/dev/null | grep -q "Docker Desktop"; then
        ok "Docker Desktop detected (recommended for WSL2)"
    else
        ok "Native Docker Engine detected"
        # Check iptables backend
        if command -v iptables &>/dev/null && iptables -V 2>/dev/null | grep -q nf_tables; then
            wsl_warn "iptables uses nftables backend"
            echo "       If Docker fails to start, switch to iptables-legacy:"
            echo "         sudo update-alternatives --set iptables /usr/sbin/iptables-legacy"
            echo "         sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy"
            echo "         sudo service docker restart"
        fi
    fi

    # Check 5: systemd
    if ! systemctl is-system-running &>/dev/null; then
        wsl_warn "systemd is not running"
        echo "       Some Docker features require systemd. Enable it:"
        echo "         Add to /etc/wsl.conf:"
        echo "           [boot]"
        echo "           systemd=true"
        echo "         Then restart WSL: wsl --shutdown"
    fi

    # Check 6: Mirrored networking mode
    WSLCONFIG=""
    if command -v wslpath &>/dev/null && command -v wslvar &>/dev/null; then
        WSLCONFIG="$(wslpath "$(wslvar USERPROFILE)")/.wslconfig" 2>/dev/null || true
    fi
    if [ -n "$WSLCONFIG" ] && [ -f "$WSLCONFIG" ] && grep -qi "networkingMode.*=.*mirrored" "$WSLCONFIG" 2>/dev/null; then
        wsl_warn "WSL2 mirrored networking mode detected"
        echo "       Docker Desktop may have connectivity issues in mirrored mode."
        echo "       If you experience problems, switch to NAT mode (default):"
        echo "         Remove 'networkingMode=mirrored' from $(wslpath "$(wslvar USERPROFILE)")/.wslconfig"
        echo "         Then restart WSL: wsl --shutdown"
    fi

    # Summary
    if [ "$HAS_WSL2_ERRORS" -gt 0 ]; then
        echo ""
        fail "WSL2 environment has errors that must be fixed before continuing."
    elif [ "$WSL2_WARNINGS" -gt 0 ]; then
        echo ""
        warn "WSL2: $WSL2_WARNINGS warning(s) — setup will continue, but review above."
    else
        ok "WSL2 environment looks good"
    fi
fi

# Build images
echo ""
echo "Building images..."
docker compose build

echo ""
ok "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Edit .env if needed (API keys go in docker-compose.override.yaml)"
echo "  2. docker compose up -d"
echo "  3. ssh -p \${SAFE_AI_SSH_PORT:-2222} dev@localhost"

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

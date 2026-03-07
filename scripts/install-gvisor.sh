#!/usr/bin/env bash
set -euo pipefail

# Install gVisor (runsc) for kernel-level container isolation.
# Run once on the Docker host: sudo ./scripts/install-gvisor.sh
#
# After installing, enable in .env:
#   SAFE_AI_RUNTIME=runsc
#
# Options:
#   --default   Set runsc as the default Docker runtime for ALL containers

SET_DEFAULT=0
for arg in "$@"; do
    case "$arg" in
        --default) SET_DEFAULT=1 ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[ok]${NC}    $1"; }
warn() { echo -e "${YELLOW}[warn]${NC}  $1"; }
fail() { echo -e "${RED}[fail]${NC}  $1"; exit 1; }

echo "gVisor (runsc) installer"
echo "========================"
echo ""

# Must be Linux
if [ "$(uname -s)" != "Linux" ]; then
    fail "gVisor only supports Linux. Current OS: $(uname -s)"
fi

# Must be root
if [ "$(id -u)" -ne 0 ]; then
    fail "This script must be run as root: sudo $0"
fi

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  URL_ARCH="x86_64" ;;
    aarch64) URL_ARCH="aarch64" ;;
    *)       fail "Unsupported architecture: $ARCH (gVisor supports x86_64 and aarch64)" ;;
esac
ok "Architecture: $ARCH"

# Check Docker
if ! command -v docker &> /dev/null; then
    fail "Docker not found. Install Docker first."
fi
ok "Docker found"

# Check if already installed
if command -v runsc &> /dev/null; then
    CURRENT_VERSION=$(runsc --version 2>/dev/null | head -1 || echo "unknown")
    warn "runsc already installed: $CURRENT_VERSION"
    echo "       Reinstalling with latest version..."
fi

# Download runsc and containerd shim
BASE_URL="https://storage.googleapis.com/gvisor/releases/release/latest/${URL_ARCH}"

echo ""
echo "Downloading gVisor binaries..."

curl -fsSL "${BASE_URL}/runsc" -o /usr/local/bin/runsc
curl -fsSL "${BASE_URL}/containerd-shim-runsc-v1" -o /usr/local/bin/containerd-shim-runsc-v1

chmod 755 /usr/local/bin/runsc
chmod 755 /usr/local/bin/containerd-shim-runsc-v1

INSTALLED_VERSION=$(runsc --version 2>/dev/null | head -1 || echo "unknown")
ok "Installed: $INSTALLED_VERSION"

# Configure Docker runtime
echo ""
echo "Configuring Docker..."
runsc install
ok "Docker configured with runsc runtime"

# Optionally set runsc as the default runtime for all containers
if [ "$SET_DEFAULT" = "1" ]; then
    DAEMON_JSON="/etc/docker/daemon.json"
    if [ -f "$DAEMON_JSON" ]; then
        tmp=$(mktemp)
        jq '. + {"default-runtime": "runsc"}' "$DAEMON_JSON" > "$tmp" && mv "$tmp" "$DAEMON_JSON"
    else
        echo '{"default-runtime": "runsc"}' > "$DAEMON_JSON"
    fi
    ok "Set runsc as default Docker runtime (all containers)"
fi

# Restart Docker
echo ""
echo "Restarting Docker daemon..."
if systemctl is-active --quiet docker; then
    systemctl restart docker
    ok "Docker restarted"
elif command -v service &> /dev/null; then
    service docker restart
    ok "Docker restarted"
else
    warn "Could not restart Docker automatically. Please restart it manually."
fi

# Verify
echo ""
echo "Verifying installation..."
if docker run --runtime=runsc --rm hello-world &> /dev/null; then
    ok "gVisor is working (hello-world passed)"
else
    fail "gVisor verification failed. Check Docker logs: journalctl -u docker"
fi

echo ""
ok "gVisor installed successfully!"
echo ""
if [ "$SET_DEFAULT" = "1" ]; then
    echo "All containers on this host now use gVisor by default."
    echo ""
    echo "Next steps:"
    echo "  1. Restart sandbox:   docker compose up -d --force-recreate"
    echo "  2. Verify:            docker inspect --format='{{.HostConfig.Runtime}}' safe-ai-sandbox"
else
    echo "Next steps:"
    echo "  1. Add to your .env:  SAFE_AI_RUNTIME=runsc"
    echo "  2. Restart sandbox:   docker compose up -d --force-recreate"
    echo "  3. Verify:            docker inspect --format='{{.HostConfig.Runtime}}' safe-ai-sandbox"
fi

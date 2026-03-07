#!/usr/bin/env bash
set -euo pipefail

# safe-ai publish script — build and push images to a private registry
#
# Usage:
#   REGISTRY=nexus.corp.com/safe-ai ./scripts/publish.sh
#   REGISTRY=nexus.corp.com/safe-ai ./scripts/publish.sh --version v1.0.0
#   REGISTRY=nexus.corp.com/safe-ai ./scripts/publish.sh --images node,codex,java
#   REGISTRY=nexus.corp.com/safe-ai ./scripts/publish.sh --custom examples/claude-java.Dockerfile:claude-java
#
# Environment variables:
#   REGISTRY  (required)  Registry URL prefix (e.g. nexus.corp.com/safe-ai)
#
# Flags:
#   --version TAG          Image tag (default: latest)
#   --images LIST          Comma-separated extensions to build (default: all)
#   --custom FILE:NAME     Build a custom Dockerfile and push as ${REGISTRY}/NAME

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[ok]${NC}    $1"; }
warn() { echo -e "${YELLOW}[warn]${NC}  $1"; }
fail() { echo -e "${RED}[fail]${NC}  $1"; exit 1; }

# ---- Parse arguments ----

VERSION="latest"
IMAGES_ARG=""
CUSTOM_BUILDS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --version) VERSION="$2"; shift 2 ;;
        --images)  IMAGES_ARG="$2"; shift 2 ;;
        --custom)  CUSTOM_BUILDS+=("$2"); shift 2 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

# All available extensions and their dependencies
# Format: name:dockerfile:dependency
EXTENSIONS=(
    "node:examples/node.Dockerfile:sandbox"
    "java:examples/java.Dockerfile:sandbox"
    "python:examples/python.Dockerfile:sandbox"
    "claude:examples/claude-code.Dockerfile:node"
    "codex:examples/codex.Dockerfile:node"
    "codex-java:examples/codex-java.Dockerfile:codex"
)

ALL_NAMES=""
for ext in "${EXTENSIONS[@]}"; do
    name="${ext%%:*}"
    ALL_NAMES="${ALL_NAMES:+${ALL_NAMES},}${name}"
done

if [ -z "$IMAGES_ARG" ]; then
    IMAGES_ARG="$ALL_NAMES"
fi

IFS=',' read -ra REQUESTED_IMAGES <<< "$IMAGES_ARG"

# ---- Resolve dependencies ----

resolve_deps() {
    local name="$1"
    for ext in "${EXTENSIONS[@]}"; do
        local ext_name="${ext%%:*}"
        local rest="${ext#*:}"
        local ext_dep="${rest#*:}"
        if [ "$ext_name" = "$name" ] && [ "$ext_dep" != "sandbox" ]; then
            # Check if dependency is already in the list
            local found=0
            for req in "${RESOLVED[@]}"; do
                [ "$req" = "$ext_dep" ] && found=1
            done
            if [ $found -eq 0 ]; then
                resolve_deps "$ext_dep"
            fi
        fi
    done
    # Add self if not already there
    local found=0
    for req in "${RESOLVED[@]}"; do
        [ "$req" = "$name" ] && found=1
    done
    if [ $found -eq 0 ]; then
        RESOLVED+=("$name")
    fi
}

RESOLVED=()
for img in "${REQUESTED_IMAGES[@]}"; do
    img=$(echo "$img" | xargs)
    resolve_deps "$img"
done

# ---- Validation ----

echo "safe-ai publish"
echo "==============="
echo ""

if [ -z "${REGISTRY:-}" ]; then
    fail "REGISTRY is not set.

  Set it to your internal registry path, e.g.:
    REGISTRY=nexus.corp.com/safe-ai ./scripts/publish.sh"
fi

ok "Registry: ${REGISTRY}"
ok "Version: ${VERSION}"
ok "Extensions: ${RESOLVED[*]}"

# ---- Ensure we're in the repo root ----

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [ ! -f "docker-compose.yaml" ]; then
    fail "Cannot find docker-compose.yaml — run this script from the safe-ai repo root"
fi

# ---- Copy allowlist into proxy build context ----

ALLOWLIST_SRC="allowlist.yaml"
ALLOWLIST_DST="images/proxy/allowlist.yaml"

if [ ! -f "$ALLOWLIST_SRC" ]; then
    fail "allowlist.yaml not found in repo root"
fi

cp "$ALLOWLIST_SRC" "$ALLOWLIST_DST"
trap 'rm -f "${REPO_ROOT}/${ALLOWLIST_DST}" 2>/dev/null' EXIT

DOMAIN_COUNT=$(grep -c '^ *- ' "$ALLOWLIST_SRC" 2>/dev/null || echo "0")
ok "Allowlist: ${DOMAIN_COUNT} domains (will be baked into proxy image)"

# ---- Build base images ----

echo ""
echo "Building base images (sandbox + proxy)..."
docker compose build

BUILT_IMAGES=("safe-ai-sandbox" "safe-ai-proxy")
ok "Base images built"

# ---- Build extensions ----

for name in "${RESOLVED[@]}"; do
    for ext in "${EXTENSIONS[@]}"; do
        ext_name="${ext%%:*}"
        rest="${ext#*:}"
        ext_dockerfile="${rest%%:*}"

        if [ "$ext_name" = "$name" ]; then
            echo ""
            echo "Building extension: ${name}..."
            docker build -f "$ext_dockerfile" -t "safe-ai-${name}:latest" .
            BUILT_IMAGES+=("safe-ai-${name}")
            ok "Built safe-ai-${name}"
            break
        fi
    done
done

# ---- Build custom Dockerfiles ----

for custom in "${CUSTOM_BUILDS[@]}"; do
    dockerfile="${custom%%:*}"
    image_name="${custom#*:}"

    if [ ! -f "$dockerfile" ]; then
        warn "Custom Dockerfile not found: ${dockerfile} — skipping"
        continue
    fi

    echo ""
    echo "Building custom: ${image_name} from ${dockerfile}..."
    docker build -f "$dockerfile" -t "safe-ai-${image_name}:latest" .
    BUILT_IMAGES+=("safe-ai-${image_name}")
    ok "Built safe-ai-${image_name}"
done

# ---- Tag and push ----

echo ""
echo "Tagging and pushing to ${REGISTRY}..."

# Map local names to registry names
for local_name in "${BUILT_IMAGES[@]}"; do
    # safe-ai-sandbox -> sandbox, safe-ai-proxy -> proxy, etc.
    registry_name="${local_name#safe-ai-}"

    docker tag "${local_name}:latest" "${REGISTRY}/${registry_name}:${VERSION}"
    docker push "${REGISTRY}/${registry_name}:${VERSION}"

    if [ "$VERSION" != "latest" ]; then
        docker tag "${local_name}:latest" "${REGISTRY}/${registry_name}:latest"
        docker push "${REGISTRY}/${registry_name}:latest"
    fi

    ok "Pushed ${REGISTRY}/${registry_name}:${VERSION}"
done

# ---- Trivy scan (optional) ----

if command -v trivy &> /dev/null; then
    echo ""
    echo "Running Trivy vulnerability scan..."
    for local_name in "${BUILT_IMAGES[@]}"; do
        registry_name="${local_name#safe-ai-}"
        trivy image --severity CRITICAL,HIGH "${REGISTRY}/${registry_name}:${VERSION}" || true
    done
else
    echo ""
    warn "Trivy not installed — skipping vulnerability scan"
    echo "       Install: https://aquasecurity.github.io/trivy/"
fi

# ---- Summary ----

echo ""
echo "========================================"
echo ""
ok "Published ${#BUILT_IMAGES[@]} images to ${REGISTRY}"
echo ""
echo "  Images:"
for local_name in "${BUILT_IMAGES[@]}"; do
    registry_name="${local_name#safe-ai-}"
    echo "    ${REGISTRY}/${registry_name}:${VERSION}"
done
echo ""
echo "  Developers can now run:"
echo "    REGISTRY=${REGISTRY} ./start.sh"
echo "    REGISTRY=${REGISTRY} IMAGE=<name> ./start.sh"
echo ""
echo "  Baked-in allowlist domains:"
grep '^ *- ' "$ALLOWLIST_SRC" 2>/dev/null | sed 's/^ *- /    /' || echo "    (none)"
echo ""

#!/usr/bin/env bash
set -euo pipefail
umask 077

# safe-ai aibox script
# Self-contained — no repo clone needed. Distributed via internal channels.
#
# Usage:
#   REGISTRY=nexus.corp.com/safe-ai ./aibox.sh
#   REGISTRY=nexus.corp.com/safe-ai IMAGE=java ./aibox.sh
#   REGISTRY=nexus.corp.com/safe-ai IMAGE=claude VERSION=v1.2.0 ./aibox.sh
#
# Environment variables:
#   REGISTRY  (required)  Registry URL prefix (e.g. nexus.corp.com/safe-ai)
#   IMAGE     (optional)  Sandbox image name (default: sandbox)
#   VERSION   (optional)  Image tag (default: latest)
#   SSH_PORT  (optional)  Host port for SSH (default: 2222)
#   SSH_KEY   (optional)  Path to SSH public key (default: ~/.ssh/id_ed25519.pub)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[ok]${NC}    $1"; }
warn() { echo -e "${YELLOW}[warn]${NC}  $1"; }
fail() { echo -e "${RED}[fail]${NC}  $1"; exit 1; }

WORK_DIR="${HOME}/.safe-ai"
IMAGE="${IMAGE:-sandbox}"
VERSION="${VERSION:-latest}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_ed25519.pub}"

echo "safe-ai start"
echo "============="
echo ""

# ---- Input validation (prevent YAML injection + path traversal) ----

if [ -z "${REGISTRY:-}" ]; then
    fail "REGISTRY is not set.

  Set it to your internal registry path, e.g.:
    REGISTRY=nexus.corp.com/safe-ai ./aibox.sh
    REGISTRY=nexus.corp.com/safe-ai IMAGE=java ./aibox.sh"
fi

[[ "$REGISTRY" =~ ^[a-zA-Z0-9._:/-]+$ ]] || fail "Invalid REGISTRY: only alphanumeric, dots, colons, slashes, hyphens allowed"
[[ "$IMAGE" =~ ^[a-zA-Z0-9._-]+$ ]] || fail "Invalid IMAGE: only alphanumeric, dots, underscores, hyphens allowed"
[[ "$VERSION" =~ ^[a-zA-Z0-9._-]+$ ]] || fail "Invalid VERSION: only alphanumeric, dots, underscores, hyphens allowed"
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] || fail "Invalid SSH_PORT: must be a number"
[[ "$SSH_KEY" =~ \.pub$ ]] || fail "Invalid SSH_KEY: must point to a .pub file"

# Prevent path traversal — SSH_KEY must be under ~/.ssh/
SSH_KEY_RESOLVED=$(realpath -m "$SSH_KEY" 2>/dev/null || echo "$SSH_KEY")
if [[ "$SSH_KEY_RESOLVED" != "${HOME}/.ssh/"* ]]; then
    fail "SSH_KEY must be under ~/.ssh/ (got: ${SSH_KEY})"
fi

# ---- Prerequisite checks ----

if ! command -v docker &> /dev/null; then
    fail "Docker not found. Install: https://docs.docker.com/get-docker/"
fi
ok "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)"

if ! docker compose version &> /dev/null; then
    fail "Docker Compose v2 not found. Install: https://docs.docker.com/compose/install/"
fi
ok "Docker Compose $(docker compose version --short 2>/dev/null || echo "unknown")"

if [ -f "$SSH_KEY" ]; then
    ok "SSH key: ${SSH_KEY}"
else
    warn "SSH key not found: ${SSH_KEY}"
    echo "       Generate one: ssh-keygen -t ed25519"
    echo "       Or set SSH_KEY to point to your public key."
fi

ok "Registry: ${REGISTRY}"
ok "Image: ${IMAGE}:${VERSION}"

# ---- Create working directory ----

mkdir -p "$WORK_DIR"
chmod 700 "$WORK_DIR"

# ---- Generate seccomp.json ----

cat > "${WORK_DIR}/seccomp.json" <<'SECCOMP_EOF'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "defaultErrnoRet": 1,
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32",
    "SCMP_ARCH_AARCH64"
  ],
  "syscalls": [
    {
      "names": [
        "read", "write", "open", "openat", "close", "stat", "fstat", "lstat",
        "statx", "newfstatat", "access", "faccessat", "faccessat2", "readlink",
        "readlinkat", "getcwd", "chdir", "rename", "renameat", "renameat2",
        "unlink", "unlinkat", "mkdir", "mkdirat", "rmdir", "symlink", "symlinkat",
        "link", "linkat", "chmod", "fchmod", "fchmodat", "chown", "fchown",
        "fchownat", "utimensat", "truncate", "ftruncate", "fallocate", "fsync",
        "fdatasync", "sync_file_range", "copy_file_range", "sendfile", "splice",
        "tee", "capget", "capset", "setuid", "setgid", "setreuid", "setregid",
        "setresuid", "setresgid", "getresuid", "getresgid", "initgroups"
      ],
      "action": "SCMP_ACT_ALLOW"
    },
    {
      "names": [
        "fork", "vfork", "clone", "clone3", "execve", "execveat", "wait4",
        "waitid", "exit", "exit_group", "getpid", "getppid", "gettid", "getuid",
        "getgid", "geteuid", "getegid", "getgroups", "setgroups", "setsid",
        "getpgid", "setpgid", "getpgrp", "prctl", "arch_prctl", "set_tid_address",
        "chroot", "seccomp"
      ],
      "action": "SCMP_ACT_ALLOW"
    },
    {
      "names": [
        "mmap", "mprotect", "munmap", "brk", "mremap", "madvise", "mincore",
        "msync", "mlock", "mlock2", "munlock", "mlockall", "munlockall"
      ],
      "action": "SCMP_ACT_ALLOW"
    },
    {
      "names": [
        "rt_sigaction", "rt_sigprocmask", "rt_sigreturn", "rt_sigpending",
        "rt_sigtimedwait", "rt_sigsuspend", "rt_sigqueueinfo",
        "rt_tgsigqueueinfo", "kill", "tgkill", "tkill", "sigaltstack"
      ],
      "action": "SCMP_ACT_ALLOW"
    },
    {
      "names": [
        "socket", "connect", "bind", "listen", "accept", "accept4", "sendto",
        "recvfrom", "sendmsg", "recvmsg", "sendmmsg", "recvmmsg", "shutdown",
        "getsockname", "getpeername", "setsockopt", "getsockopt", "socketpair",
        "select", "pselect6", "poll", "ppoll", "epoll_create", "epoll_create1",
        "epoll_ctl", "epoll_wait", "epoll_pwait", "epoll_pwait2"
      ],
      "action": "SCMP_ACT_ALLOW"
    },
    {
      "names": [
        "futex", "set_robust_list", "get_robust_list", "sched_yield",
        "sched_getaffinity", "sched_setaffinity", "sched_getscheduler",
        "sched_getparam"
      ],
      "action": "SCMP_ACT_ALLOW"
    },
    {
      "names": [
        "io_setup", "io_submit", "io_getevents", "io_destroy", "eventfd",
        "eventfd2", "timerfd_create", "timerfd_settime", "timerfd_gettime",
        "signalfd", "signalfd4"
      ],
      "action": "SCMP_ACT_ALLOW"
    },
    {
      "names": [
        "statfs", "fstatfs", "getdents", "getdents64", "fcntl", "ioctl", "dup",
        "dup2", "dup3", "pipe", "pipe2", "inotify_init", "inotify_init1",
        "inotify_add_watch", "inotify_rm_watch", "fanotify_init", "fanotify_mark",
        "flock", "lseek"
      ],
      "action": "SCMP_ACT_ALLOW"
    },
    {
      "names": [
        "clock_gettime", "clock_getres", "clock_nanosleep", "gettimeofday",
        "nanosleep", "timer_create", "timer_settime", "timer_gettime",
        "timer_getoverrun", "timer_delete"
      ],
      "action": "SCMP_ACT_ALLOW"
    },
    {
      "names": [
        "getrandom", "memfd_create", "membarrier", "rseq", "pread64", "pwrite64",
        "readv", "writev", "preadv", "preadv2", "pwritev", "pwritev2", "sysinfo",
        "uname", "getrlimit", "setrlimit", "prlimit64", "getrusage", "times",
        "umask"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
SECCOMP_EOF

# ---- Generate docker-compose.yaml ----

cat > "${WORK_DIR}/docker-compose.yaml" <<COMPOSE_EOF
# Auto-generated by safe-ai aibox.sh — do not edit manually.
# This file is regenerated on every run. Changes will be overwritten.

services:
  sandbox:
    image: ${REGISTRY}/${IMAGE}:${VERSION}
    container_name: safe-ai-sandbox
    hostname: sandbox
    networks:
      - internal
    dns:
      - 172.28.0.2
    volumes:
      - workspace:/workspace
      - vscode-server:/home/dev/.vscode-server
      - ${SSH_KEY}:/home/dev/.ssh/authorized_keys:ro
    environment:
      - http_proxy=http://proxy:3128
      - https_proxy=http://proxy:3128
      - HTTP_PROXY=http://proxy:3128
      - HTTPS_PROXY=http://proxy:3128
      - no_proxy=localhost,127.0.0.1
      - NO_PROXY=localhost,127.0.0.1
    security_opt:
      - seccomp=./seccomp.json
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - SETUID
      - SETGID
      - SYS_CHROOT
      - NET_BIND_SERVICE
      - CHOWN
    read_only: true
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=2g
      - /run:rw,noexec,nosuid,size=64m
    deploy:
      resources:
        limits:
          memory: \${SAFE_AI_SANDBOX_MEMORY:-8g}
          cpus: "\${SAFE_AI_SANDBOX_CPUS:-4}"
          pids: 512
    healthcheck:
      test: ["CMD-SHELL", "pgrep sshd > /dev/null || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    restart: unless-stopped
    depends_on:
      proxy:
        condition: service_healthy

  proxy:
    image: ${REGISTRY}/proxy:${VERSION}
    container_name: safe-ai-proxy
    hostname: proxy
    networks:
      internal:
        ipv4_address: 172.28.0.2
      external:
    ports:
      - "${SSH_PORT}:2222"
    volumes:
      - squid-logs:/var/log/squid
    environment:
      - SAFE_AI_SSH_FORWARD=1
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
      - SETUID
      - SETGID
      - CHOWN
      - DAC_OVERRIDE
    read_only: true
    tmpfs:
      - /var/spool/squid:rw,size=256m
      - /run:rw,size=16m
      - /tmp:rw,size=64m
      - /etc/squid:rw,size=1m
      - /etc/dnsmasq.d:rw,size=1m
    healthcheck:
      test: ["CMD-SHELL", "squid -k check && pgrep dnsmasq > /dev/null && pgrep socat > /dev/null"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 5s
    deploy:
      resources:
        limits:
          memory: 256m
          cpus: "1"
          pids: 128
    restart: unless-stopped

networks:
  internal:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.28.0.0/28
  external:
    driver: bridge

volumes:
  workspace:
    driver: local
  vscode-server:
    driver: local
  squid-logs:
    driver: local
COMPOSE_EOF

# ---- Create .env if not present ----

if [ ! -f "${WORK_DIR}/.env" ]; then
    cat > "${WORK_DIR}/.env" <<ENV_EOF
# safe-ai environment configuration
# Edit this file to customize your setup. Preserved across aibox.sh runs.

# Resource limits (adjust for your machine)
SAFE_AI_SANDBOX_MEMORY=8g
SAFE_AI_SANDBOX_CPUS=4
ENV_EOF
    ok "Created ${WORK_DIR}/.env"
else
    ok "Using existing ${WORK_DIR}/.env"
fi

# ---- Pull images ----

echo ""
echo "Pulling images from ${REGISTRY}..."
cd "$WORK_DIR"
docker compose pull

# ---- Start containers ----

echo ""
echo "Starting containers..."
docker compose up -d

# ---- Wait for healthy ----

echo ""
echo -n "Waiting for containers to be healthy"
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    HEALTHY=$(docker compose ps --format json 2>/dev/null | grep -c '"healthy"' || true)
    if [ "$HEALTHY" -ge 2 ]; then
        echo ""
        ok "All containers healthy"
        break
    fi
    echo -n "."
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo ""
    warn "Timed out waiting for containers. Check: docker compose -f ${WORK_DIR}/docker-compose.yaml ps"
fi

# ---- Print connection info ----

echo ""
echo "========================================"
echo ""
ok "safe-ai is running!"
echo ""
echo "  Connect:  ssh -p ${SSH_PORT} dev@localhost"
echo "  Logs:     docker compose -f ${WORK_DIR}/docker-compose.yaml logs -f proxy"
echo "  Stop:     docker compose -f ${WORK_DIR}/docker-compose.yaml down"
echo "  Restart:  REGISTRY=${REGISTRY} IMAGE=${IMAGE} $(realpath "$0")"
echo ""
echo "  Image:    ${REGISTRY}/${IMAGE}:${VERSION}"
echo "  Proxy:    ${REGISTRY}/proxy:${VERSION}"
echo ""

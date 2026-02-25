# safe-ai

Sandboxed containers for AI coding agents. Filesystem safety + network allowlisting in 13 files.

```
┌─────────────────────────────────┐
│        external network         │ ← internet
└───────────────┬─────────────────┘
                │
┌───────────────┴─────────────────┐
│  proxy (Squid)                  │
│  allowlist.yaml → squid.conf   │
│  port 3128                      │
└───────────────┬─────────────────┘
                │
┌───────────────┴─────────────────┐
│        internal network         │ ← internal: true (NO internet)
└───────────────┬─────────────────┘
                │
┌───────────────┴─────────────────┐
│  sandbox (dev environment)      │
│  read-only root, cap_drop ALL   │
│  seccomp, noexec /tmp           │
│  SSH on port 22                 │
└─────────────────────────────────┘
         │
   port 2222 → host (IDE access)
```

The sandbox has **no internet access**. All outbound traffic goes through the proxy, which only allows connections to domains in your allowlist. Docker's `internal: true` network enforces this at the kernel level — even if an AI agent tries to bypass the proxy, there is no route out.

## Quickstart

```bash
# 1. Clone
git clone https://github.com/safe-ai-project/safe-ai.git
cd safe-ai

# 2. Edit your allowlist (optional — sensible defaults included)
vim allowlist.yaml

# 3. Build and start
docker compose up -d --build

# 4. Connect via SSH (VS Code Remote-SSH, JetBrains Gateway, or terminal)
ssh -p 2222 dev@localhost

# 5. Verify isolation
curl https://api.anthropic.com    # works (allowlisted)
curl https://evil.com             # blocked (403)
ping 8.8.8.8                     # blocked (no route)
```

## Allowlist Configuration

Edit `allowlist.yaml` to control which domains the sandbox can reach:

```yaml
domains:
  - api.anthropic.com
  - api.openai.com
  - github.com
  - registry.npmjs.org
```

Three ways to configure:

| Method | How | Use case |
|--------|-----|----------|
| **File** | Edit `allowlist.yaml` | Default for most teams |
| **ENV** | `SAFE_AI_DEFAULT_DOMAINS=a.com,b.com` | CI/CD additions |
| **Mount** | `SAFE_AI_ALLOWLIST=./my-list.yaml docker compose up` | Per-project override |

Domains from all sources are merged. Subdomains are automatically included (e.g. `github.com` also allows `api.github.com`).

## Extending the Base Image

safe-ai is a base — add your own tools by extending the sandbox image:

```dockerfile
# my-sandbox.Dockerfile
FROM safe-ai-sandbox:latest

USER root
RUN apt-get update && apt-get install -y openjdk-21-jdk && rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
USER dev
```

Then override in `docker-compose.override.yaml`:

```yaml
services:
  sandbox:
    build:
      context: .
      dockerfile: my-sandbox.Dockerfile
```

All security properties (read-only root, capability drops, seccomp, network isolation) are enforced by the compose file, not the Dockerfile — they are inherited automatically.

### Example Layer Graph

```
safe-ai-sandbox:latest
  ├── node.Dockerfile       → safe-ai-node        (+ Node.js 22)
  │     ├── claude-code.Dockerfile → safe-ai-claude  (+ Claude Code CLI)
  │     └── codex.Dockerfile       → safe-ai-codex   (+ Codex CLI)
  │           └── codex-java.Dockerfile → safe-ai-codex-java  (+ Java 21)
  └── java.Dockerfile       → safe-ai-java         (+ Java 21, standalone)
```

Build in dependency order:

```bash
docker compose build                                              # base sandbox + proxy
docker build -f examples/node.Dockerfile -t safe-ai-node .       # shared Node.js layer
docker build -f examples/claude-code.Dockerfile -t safe-ai-claude .
docker build -f examples/codex.Dockerfile -t safe-ai-codex .
docker build -f examples/java.Dockerfile -t safe-ai-java .
docker build -f examples/codex-java.Dockerfile -t safe-ai-codex-java .
```

See `examples/` for full Dockerfiles and `examples/codex-config.toml` for a sample Codex runtime configuration.

## IDE Setup

**VS Code**: Install "Remote - SSH" extension, connect to `dev@localhost:2222`.

**JetBrains**: Use JetBrains Gateway, connect via SSH to `localhost:2222`.

**SSH key**: By default, `~/.ssh/id_ed25519.pub` is mounted. Override with:

```bash
SAFE_AI_SSH_KEY=~/.ssh/id_rsa.pub docker compose up -d
```

## Security Model

**What is prevented:**

- Outbound connections to non-allowlisted domains (proxy + network isolation)
- System file modification (read-only root filesystem)
- Privilege escalation (all capabilities dropped, no-new-privileges)
- Raw sockets / ICMP covert channels (no CAP_NET_RAW)
- Dangerous syscalls — ptrace, mount, bpf, unshare, kexec (seccomp filter)
- Execution from /tmp (noexec mount)
- Proxy bypass (sandbox has no route to internet, only to proxy on internal network)

**Accepted risks (documented):**

- Exfiltration via allowlisted domains (scope your allowlist narrowly)
- Container escape via kernel zero-day (add gVisor `runtime: runsc` for defense-in-depth)

## Publishing to a Private Registry

Images are built locally by default. If your team wants to share pre-built images (e.g. via an on-prem Nexus, Artifactory, or Harbor), tag and push them after building:

```bash
# Build
docker compose build

# Tag for your registry
docker tag safe-ai-sandbox:latest nexus.internal.example.com/safe-ai/sandbox:latest
docker tag safe-ai-proxy:latest nexus.internal.example.com/safe-ai/proxy:latest

# Push
docker push nexus.internal.example.com/safe-ai/sandbox:latest
docker push nexus.internal.example.com/safe-ai/proxy:latest
```

Then consumers pull from the registry instead of building locally — create a `docker-compose.override.yaml`:

```yaml
services:
  sandbox:
    image: nexus.internal.example.com/safe-ai/sandbox:latest
    build: !override null
  proxy:
    image: nexus.internal.example.com/safe-ai/proxy:latest
    build: !override null
```

> `!override null` requires Docker Compose v2.24+. On older versions, edit `docker-compose.yaml` directly to remove the `build:` keys.

See `examples/publish-to-registry.yaml` for a GitHub Actions workflow you can adapt.

## Podman

Works with `podman compose` (Podman's built-in compose, which uses the Docker Compose compatibility layer):

```bash
podman compose up -d
ssh -p 2222 dev@localhost
```

> **Important:** Use `podman compose` (built-in), **not** `podman-compose` (third-party Python tool). The `dns:`, `ipv4_address`, `deploy.resources.limits`, and `service_healthy` compose features require the built-in compose.

Podman uses `aardvark-dns` instead of Docker's embedded DNS (`127.0.0.11`). Verify DNS filtering works after setup:

```bash
# Inside the sandbox:
dig github.com @172.28.0.2      # should resolve (allowlisted)
dig evil.com @172.28.0.2         # should return 0.0.0.0 (blocked)
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SAFE_AI_SSH_PORT` | `2222` | Host port for SSH |
| `SAFE_AI_SSH_KEY` | `~/.ssh/id_ed25519.pub` | Public key to mount |
| `SAFE_AI_ALLOWLIST` | `./allowlist.yaml` | Path to allowlist file |
| `SAFE_AI_DEFAULT_DOMAINS` | (empty) | Extra domains (comma-separated) |
| `SAFE_AI_SANDBOX_MEMORY` | `8g` | Sandbox memory limit |
| `SAFE_AI_SANDBOX_CPUS` | `4` | Sandbox CPU limit |

## License

Apache 2.0

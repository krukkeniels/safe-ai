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

## Configuration

Copy the example files and customize:

```bash
cp .env.example .env                                          # infrastructure config
cp docker-compose.override.yaml.example docker-compose.override.yaml  # API keys & mounts
```

Edit `.env` for SSH port, key path, and resource limits. Edit `docker-compose.override.yaml` to pass API keys and mount local code. Neither file is committed to git.

Or run `./scripts/setup.sh` to do this automatically.

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
  ├── java.Dockerfile       → safe-ai-java         (+ Java 21, standalone)
  └── python.Dockerfile     → safe-ai-python       (+ Python venv)
```

Build in dependency order:

```bash
docker compose build                                              # base sandbox + proxy
docker build -f examples/node.Dockerfile -t safe-ai-node .       # shared Node.js layer
docker build -f examples/claude-code.Dockerfile -t safe-ai-claude .
docker build -f examples/codex.Dockerfile -t safe-ai-codex .
docker build -f examples/java.Dockerfile -t safe-ai-java .
docker build -f examples/codex-java.Dockerfile -t safe-ai-codex-java .
docker build -f examples/python.Dockerfile -t safe-ai-python .
```

See `examples/` for full Dockerfiles and `examples/codex-config.toml` for a sample Codex runtime configuration.

## IDE Setup

**VS Code**: Install "Remote - SSH" extension, connect to `dev@localhost:2222`.

**JetBrains**: Use JetBrains Gateway, connect via SSH to `localhost:2222`.

**SSH key**: By default, `~/.ssh/id_ed25519.pub` is mounted. Override with:

```bash
SAFE_AI_SSH_KEY=~/.ssh/id_rsa.pub docker compose up -d
```

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| SSH "connection refused" | Container not running | `docker compose ps` to check, `docker compose up -d` to start |
| SSH "host key changed" | Container rebuilt (new host keys) | `ssh-keygen -R '[localhost]:2222'` |
| `curl` returns 403 | Domain not in allowlist | Add to `allowlist.yaml` and restart: `docker compose restart proxy` |
| `apt-get` fails | Read-only root filesystem | Pre-install in a custom Dockerfile (see "Extending the Base Image") |
| Can't see my local files | Using named volume | Use `docker-compose.override.yaml` with a bind mount (see example) |
| DNS resolution fails | Proxy not healthy | `docker compose logs proxy` to check for errors |

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

**Monitoring proxy traffic:**

```bash
docker compose logs proxy                     # all proxy logs
docker compose logs proxy | grep DENIED       # blocked requests only
docker compose logs -f proxy                  # follow in real-time
```

**Additional hardening:** For defense-in-depth against container escape, run the sandbox under [gVisor](https://gvisor.dev):

```yaml
# docker-compose.override.yaml
services:
  sandbox:
    runtime: runsc
```

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

See `.github/workflows/publish.yaml` for a GitHub Actions workflow you can adapt. To use it, configure `REGISTRY_USERNAME` and `REGISTRY_PASSWORD` as repository secrets and update the `REGISTRY` env var.

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

## Windows (WSL2)

safe-ai runs inside WSL2 on Windows 11. **Docker Desktop with the WSL2 backend** is the recommended setup.

### Prerequisites

1. **Install WSL2** with a Ubuntu distro (Windows Terminal: `wsl --install`)
2. **Install Docker Desktop** and enable "Use the WSL 2 based engine" in Settings > General
3. **Clone the project inside WSL2** — not on the Windows filesystem:

```bash
# Good — WSL2 native filesystem (fast, correct permissions)
cd ~ && git clone https://github.com/safe-ai-project/safe-ai.git

# Bad — Windows filesystem (slow, broken permissions)
cd /mnt/c/Users/you && git clone ...
```

4. **SSH keys must be on the WSL2 filesystem**:

```bash
# If your key is on Windows, copy it:
cp /mnt/c/Users/you/.ssh/id_ed25519* ~/.ssh/
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
```

5. **Run setup** to validate your environment:

```bash
./scripts/setup.sh    # detects WSL2 and checks for common issues
```

### WSL2 Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `bad interpreter: No such file or directory` | CRLF line endings | Run `./scripts/setup.sh` (auto-fixes) or `sed -i 's/\r$//' sandbox/entrypoint.sh proxy/entrypoint.sh` |
| SSH "permissions are too open" | Key on NTFS filesystem (`/mnt/c/`) | Copy key to `~/.ssh/` and `chmod 600` |
| Very slow `docker compose build` | Project on `/mnt/c/` | Move project to `~/` (WSL2 native filesystem) |
| SSH "connection refused" from Windows | Hyper-V firewall blocking | PowerShell (admin): `Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow` |
| Docker won't start (iptables error) | Native Docker Engine + nftables | `sudo update-alternatives --set iptables /usr/sbin/iptables-legacy && sudo service docker restart` |

### Alternative Runtimes on WSL2

**Docker Desktop** (recommended): All safe-ai features work. Note that Docker Desktop defaults seccomp to `unconfined` at the daemon level — safe-ai is protected because it specifies an explicit seccomp profile, but be aware for other containers.

**Native Docker Engine in WSL2**: Works, but requires manual setup. Enable systemd in `/etc/wsl.conf`, switch iptables to legacy backend, and note that container ports are not auto-forwarded to Windows (use `wsl --shutdown` and reconnect if ports seem stuck).

**Podman in WSL2**: Functional but less reliable. Rootless Podman has known systemd race conditions on WSL2. Use `podman compose` (built-in), not `podman-compose`. See the Podman section above for verification steps.

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

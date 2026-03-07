# Publishing to a Private Registry

Images are built locally by default. For teams sharing pre-built images via an on-prem registry (Nexus, Artifactory, Harbor), use the publish and start scripts.

## Platform team: build and push

```bash
# Publish base images + selected extensions to your registry
REGISTRY=nexus.internal.example.com/safe-ai ./scripts/publish.sh

# Only build specific extensions (dependencies resolved automatically)
REGISTRY=nexus.internal.example.com/safe-ai ./scripts/publish.sh --images node,codex,java

# Tag a release
REGISTRY=nexus.internal.example.com/safe-ai ./scripts/publish.sh --version v1.0.0

# Include a team-specific custom Dockerfile
REGISTRY=nexus.internal.example.com/safe-ai ./scripts/publish.sh \
  --images claude \
  --custom examples/claude-java.Dockerfile:claude-java
```

The publish script bakes the curated `allowlist.yaml` into the proxy image. Developers who pull the image cannot accidentally override the allowlist — they would need to rebuild the proxy image or edit the compose file (a deliberate choice, not a mistake).

## Developer: one command to start

Distribute `scripts/start.sh` to developers via your internal channel. No repo clone needed — the script is self-contained.

```bash
# Start with base sandbox
REGISTRY=nexus.internal.example.com/safe-ai ./start.sh

# Start with Java sandbox
REGISTRY=nexus.internal.example.com/safe-ai IMAGE=java ./start.sh

# Start with a specific version
REGISTRY=nexus.internal.example.com/safe-ai IMAGE=claude VERSION=v1.0.0 ./start.sh
```

The script checks prerequisites (Docker, Docker Compose, SSH key), pulls images, starts containers, and prints the SSH command. Configuration is stored in `~/.safe-ai/`.

| Variable | Default | Description |
|----------|---------|-------------|
| `REGISTRY` | (required) | Registry URL prefix |
| `IMAGE` | `sandbox` | Sandbox image name (`sandbox`, `node`, `java`, `python`, `claude`, `codex`, `codex-java`) |
| `VERSION` | `latest` | Image tag |
| `SSH_PORT` | `2222` | Host port for SSH |
| `SSH_KEY` | `~/.ssh/id_ed25519.pub` | Path to SSH public key |

## Security model for registry deployments

Security controls are split between two layers:

| Control | Where it lives | Central update mechanism |
|---------|---------------|--------------------------|
| Domain allowlist | Baked into proxy image | Push new proxy image |
| Seccomp profile | Embedded in start.sh | Redistribute start.sh |
| Capabilities, read-only root, network isolation | Embedded in start.sh | Redistribute start.sh |

This split is deliberate: even if the registry is compromised, an attacker cannot weaken the seccomp filter, capability drops, or network isolation because those are enforced by the compose file in start.sh, not by the images.

See `.github/workflows/publish.yaml` for a GitHub Actions workflow you can adapt.

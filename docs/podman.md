# Podman

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

## See Also

- [WSL2 Setup](wsl2.md) -- Windows-specific installation (includes Podman on WSL2 notes)
- [README](../README.md) -- Full setup and configuration guide

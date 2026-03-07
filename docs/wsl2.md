# Windows (WSL2)

safe-ai runs inside WSL2 on Windows 11. **Docker Desktop with the WSL2 backend** is the recommended setup.

## Prerequisites

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

## WSL2 Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `bad interpreter: No such file or directory` | CRLF line endings | Run `./scripts/setup.sh` (auto-fixes) or `sed -i 's/\r$//' images/sandbox/entrypoint.sh images/proxy/entrypoint.sh` |
| SSH "permissions are too open" | Key on NTFS filesystem (`/mnt/c/`) | Copy key to `~/.ssh/` and `chmod 600` |
| Very slow `docker compose build` | Project on `/mnt/c/` | Move project to `~/` (WSL2 native filesystem) |
| SSH "connection refused" from Windows | Hyper-V firewall blocking | PowerShell (admin): `Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow` |
| Docker won't start (iptables error) | Native Docker Engine + nftables | `sudo update-alternatives --set iptables /usr/sbin/iptables-legacy && sudo service docker restart` |

## Alternative Runtimes on WSL2

**Docker Desktop** (recommended): All safe-ai features work. Note that Docker Desktop defaults seccomp to `unconfined` at the daemon level — safe-ai is protected because it specifies an explicit seccomp profile, but be aware for other containers.

**Native Docker Engine in WSL2**: Works, but requires manual setup. Enable systemd in `/etc/wsl.conf`, switch iptables to legacy backend, and note that container ports are not auto-forwarded to Windows (use `wsl --shutdown` and reconnect if ports seem stuck).

**Podman in WSL2**: Functional but less reliable. Rootless Podman has known systemd race conditions on WSL2. Use `podman compose` (built-in), not `podman-compose`. See the Podman section above for verification steps.

#!/bin/bash
set -euo pipefail

# safe-ai sandbox entrypoint
# Generates SSH host keys into /tmp (root FS is read-only) and starts sshd.

# /run is tmpfs (empty at boot); sshd needs this for privilege separation
mkdir -p /run/sshd

# When /home/dev is a tmpfs mount, Docker creates .ssh as root:root.
# sshd StrictModes requires .ssh to be owned by the login user.
# Fix ownership of volume mounts (created as root by Docker).
# Use '|| true' because the root FS is read-only — only volume-backed
# dirs are writable.
for dir in /home/dev/.ssh /home/dev/.vscode-server; do
  if [ -d "$dir" ]; then
    chown dev:dev "$dir" 2>/dev/null || true
    # 0711: owner rwx, others --x (traverse only). Needed so root
    # (without DAC_READ_SEARCH) can reach authorized_keys.
    chmod 711 "$dir" 2>/dev/null || true
  fi
done

if [ ! -f /tmp/ssh_host_ed25519_key ]; then
  ssh-keygen -t ed25519 -f /tmp/ssh_host_ed25519_key -N "" -q
  ssh-keygen -t rsa -b 4096 -f /tmp/ssh_host_rsa_key -N "" -q
fi

exec /usr/sbin/sshd -D \
  -h /tmp/ssh_host_ed25519_key \
  -h /tmp/ssh_host_rsa_key \
  -o "PidFile=/tmp/sshd.pid"

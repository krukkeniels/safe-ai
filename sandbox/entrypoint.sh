#!/bin/bash
set -euo pipefail

# safe-ai sandbox entrypoint
# Generates SSH host keys into /tmp (root FS is read-only) and starts sshd.

# /run is tmpfs (empty at boot); sshd needs this for privilege separation
mkdir -p /run/sshd

# When /home/dev is a tmpfs mount, Docker creates .ssh as root:root.
# sshd StrictModes requires .ssh to be owned by the login user.
if [ -d /home/dev/.ssh ]; then
  # 0711: owner rwx, others --x (traverse only, no write).
  # StrictModes accepts no-write-for-others; root needs x-bit
  # to reach authorized_keys since CAP_DAC_READ_SEARCH is dropped.
  chmod 711 /home/dev/.ssh
  chown dev:dev /home/dev/.ssh
fi

if [ ! -f /tmp/ssh_host_ed25519_key ]; then
  ssh-keygen -t ed25519 -f /tmp/ssh_host_ed25519_key -N "" -q
  ssh-keygen -t rsa -b 4096 -f /tmp/ssh_host_rsa_key -N "" -q
fi

exec /usr/sbin/sshd -D \
  -h /tmp/ssh_host_ed25519_key \
  -h /tmp/ssh_host_rsa_key \
  -o "PidFile=/tmp/sshd.pid"

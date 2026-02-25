# safe-ai sandbox: Minimal, secure base image for AI coding agents.
#
# Extend with: FROM safe-ai-sandbox:latest
#
# Provides: Ubuntu 24.04, git, curl, ssh-server, basic dev tools
# Security: non-root user, read-only root (via compose), seccomp, no capabilities

FROM docker.io/library/ubuntu:24.04

LABEL org.opencontainers.image.title="safe-ai sandbox" \
      org.opencontainers.image.description="Sandboxed environment for AI coding agents" \
      org.opencontainers.image.source="https://github.com/safe-ai-project/safe-ai" \
      org.opencontainers.image.licenses="Apache-2.0"

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       git \
       openssh-server \
       curl \
       wget \
       jq \
       vim \
       nano \
       bash \
       build-essential \
       python3 \
       python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN userdel -r ubuntu 2>/dev/null || true \
    && useradd -m -s /bin/bash -u 1000 dev \
    && passwd -d dev \
    && mkdir -p /home/dev/.ssh \
    && chmod 700 /home/dev/.ssh \
    && chown -R dev:dev /home/dev

RUN mkdir -p /run/sshd /workspace \
    && chown dev:dev /workspace

# Proxy env vars for SSH login sessions (docker 'environment' only sets for PID 1)
RUN printf '%s\n' \
    'export http_proxy=http://proxy:3128' \
    'export https_proxy=http://proxy:3128' \
    'export HTTP_PROXY=http://proxy:3128' \
    'export HTTPS_PROXY=http://proxy:3128' \
    'export no_proxy=localhost,127.0.0.1' \
    'export NO_PROXY=localhost,127.0.0.1' \
    > /etc/profile.d/safe-ai-proxy.sh

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace
EXPOSE 22

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

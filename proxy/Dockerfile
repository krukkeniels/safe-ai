# safe-ai proxy: Squid sidecar for domain allowlist enforcement.
# Reads allowlist.yaml at startup and generates squid.conf.

FROM docker.io/library/alpine:3.20

RUN apk add --no-cache \
    squid \
    yq \
    bash \
    dnsmasq \
    socat \
    && mkdir -p /var/spool/squid /var/log/squid \
    && chown -R squid:squid /var/spool/squid /var/log/squid

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3128
EXPOSE 53/udp 53/tcp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

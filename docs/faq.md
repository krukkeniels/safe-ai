# Frequently Asked Questions

---

## Security

### Why doesn't safe-ai inspect HTTPS content?

MITM proxying creates its own risks (CA key management, breaking certificate pinning, plaintext exposure). safe-ai controls WHERE data goes via the domain allowlist. If data must not reach external LLMs, don't allowlist them.

### How does safe-ai enforce export control (ITAR/EAR) compliance?

Three independent network controls block external traffic: Docker `internal: true` removes the default gateway, dnsmasq returns NXDOMAIN for unlisted domains, Squid denies unlisted CONNECT requests. ITAR deployments use an empty external allowlist with a self-hosted LLM.

### How do you prove ITAR code was never sent externally?

Audit logs capture every allowed and denied proxy request. In an air-gapped config, logs show zero outbound connections. Combined with no default gateway and no external DNS, this is positive evidence of isolation.

### Is the allowlist just a policy document?

No. It is enforced by three independent technical controls (Docker internal network, dnsmasq DNS filtering, Squid ACLs). Blocked domains are unreachable.

### Why is build-essential in the sandbox?

Required for `pip install` (C extensions) and `npm install` (native modules). Compensating controls: seccomp limits what compiled code can do, read-only root prevents persistent implants, gVisor intercepts syscalls.

### Why can't I apt-get install at runtime?

Read-only root prevents persistent implants. Install tools via extended Dockerfiles (e.g., `examples/node.Dockerfile`).

### Is gVisor required?

Optional via `SAFE_AI_RUNTIME=runsc`. Recommended for defense work. Not mandatory because it's unavailable on some platforms (ARM, certain cloud VMs).

---

## Deployment

### What's the difference between self-service and managed mode?

**Self-service:** developer controls their environment. For individual use. **Managed:** platform team controls all configuration, developers only SSH in. Enterprise uses managed mode.

### Why isn't air-gap the default?

The default serves developers using cloud LLM APIs. ITAR/defense deployments use a different configuration. See the enterprise example.

### Does safe-ai scale past 50 developers?

Docker Compose is designed for single-host deployments. Beyond ~50 users, move to Kubernetes. safe-ai's security requirements (R1-R12) map to Kubernetes primitives.

### Why separate infrastructure per security tier?

You cannot mix ITAR and non-ITAR workloads on the same host and claim compliance. Separation IS the security control.

### Is logging mandatory?

Not in the compose file (would break self-service). For enterprise, always deploy with `--profile logging`. Run `make validate` to check.

---

## MCP Servers

### How does safe-ai handle MCP server traffic?

MCP servers make network requests like any other tool -- they go through the proxy and are subject to the domain allowlist. If an MCP server needs to reach `api.example.com`, that domain must be allowlisted. Unlisted domains are blocked.

### How should we evaluate MCP servers for enterprise use?

Treat MCP servers like any third-party dependency. Before approving one:

1. **Review the source** -- understand what network calls it makes and what data it sends
2. **Map its domains** -- identify every external endpoint it contacts and add only those to the allowlist
3. **Assess data exposure** -- determine what workspace data the MCP server can access and whether that data may reach external services
4. **Pin versions** -- use specific versions, not `latest`, to prevent supply chain surprises

### Can a malicious MCP server exfiltrate data?

Only to allowlisted domains. A compromised MCP server inside the sandbox is constrained by the same network controls as the AI agent itself -- it cannot reach domains not on the allowlist. This is why allowlist reviews should account for MCP server needs: every allowlisted domain is a domain ANY tool in the sandbox can reach.

### Should we run MCP servers inside or outside the sandbox?

**Inside** (default): the MCP server runs in the sandbox and is subject to all safe-ai controls (network, seccomp, capabilities). This is the secure default.

**Outside** (on host or separate service): the MCP server is not sandboxed. Only do this for trusted infrastructure MCP servers (e.g., internal database access) where the server needs network access the sandbox should not have.

### How do we manage allowlist growth from MCP servers?

Each MCP server may need additional domains. In managed deployments, maintain a per-MCP-server domain manifest documenting which domains each server requires and why. Review these during allowlist change requests. Consolidate where possible -- many MCP servers share common API endpoints.

### Can we inspect what data MCP servers send?

safe-ai logs request metadata (domain, bytes, status) for all proxy traffic, including MCP requests. It does not inspect HTTPS payload content. For sensitive environments, prefer MCP servers that connect to self-hosted services on the internal network, where you control both ends.

---

## Scope

### Does safe-ai satisfy NIST 800-171 / CMMC?

Partially. It covers controls within its scope (network isolation, access control, audit logging). Your CMMC assessment maps safe-ai alongside your SIEM, IdP, endpoint protection, etc.

### Does safe-ai need FedRAMP or FIPS 140-2?

No. FedRAMP is for cloud service providers. FIPS is a host OS concern. safe-ai uses the system's OpenSSH and TLS -- no custom cryptography.

### Why no LDAP/SAML/OIDC/MFA?

safe-ai is infrastructure isolation, not an identity platform. Identity federation belongs to the provisioning layer above safe-ai.

### Who handles secrets management (Vault/KMS)?

The platform team injects secrets from their secrets manager into the container environment. safe-ai uses standard Docker Compose environment variables. The gateway token never enters the sandbox.

### Who handles SIEM integration?

safe-ai ships structured JSON logs to Loki. Your SIEM (Splunk, Sentinel, etc.) ingests from Loki or Fluent Bit. safe-ai provides the data; you provide the SIEM.

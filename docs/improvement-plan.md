# safe-ai Improvement Plan

**Prioritized recommendations from a multi-agent security review against [AI Coding Agent Requirements](./ai-coding-agent-requirements.md)**

> Reviewed: 2026-03-07. Each item is scored by security impact and implementation effort. The plan favors simplicity -- no new services, no new dependencies, no over-engineering. Items are grouped into tiers by urgency.

---

## Summary

safe-ai's architecture is strong. Network isolation, seccomp whitelist, read-only root, capability drops, and gateway token injection are all well-implemented. The review found **no critical vulnerabilities** but identified a significant asymmetry: **the proxy container -- which holds secrets, has internet access, and is the sole egress path -- has no container-level hardening at all.** The sandbox is locked down; the proxy is wide open.

Beyond that, most findings are trivial one-line fixes, documentation gaps, or configuration tightening.

### Coverage at a glance

| Requirement | Current State | After This Plan |
|-------------|--------------|-----------------|
| R1 Network Egress | Strong | Strong (tightened) |
| R2 Sandbox Isolation | Strong | Strong (edge cases closed) |
| R3 Credential Separation | Good | Good (proxy hardened) |
| R4 Human Approval Gates | Not addressed | Partially addressed (git hook) |
| R5 Audit Logging | Good | Good (retention + alerting) |
| R6 Filesystem Scoping | Good | Good (risks documented) |
| R7 Resource Limits | Good | Good (risks documented) |
| R8 Supply Chain | Domain-level only | Domain-level + guidance |
| R9 Code Review | Not addressed | Partially (commit tagging) |
| R10 Data Classification | Policy doc only | Unchanged (adequate) |
| R11 Agent Identity | Partial | Improved (hostname + commits) |
| R12 Incident Response | Minimal | Documented runbook + tooling |

---

## Tier 1: Harden the Proxy (High Impact)

The proxy is internet-facing, runs as root, holds the gateway token, and has no `cap_drop`, no `seccomp`, no `read_only`, and no `no-new-privileges`. A vulnerability in Squid, dnsmasq, or socat gives an attacker root with full capabilities and direct internet access. This is the single most important improvement.

### 1.1 Add container hardening to the proxy service

**Why:** The proxy is the most security-critical component. Every other container is locked down; the proxy is not. This is an asymmetry in the security model -- the component that holds secrets and has internet access is the least protected.

**How:** Add to the proxy service in `docker-compose.yaml`: `cap_drop: ALL`, re-add only needed capabilities (NET_BIND_SERVICE for port 53, SETUID/SETGID for Squid worker), `security_opt: [no-new-privileges:true]`, and `read_only: true` with targeted tmpfs mounts for Squid spool, cache, and `/run`.

**Effort:** Medium | **Impact:** High | **Files:** `docker-compose.yaml`

### 1.2 Add connection limits to socat SSH forwarder

**Why:** The socat forwarder (`TCP-LISTEN:2222,fork,reuseaddr`) spawns a new process per connection with no limit. An attacker can exhaust the proxy's 128 PID limit, killing Squid and dnsmasq -- a denial-of-service that takes down all egress and DNS for the sandbox.

**How:** Add `max-children=10` to the socat options. One parameter.

**Effort:** Trivial | **Impact:** Medium | **Files:** `images/proxy/entrypoint.sh`

### 1.3 Add domain input validation in proxy entrypoint

**Why:** Domains from `allowlist.yaml` and `SAFE_AI_DEFAULT_DOMAINS` are written directly into `squid.conf` and `dnsmasq.conf` with no validation. A malicious domain string containing newlines or special characters could inject arbitrary Squid ACL rules or dnsmasq config.

**How:** Add a regex check before writing each domain: `[[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] || continue`. One line per processing loop.

**Effort:** Trivial | **Impact:** Medium | **Files:** `images/proxy/entrypoint.sh`

---

## Tier 2: Close Easy Security Gaps (Trivial Fixes)

Each of these is a one-line or few-line change with zero added complexity.

### 2.1 Remove dead `ssl_bump` directives from Squid config

**Why:** The proxy entrypoint generates `ssl_bump peek all` and `ssl_bump splice all`, but Alpine's Squid package is not compiled with SSL bump support (`--with-openssl`). These directives are dead code. The README and `enterprise-risk-mapping.md` claim SNI-based filtering is active when it is not -- HTTPS filtering actually relies on the CONNECT method's hostname. The security documentation is misleading.

**How:** Remove the two `ssl_bump` lines from the generated squid.conf. Update documentation to accurately describe CONNECT-based (not SNI-based) HTTPS filtering.

**Effort:** Trivial | **Impact:** Medium (documentation accuracy is a security property)

### 2.2 Suppress Squid information leakage headers

**Why:** Squid adds `Via: 1.1 safe-ai-proxy` and `X-Forwarded-For: 172.28.0.x` to outgoing requests by default. This leaks the proxy name and internal network topology to every upstream server (GitHub, npm, LLM APIs). Enables fingerprinting of safe-ai deployments.

**How:** Add `via off` and `forwarded_for delete` to the generated squid.conf. Two lines.

**Effort:** Trivial | **Impact:** Low | **Files:** `images/proxy/entrypoint.sh`

### 2.3 Add Squid connection timeout and upload size limits

**Why:** HTTPS CONNECT tunnels have no duration or size limits. A compromised agent can establish a persistent tunnel to an allowlisted domain and transfer unlimited data. Combined with `github.com` being allowlisted, a multi-gigabyte exfiltration via `git push` would succeed with no proxy-level limit.

**How:** Add reasonable defaults to the generated squid.conf: `connect_timeout 30 seconds`, `read_timeout 15 minutes`, `request_body_max_size 100 MB`.

**Effort:** Trivial | **Impact:** Medium | **Files:** `images/proxy/entrypoint.sh`

### 2.4 Lock the `dev` user account instead of deleting password

**Why:** `passwd -d dev` in the sandbox Dockerfile creates an account with an empty password, not a locked account. While `PasswordAuthentication no` blocks SSH password login today, anyone extending the Dockerfile or re-enabling PAM inherits an empty-password account.

**How:** Change `passwd -d dev` to `passwd -l dev`. One character change.

**Effort:** Trivial | **Impact:** Low | **Files:** `images/sandbox/Dockerfile`

### 2.5 Set `AddressFamily inet` in sshd_config

**Why:** `AddressFamily any` means sshd listens on IPv6. IPv6 link-local addressing works on Linux Docker bridges even without explicit IPv6 configuration, potentially allowing container-to-container communication outside the intended topology.

**How:** Change `AddressFamily any` to `AddressFamily inet`. One word.

**Effort:** Trivial | **Impact:** Low | **Files:** `images/sandbox/sshd_config`

### 2.6 Disable Grafana anonymous access and bind to localhost

**Why:** Grafana is exposed on port 3000 with anonymous read access and a default admin password of `admin`. Anyone reaching the host can view all audit logs and, with the default password, get full admin access.

**How:** Set `GF_AUTH_ANONYMOUS_ENABLED=false`. Bind the port to localhost: `127.0.0.1:${SAFE_AI_GRAFANA_PORT:-3000}:3000`. Change or remove the default password.

**Effort:** Trivial | **Impact:** Medium | **Files:** `docker-compose.yaml`

### 2.7 Shrink internal network subnet from /16 to /28

**Why:** A /16 subnet (65,534 addresses) for 2-5 containers is unnecessarily large. It increases the L2 attack surface for ARP spoofing.

**How:** Change `subnet: 172.28.0.0/16` to `subnet: 172.28.0.0/28`. One line. Adjust the proxy's static IP if needed (172.28.0.2 stays within /28).

**Effort:** Trivial | **Impact:** Low | **Files:** `docker-compose.yaml`

### 2.8 Remove `personality` syscall from seccomp profile

**Why:** The `personality` syscall allows disabling ASLR (`ADDR_NO_RANDOMIZE`) and enabling `READ_IMPLIES_EXEC` (all readable memory becomes executable). This makes exploitation of memory corruption bugs significantly easier. Most dev tools do not need it.

**How:** Remove `"personality"` from the seccomp profile's misc section. One line deletion.

**Effort:** Trivial | **Impact:** Low | **Files:** `config/seccomp.json`

---

## Tier 3: Improve Audit & Monitoring (Easy Wins)

### 3.1 Increase Loki retention to 90 days

**Why:** Current retention is 720h (30 days). R5.5 recommends 90+ days minimum. Forensic evidence could be lost if an incident is discovered weeks later.

**How:** Change `retention_period: 720h` to `retention_period: 2160h`. One line.

**Effort:** Trivial | **Impact:** Medium | **Files:** `config/logging/loki/loki-config.yaml`

### 3.2 Add a Grafana alert rule for denied request spikes

**Why:** The Grafana dashboard visualizes data but has no alerting. A burst of denied requests (probing/escape attempts) or unusual upload volumes (exfiltration) goes unnoticed unless someone is actively watching.

**How:** Add a provisioned alert rule JSON file for "denied requests > 10 in 5 minutes." This is the single highest-value automated detection.

**Effort:** Medium | **Impact:** Medium | **Files:** `config/logging/grafana/`

### 3.3 Fix `SAFE_AI_HOSTNAME` default for multi-developer audit

**Why:** `SAFE_AI_HOSTNAME` defaults to `safe-ai` in docker-compose.yaml. If multiple developers deploy without setting it, all logs are attributed identically, defeating per-developer audit trails. The Fluent Bit entrypoint already has a `$(hostname)` fallback that would give unique values.

**How:** Remove the hardcoded `safe-ai` default from docker-compose.yaml so the Fluent Bit fallback takes effect. One line change.

**Effort:** Trivial | **Impact:** Medium | **Files:** `docker-compose.yaml`

---

## Tier 4: Add Operational Tooling (Small Additions)

### 4.1 Ship a sample git pre-push hook

**Why:** This is the most impactful R4 (Human Approval Gates) control that safe-ai can provide at the infrastructure level. An agent can `git push` to GitHub (allowlisted) with no gate. A pre-push hook that prompts for confirmation is ~15 lines of bash and the only thing standing between "agent wrote code" and "code is on the shared remote."

**How:** Create `config/git/pre-push` hook script. Document installation via `git config core.hooksPath`.

**Effort:** Easy | **Impact:** High | **Files:** New file + README section

### 4.2 Add agent commit tagging via git config

**Why:** Commits from inside the sandbox are indistinguishable from human commits. In forensics or code review, you cannot identify which commits came from an AI agent. R9.4 and R11.2 both require this.

**How:** Add `git config --system user.name "dev (via safe-ai)"` and `git config --system user.email "dev@safe-ai.local"` to the sandbox Dockerfile. Users can override per-repo. One `RUN` line.

**Effort:** Trivial | **Impact:** Medium | **Files:** `images/sandbox/Dockerfile`

### 4.3 Add `make kill` and `make snapshot` targets

**Why:** In an incident, operators need a discoverable, correct kill switch. `docker compose down` works but doesn't stop logging containers; `docker compose down -v` destroys evidence. A snapshot command preserves the workspace for forensics.

**How:** Two Makefile targets:
- `kill`: `docker compose --profile logging down --remove-orphans`
- `snapshot`: One-liner using `docker run --rm` to tar the workspace volume.

**Effort:** Trivial | **Impact:** Medium | **Files:** `Makefile`

### 4.4 Add configurable upstream DNS

**Why:** dnsmasq hardcodes `8.8.8.8` / `8.8.4.4` as upstream resolvers. Enterprise environments require DNS through internal resolvers for policy enforcement. DNS queries to Google also leak which domains are in use.

**How:** Add a `SAFE_AI_DNS_UPSTREAM` env var (defaulting to `8.8.8.8`). Use it in the `server=` directives. Default behavior stays the same.

**Effort:** Easy | **Impact:** Medium (for enterprise users) | **Files:** `images/proxy/entrypoint.sh`, `docker-compose.yaml`, `.env.example`

---

## Tier 5: Documentation & Guidance (Zero-Code)

### 5.1 Create an incident response runbook

**Why:** No `docs/incident-response.md` exists. When something goes wrong, operators have no runbook.

**How:** A short document with 4 steps: Contain (`docker compose down`), Preserve evidence (volumes survive `down`), Analyze (review Squid logs for anomalies), Recover (rebuild, rotate credentials, review git history).

**Effort:** Trivial | **Impact:** High (at the exact moment it's needed)

### 5.2 Document the agent-vs-infrastructure responsibility boundary

**Why:** Users may assume safe-ai handles agent-level approval gates (R4). It does not. The sandbox prevents network escape and privilege escalation, but an agent can still delete workspace files, rewrite CI configs, or push to GitHub.

**How:** A README section or doc page explaining which controls are safe-ai's responsibility (network, isolation, audit) and which are the agent's (approval gates, tool restrictions, code review).

**Effort:** Trivial | **Impact:** Medium (prevents false security assumptions)

### 5.3 Add supply chain and MCP guidance

**Why:** R8 (Supply Chain) is partially addressed by the domain allowlist but users need to know: use lock files, prefer `npm ci` / `pip install --require-hashes`, and MCP servers are implicitly controlled by the allowlist.

**How:** A short README section or `docs/supply-chain.md`.

**Effort:** Trivial | **Impact:** Medium

### 5.4 Document accepted risks explicitly

**Why:** Several findings are inherent tradeoffs that cannot be fixed without disproportionate complexity: workspace volume has no size limit (Docker/ext4 limitation), rate limiting belongs at the gateway not the proxy, log tamper resistance requires architectural changes, interpreted scripts bypass noexec.

**How:** Add an "Accepted Risks" section to the README or `enterprise-risk-mapping.md` that explicitly calls out each tradeoff and its mitigation (e.g., "monitor `du -s /workspace` for disk exhaustion").

**Effort:** Trivial | **Impact:** Low (awareness, not enforcement)

---

## Items Considered and Rejected

These were evaluated but do not fit the project's simplicity philosophy:

| Item | Why Rejected |
|------|-------------|
| API rate limiting at proxy (Squid `delay_pools`) | Squid doesn't do request-count rate limiting. True rate limiting requires an additional component. Rate limiting belongs at the enterprise gateway (`SAFE_AI_GATEWAY_DOMAIN`). |
| Workspace volume size quotas | Requires XFS with project quotas or a loopback device. Docker's local driver doesn't support size limits on ext4. Document as accepted risk. |
| SAST/DAST integration (R9.2) | CI/CD pipeline concern, not sandbox concern. Out of scope. |
| PR workflow enforcement (R9.1) | GitHub/GitLab responsibility. Out of scope. |
| Per-plugin AppArmor/SELinux profiles (R7) | Requires MAC framework inside container. Disproportionate complexity. |
| Dependency install interception (R8.5) | Would require intercepting package manager commands. Fragile and agent-specific. |
| Full red-teaming framework (R12.4) | Out of scope. Recommend extending `scripts/test.sh` with 2-3 adversarial checks (DNS tunneling blocked, direct internet blocked, noexec works). |
| Block `memfd_create` in seccomp | May break Node.js and Python packages. Test before deciding. If workflows break, document as accepted risk. Consider offering an alternative "strict" seccomp profile. |
| Separate privileged init from sshd | Requires an init system (s6, tini) to drop privileges after setup. Moderate complexity for low incremental benefit given `no-new-privileges` already constrains escalation. |
| Squid stdout logging (log tamper fix) | Would simplify architecture (fewer volumes) but requires changing the entire Fluent Bit pipeline. Worth considering in a future rework, not now. |

---

## Implementation Order

For teams implementing this plan, the recommended order minimizes risk and maximizes early value:

1. **Tier 2 first** -- All trivial one-line fixes. Ship as a single commit. Immediate security improvement with zero risk of breakage.
2. **Tier 1.2 + 1.3** -- socat limits and domain validation. Still trivial, slightly more proxy-touching.
3. **Tier 1.1** -- Proxy hardening. Most impactful but needs testing (ensure Squid/dnsmasq/socat still work with reduced capabilities and read-only root).
4. **Tier 5** -- Documentation. Can be done in parallel with everything above.
5. **Tier 3** -- Logging improvements. Only relevant if `--profile logging` is in use.
6. **Tier 4** -- Operational tooling. Nice-to-have, ship when ready.

---

*Generated by multi-agent security review team. Reviewed against [AI Coding Agent Requirements](./ai-coding-agent-requirements.md) and [Enterprise Risk Mapping](./enterprise-risk-mapping.md). 2026-03-07.*

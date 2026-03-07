# safe-ai Enterprise Risk Mapping

**AI Risk-to-Mitigation Matrix for Enterprise Adoption**

> This document maps AI security risks to the controls safe-ai provides, identifies gaps, and gives enterprises a clear framework for deciding where to accept risk in favor of AI efficiency. Designed for CISO, security architecture, and compliance review.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Overview](#architecture-overview)
3. [OWASP Top 10 for LLM Applications -- Risk Mapping](#owasp-top-10-for-llm-applications----risk-mapping)
4. [Enterprise Decision Matrix](#enterprise-decision-matrix)
5. [Container Security Analysis](#container-security-analysis)
6. [Network Security Analysis](#network-security-analysis)
7. [Exfiltration Vector Assessment](#exfiltration-vector-assessment)
8. [Audit Logging & Monitoring](#audit-logging--monitoring)
9. [Hardening Roadmap](#hardening-roadmap)
10. [Risk Acceptance Checklist](#risk-acceptance-checklist)

---

## Executive Summary

safe-ai is a sandboxed container environment that lets enterprises deploy AI coding agents with defense-in-depth isolation. It enforces **network-layer allowlisting**, **filesystem immutability**, **syscall filtering**, and **audit logging** -- without requiring changes to the AI agent itself.

### What safe-ai does well

- **Network containment** is excellent. Docker's `internal: true` network, domain-level proxy allowlisting, and DNS filtering create three independent layers that all must fail for unauthorized egress.
- **Container hardening** is above industry standard. Whitelist-based seccomp (vs Docker's default blacklist), all capabilities dropped, read-only root, noexec tmpfs, no-new-privileges, and optional gVisor.
- **Audit trail** captures every proxy request (allowed and denied) with structured JSON metadata, shippable to central SIEM.
- **Gateway token injection** keeps API credentials out of the sandbox entirely.

### Where enterprises must make decisions

- **Content inspection is intentionally absent.** safe-ai does not MITM HTTPS traffic. It knows WHERE data goes but not WHAT is sent. Enterprises handling export-controlled, classified, or highly sensitive IP must layer content-level controls (DLP proxy, self-hosted LLM) or accept this risk.
- **The allowlist is the single most important policy artifact.** Every enterprise scenario -- from ITAR compliance to web search permissions -- reduces to "what domains are in allowlist.yaml." Treat it like a firewall rule set.
- **gVisor should be mandatory in enterprise deployments.** Without it, kernel exploits in allowed syscalls remain the primary container escape path.

### Coverage at a glance

| Domain | Coverage |
|--------|----------|
| Unauthorized network egress | Excellent |
| Container escape / privilege escalation | Strong (Excellent with gVisor) |
| Data exfiltration to allowlisted domains | Metadata-only detection |
| Content-level DLP | Not addressed (by design) |
| Supply chain (package security) | Domain-level only |
| Audit & forensics | Good for network; gap for in-sandbox activity |

---

## Architecture Overview

```
                    Internet
                       |
         +-------------+-------------+
         |     external network       |
         +-------------+-------------+
                       |
         +-------------+-------------+
         |  proxy (Squid + dnsmasq)  |  <- Dual-homed
         |  - Domain allowlist ACLs  |
         |  - CONNECT-based HTTPS    |
         |  - DNS filtering          |
         |  - Gateway token inject   |
         |  - JSON audit logging     |
         |  - SSH forwarding (socat) |
         +-------------+-------------+
                       |
         +-------------+-------------+
         |     internal network       |  <- Docker internal: true
         |     172.28.0.0/16          |     (NO default gateway)
         +-------------+-------------+
                       |
         +-------------+-------------+
         |  sandbox (dev environment) |
         |  - Read-only root FS      |
         |  - cap_drop: ALL          |
         |  - Seccomp whitelist      |
         |  - noexec /tmp, /run      |
         |  - no-new-privileges      |
         |  - Resource limits        |
         |  - Optional: gVisor       |
         +---------------------------+
```

**Key principle:** The sandbox has *no route to the internet*. All traffic is forced through the proxy, which enforces the allowlist. Even if the AI agent is fully compromised, it cannot bypass the network boundary.

---

## OWASP Top 10 for LLM Applications -- Risk Mapping

### Summary Table

| # | Risk | safe-ai Coverage | Key Controls |
|---|------|-----------------|--------------|
| LLM01 | Prompt Injection | PARTIALLY MITIGATED | Network isolation + seccomp limit blast radius; injection itself not prevented |
| LLM02 | Insecure Output Handling | MITIGATED | noexec /tmp, read-only root, seccomp, non-root user, gVisor |
| LLM03 | Training Data Poisoning | NOT ADDRESSED | Out of scope (runtime sandbox, not training pipeline) |
| LLM04 | Model Denial of Service | PARTIALLY MITIGATED | Memory/CPU/PID limits; no API-side rate limiting |
| LLM05 | Supply Chain Vulnerabilities | PARTIALLY MITIGATED | Registry allowlist; no per-package filtering |
| LLM06 | Sensitive Info Disclosure | MITIGATED | Gateway token injection, network isolation, audit logging |
| LLM07 | Insecure Plugin Design | PARTIALLY MITIGATED | OS-level constraints; no per-plugin authorization |
| LLM08 | Excessive Agency | MITIGATED | Read-only FS, allowlist, non-root, audit trail |
| LLM09 | Overreliance | PARTIALLY MITIGATED | Audit logging supports review; no enforcement of code review |
| LLM10 | Model Theft | PARTIALLY MITIGATED | Network isolation; no API rate limiting |

### Detailed Analysis

#### LLM01: Prompt Injection

**Threat:** Attacker-crafted inputs cause the LLM to execute unintended actions -- running shell commands, exfiltrating data, or pivoting to internal systems.

**safe-ai mitigation:** Network isolation (`docker-compose.yaml` -- `internal: true`) prevents the agent from reaching unauthorized destinations even if prompt injection succeeds. DNS filtering (dnsmasq `address=/#/`) returns empty for non-allowlisted domains. Seccomp whitelist (`config/seccomp.json` -- `SCMP_ACT_ERRNO` default) blocks dangerous syscalls. Capability drops (`cap_drop: ALL`) prevent privilege escalation. PID limit (512) prevents fork bombs.

**Residual risk:** Prompt injection itself is not prevented. The agent can still be tricked into destructive actions *within* the sandbox (deleting workspace files, corrupting code). Lateral movement and exfiltration are blocked.

**Recommendation:** Layer prompt injection detection at the LLM API gateway level. Use `SAFE_AI_GATEWAY_DOMAIN` to route through an enterprise gateway that performs content filtering.

#### LLM02: Insecure Output Handling

**Threat:** Malicious code in LLM output is executed without sanitization, leading to RCE or privilege escalation.

**safe-ai mitigation:** Read-only root (`docker-compose.yaml:50`) prevents system modification. noexec /tmp prevents binary execution from temp directories. Seccomp blocks dangerous syscalls even if malicious code runs. Non-root user (`dev`, UID 1000) limits damage. gVisor (optional) adds kernel-level isolation.

**Residual risk:** Malicious output can damage files in `/workspace`. Code injected into the workspace could be committed upstream if git credentials are available.

**Recommendation:** Mount `/workspace` with filesystem snapshots or use git hooks requiring human approval before push.

#### LLM03: Training Data Poisoning

**Threat:** Manipulation of training data to introduce backdoors or vulnerabilities.

**safe-ai mitigation:** Not addressed. safe-ai is a runtime sandbox, not a training pipeline.

**Recommendation:** Use model provenance verification, signed model artifacts, and SLSA framework attestation.

#### LLM04: Model Denial of Service

**Threat:** Inputs causing excessive resource consumption that degrades service.

**safe-ai mitigation:** Memory limit (8GB default), CPU limit (4 cores default), PID limit (512). Proxy capped at 256MB/1 CPU/128 PIDs. Squid caching disabled (`cache deny all`).

**Residual risk:** No rate limits on API calls to allowlisted endpoints. Agent could make excessive calls driving up costs.

**Recommendation:** Add Squid `delay_pools` or use the enterprise gateway for per-agent rate limits and cost budgets.

#### LLM05: Supply Chain Vulnerabilities

**Threat:** Compromised packages from npm, PyPI, or other registries.

**safe-ai mitigation:** Only `registry.npmjs.org`, `pypi.org`, and `files.pythonhosted.org` are reachable by default. Read-only root prevents system-level package modification. noexec /tmp blocks temp directory execution.

**Residual risk:** The allowlist trusts entire registries, not individual packages. Malicious npm post-install scripts execute within the sandbox.

**Recommendation:** Deploy internal package mirrors (Artifactory/Nexus) and remove public registries from the allowlist. Enforce lock files with integrity hashes.

#### LLM06: Sensitive Information Disclosure

**Threat:** LLM reveals API keys, credentials, PII, or proprietary code through outputs or exfiltration.

**safe-ai mitigation:** Gateway token injection (`images/proxy/entrypoint.sh:96-124`) keeps API tokens invisible to the agent. Anti-spoofing strips and re-adds the header. Network isolation prevents exfiltration to unauthorized destinations. Audit logging captures all request metadata.

**Residual risk:** Data can be exfiltrated to allowlisted domains within encrypted payloads (no MITM). Environment variables in `docker-compose.yaml` are visible to sandbox processes (except gateway tokens which are proxy-side only).

**Recommendation:** Enable HTTPS inspection (MITM) at the proxy for DLP if compliance requires it. Use `SAFE_AI_GATEWAY_DOMAIN` to channel all LLM traffic through an enterprise DLP-enabled gateway.

#### LLM07: Insecure Plugin Design

**Threat:** LLM plugins operate with excessive permissions or enable unintended actions.

**safe-ai mitigation:** All plugins execute within the sandbox, inheriting all security controls. Capability drops, seccomp, and network restriction apply uniformly.

**Residual risk:** No per-plugin authorization. All plugins share the same sandbox permissions and can access all workspace files.

**Recommendation:** Implement per-plugin AppArmor/SELinux profiles within the container. Add tool-use audit logging at the agent framework level.

#### LLM08: Excessive Agency

**Threat:** AI agents take destructive or irreversible actions without human approval.

**safe-ai mitigation:** Read-only root prevents system damage. Allowlist limits reachable services (8 domains by default). Non-root user with no-new-privileges. Audit trail enables post-hoc review.

**Residual risk:** Agent has full control over `/workspace` -- can delete files, rewrite code, or push to GitHub (allowlisted).

**Recommendation:** Implement workspace snapshotting. Add git pre-push hooks requiring human approval. Set up Grafana alerts for destructive operations.

#### LLM09: Overreliance

**Threat:** Blind trust of LLM outputs leading to deployment of buggy or insecure code.

**safe-ai mitigation:** Audit logging provides visibility into agent activity. Sandbox isolation creates a natural review boundary -- code must be explicitly extracted.

**Residual risk:** No enforcement of code review or testing before deployment.

**Recommendation:** Require PR-based workflows with mandatory human review. Integrate SAST/DAST scanning in CI.

#### LLM10: Model Theft

**Threat:** Exfiltration of model weights or extraction of model capabilities through systematic querying.

**safe-ai mitigation:** Network isolation prevents exfiltration of locally-loaded models. DNS filtering blocks tunneling. Audit logging tracks data transfer volumes.

**Residual risk:** Model extraction via systematic API querying is not rate-limited at the proxy level.

**Recommendation:** Use the enterprise gateway for API rate limits and model extraction detection. If local models are used, mount them read-only outside `/workspace`.

---

## Enterprise Decision Matrix

This matrix covers seven enterprise scenarios. For each: the risk level, what safe-ai provides today, what gaps remain, and the enterprise decision.

### Summary

| Scenario | Risk | Accept As-Is? | Key Action | Config Complexity |
|----------|------|---------------|------------|-------------------|
| Export-Controlled Code (ITAR/EAR) | CRITICAL | NO | Self-hosted LLM, air-gap | High |
| Classified/Restricted Data | CRITICAL | NO | Air-gap, per-compartment sandboxes | High |
| PII/GDPR Compliance | HIGH | WITH MITIGATIONS | EU endpoints, DPAs, synthetic data | Medium |
| Intellectual Property | HIGH | WITH MITIGATIONS | Enterprise LLM tiers, audit alerts | Low-Medium |
| Web Search (allow vs deny) | MEDIUM | CASE-BY-CASE | Scoped domain allowlist | Low |
| Supply Chain Security | HIGH | WITH MITIGATIONS | Internal mirrors, remove public registries | Medium |
| Multi-Tenancy / Team Isolation | MEDIUM | WITH MITIGATIONS | Separate hosts per classification, centralized policy | Medium-High |

### 1. Export-Controlled Code (ITAR/EAR)

**Risk Level: CRITICAL**

AI coding agents send code snippets to external LLM APIs as part of normal workflow. This constitutes an export under ITAR/EAR if the code is controlled.

**safe-ai controls:** Network allowlist restricts outbound to listed domains only. DNS filtering blocks non-allowlisted resolution. `internal: true` prevents proxy bypass. Audit logging records every request.

**Gaps:** No content inspection (CONNECT-based filtering only, no MITM). Controlled code WILL be sent to allowlisted LLM API endpoints. No DLP integration. No data classification tagging.

**Enterprise decision: DO NOT accept risk as-is.**

**Required configuration:**
```yaml
# allowlist.yaml for ITAR environments
domains:
  - llm.internal.defense-corp.com    # self-hosted LLM ONLY
  - nexus.internal.defense-corp.com  # internal package mirror
```
```bash
SAFE_AI_RUNTIME=runsc   # gVisor mandatory
```

### 2. Classified/Restricted Data

**Risk Level: CRITICAL**

Classified or compartmented data must not be exposed to external services. Different compartments may require different access levels.

**safe-ai controls:** Allowlist can be empty for full air-gap. Workspace scoped via bind mounts. Seccomp blocks escalation paths.

**Gaps:** No file-level access control within the sandbox -- agent reads everything in `/workspace`. No MAC (SELinux/AppArmor). No air-gap verification mechanism.

**Enterprise decision: DO NOT accept risk without significant hardening.**

**Required configuration:**
```yaml
# allowlist.yaml for classified environments
domains: []   # complete air-gap
```
```bash
SAFE_AI_RUNTIME=runsc
# Deploy one sandbox per compartment -- NEVER mix classifications
# Bind-mount only the specific project directory:
#   /classified/project-alpha:/workspace:rw
```

### 3. PII/GDPR Compliance

**Risk Level: HIGH**

Codebases contain PII in config files, test fixtures, and logs. GDPR requires data residency and right-to-erasure compliance.

**safe-ai controls:** Allowlist controls which endpoints receive data. Gateway token injection reduces credential correlation risk. Volumes can be destroyed for data lifecycle.

**Gaps:** No PII scanning or redaction. No data residency enforcement (domain != geography). No right-to-erasure workflow for data sent to LLM providers.

**Enterprise decision: ACCEPT WITH MITIGATIONS.**

**Required configuration:**
```yaml
domains:
  - eu.api.openai.com              # EU-region endpoint only
  - europe-west1-aiplatform.googleapis.com
  - github.com
```
```bash
docker compose --profile logging up -d   # audit trail for compliance evidence
SAFE_AI_LOKI_URL=http://siem.eu.internal:3100
```
Also: mandate synthetic test data, execute DPAs with LLM providers.

### 4. Intellectual Property Protection

**Risk Level: HIGH**

Proprietary algorithms and trade secrets may be sent to LLM providers as prompt context.

**safe-ai controls:** Allowlist limits recipients. Audit logs capture domain, byte counts, timestamps. Gateway tokens keep credentials separate. Network isolation blocks unauthorized channels.

**Gaps:** No content-level audit (HTTPS encrypted). No egress volume alerting built in. LLM provider training use depends on contract.

**Enterprise decision: ACCEPT WITH MITIGATIONS.**

Key actions: Use enterprise LLM tiers with zero-retention guarantees. Configure Grafana alerts on data transfer volumes. Self-host LLMs for crown-jewel IP.

### 5. Web Search: Allow vs Deny

**Risk Level: MEDIUM**

| Factor | Allow (scoped) | Deny |
|--------|---------------|------|
| Use case | General development, open-source | Export control, classified, financial |
| Productivity | High -- AI looks up docs, examples | Medium -- local context only |
| Data leakage | Medium -- search queries may contain code | Low -- no outbound data |
| Audit complexity | Higher -- more domains | Lower -- fewer events |

**Enterprise decision: CASE-BY-CASE based on data classification.**

**Configuration for scoped web search:**
```yaml
domains:
  - api.anthropic.com
  - github.com
  - stackoverflow.com
  - docs.python.org
  - developer.mozilla.org
  # DO NOT add google.com -- too broad (includes Drive, Gmail, etc.)
```

**Configuration for denied web search:**
```yaml
domains:
  - api.anthropic.com   # LLM API only
```

### 6. Supply Chain Security

**Risk Level: HIGH**

Default allowlist includes npm and PyPI. AI agents may install packages, creating exposure to typosquatting and malicious packages.

**safe-ai controls:** Domain-level registry restriction. Read-only root prevents system modification. noexec /tmp blocks temp execution. PID limits constrain fork bombs.

**Gaps:** No per-package filtering. No integrity verification enforcement. No built-in internal mirror support.

**Enterprise decision: ACCEPT WITH MITIGATIONS.**

**Required configuration:**
```yaml
# Replace public registries with internal mirrors
domains:
  - api.anthropic.com
  - github.com
  - nexus.corp.example.com     # internal npm + PyPI mirror (scanned)
  # registry.npmjs.org REMOVED
  # pypi.org REMOVED
```

### 7. Multi-Tenancy / Team Isolation

**Risk Level: MEDIUM**

Multiple teams on shared infrastructure need different security requirements.

**safe-ai controls:** Per-instance allowlist via `SAFE_AI_ALLOWLIST`. Per-instance audit labels via `SAFE_AI_HOSTNAME`. Separate compose stacks on isolated networks.

**Gaps:** No centralized multi-tenant orchestration. Shared Docker daemon. No allowlist policy enforcement. Log segregation depends on Grafana RBAC.

**Enterprise decision: ACCEPT WITH MITIGATIONS for teams at similar classification levels.**

Key actions: Separate hosts per classification level. Distribute allowlists via configuration management. Set gVisor as daemon default (`install-gvisor.sh --default`).

---

## Container Security Analysis

### Defense-in-Depth Layers

| Layer | Control | Prevents | Bypass Requires |
|-------|---------|----------|-----------------|
| L1 | Seccomp whitelist | Dangerous syscalls (ptrace, mount, bpf, unshare, io_uring, kernel modules) | Kernel vuln in allowed syscall |
| L2 | cap_drop ALL + 5 minimal | No namespace manipulation, no raw network, no kernel modules | Would need CAP_SYS_ADMIN |
| L3 | no-new-privileges | setuid/setgid escalation, execve privilege gain | N/A (kernel-enforced) |
| L4 | Read-only rootfs | System binary modification, backdoor installation | Write to volumes/tmpfs only |
| L5 | noexec tmpfs | Binary execution from /tmp and /run | Interpreted scripts, memfd_create |
| L6 | Network isolation | Direct internet, host network, metadata services | Allowlisted domains only |
| L7 | Resource limits | Fork bombs, OOM, CPU starvation | Disk exhaustion via volumes |
| L8 | SSH hardening | Brute force, unauthorized access | Stolen SSH key |
| L9 | gVisor (optional) | Kernel exploits, syscall-based escapes | gVisor-specific vulnerabilities |
| L10 | Non-root user | Intra-container privilege abuse | Root process (sshd) still exists |
| L11 | Audit logging | Undetected activity (post-incident forensics) | Only if logging profile enabled |

### Seccomp Profile: safe-ai vs Docker Default

safe-ai uses a **whitelist** (default DENY, allow specific calls). Docker's default uses a **blacklist** (default ALLOW, deny specific calls). This is significantly more restrictive. Key additional blocks:

| Blocked Syscall | Attack Prevented |
|----------------|-----------------|
| `ptrace` | Process injection, credential theft |
| `mount` / `umount2` | Filesystem escape via bind mounts |
| `bpf` | eBPF kernel manipulation |
| `unshare` / `setns` | Namespace escape |
| `kexec_load` | Kernel replacement |
| `io_uring_*` | Major source of kernel vulnerabilities |
| `userfaultfd` | Use-after-free exploitation primitive |
| `perf_event_open` | Side-channel attacks |
| `init_module` / `finit_module` | Kernel module loading |

### Capability Analysis

ALL capabilities dropped. Five re-added for sshd operation:

| Capability | Purpose | Risk |
|-----------|---------|------|
| SETUID | sshd user switching | Constrained by no-new-privileges |
| SETGID | sshd group switching | Constrained by no-new-privileges |
| SYS_CHROOT | sshd privsep | Cannot escape without SYS_ADMIN |
| NET_BIND_SERVICE | sshd port 22 | Can bind privileged ports |
| CHOWN | sshd file management | Can change ownership |

These are minimal and well-justified. The `no-new-privileges` flag neutralizes the escalation risk from SETUID/SETGID.

### Filesystem Writable Surfaces

| Path | Type | Exec? | Size Limit | Risk |
|------|------|-------|-----------|------|
| `/workspace` | Named volume | Yes | **Unlimited** | Primary attack surface; disk exhaustion possible |
| `/home/dev/.vscode-server` | Named volume | Yes | **Unlimited** | VS Code binaries stored here |
| `/tmp` | tmpfs | No | 2GB | Write-only; interpreted scripts still work |
| `/run` | tmpfs | No | 64MB | Minimal |

### Known Gaps

1. **`memfd_create` + `execve`**: Allowed in seccomp profile. Enables fileless execution -- write ELF to anonymous memory fd and execute it, bypassing all noexec restrictions.
2. **Workspace volume has no size limit**: Disk exhaustion attack via `/workspace` is possible.
3. **Interpreted script execution**: `bash /tmp/script.sh` and `python3 /tmp/exploit.py` work despite noexec (noexec only blocks direct ELF execution).

### Container Escape Assessment

| Vector | Status | Notes |
|--------|--------|-------|
| Docker socket | NOT EXPOSED | Not mounted into any container |
| Shared namespaces | ISOLATED | No --pid/network/ipc=host |
| Device access | BLOCKED | No --privileged, no --device |
| /proc /sys | DEFAULT MASKED | Sensitive paths masked by Docker |
| Kernel exploits | POSSIBLE (runc) / BLOCKED (gVisor) | Primary remaining escape path |

**Risk rating:** With runc: **Medium**. With gVisor: **Low**.

---

## Network Security Analysis

### Isolation Architecture

The sandbox sits on a Docker `internal: true` network. At the kernel level, Docker implements this by not creating a default gateway route and adding iptables DROP rules for bridge-to-external traffic. The proxy is dual-homed (internal + external) and is the sole egress path.

### Proxy Controls (Squid)

| Control | Implementation | Effect |
|---------|---------------|--------|
| Domain allowlist | `dstdomain` ACLs from allowlist.yaml | Only listed domains reachable |
| HTTPS filtering | CONNECT-based HTTPS filtering (no MITM) | Matches hostname from CONNECT method without decrypting |
| Port restriction | Safe_ports (80, 443 only) | No connections to non-standard ports |
| CONNECT restriction | SSL_ports (443 only) | No tunnels to non-HTTPS ports |
| Default deny | `http_access deny all` | Everything not explicitly allowed is blocked |
| No caching | `cache deny all` | Proxy is access control only |

### DNS Filtering (dnsmasq)

- **Default behavior:** `address=/#/` returns empty for ALL domains
- **Allowlisted domains:** Individual `server=/domain/8.8.8.8` entries forward only listed domains
- **Sandbox DNS:** Hardcoded to `172.28.0.2` (proxy container)
- **DNS tunneling:** Effectively blocked -- only allowlisted domains are forwarded

### Gateway Token Security

The proxy injects `X-Safe-AI-Token` headers for requests to the gateway domain. Anti-spoofing (`request_header_access X-Safe-AI-Token deny all`) strips any sandbox-originated headers before re-adding the legitimate token. The sandbox never sees the token.

**Gap:** When using env vars (`SAFE_AI_GATEWAY_TOKEN`), the token is visible in `docker inspect`. The baked-image approach (`gateway-proxy.Dockerfile`) is more secure but stores the token in image layer history. Recommendation: use BuildKit `--secret` instead of `ARG`.

### SSH Forwarding

socat forwards port 2222 (proxy) to port 22 (sandbox). This is required because `internal: true` networks don't support Docker port publishing.

**Gap:** `AllowTcpForwarding yes` in sshd_config allows SSH port forwarding. While tunneled traffic still goes through Squid, this is unnecessary attack surface. Recommendation: set to `local` or `no` unless VS Code Remote requires it.

---

## Exfiltration Vector Assessment

| Vector | Risk | Logged? | Detection |
|--------|------|---------|-----------|
| Direct internet from sandbox | Very Low | N/A | Blocked by internal:true |
| Non-allowlisted domains | Very Low | Yes (denied) | Squid access log |
| Data in API request bodies to allowlisted domains | **High** | Byte count only | Volume anomaly detection |
| Git push to github.com | **High** | Byte count only | Upload volume monitoring |
| DNS tunneling | Very Low | Partial | dnsmasq filters non-allowlisted |
| ICMP covert channels | None | N/A | No CAP_NET_RAW |
| HTTP header encoding | Low | No | Tiny bandwidth, impractical |
| Timing-based channels | Very Low | No | Theoretical only |
| SSH tunnel abuse | Medium | No | AllowTcpForwarding is on |
| Domain fronting | Medium | No | Depends on CDN behavior |

**Key insight:** The highest-risk exfiltration path is via normal API calls to allowlisted domains. safe-ai logs the metadata (domain, bytes, timing) but cannot inspect encrypted payloads. This is an explicit design tradeoff -- no MITM means no content visibility but also no privacy invasion.

---

## Audit Logging & Monitoring

### What IS Logged

Every Squid proxy request is logged as structured JSON:
```json
{
  "timestamp": "07/Mar/2026:10:30:45 -0500",
  "duration_ms": 123,
  "client_ip": "172.28.0.3",
  "method": "CONNECT",
  "url": "api.anthropic.com:443",
  "http_status": 200,
  "squid_action": "TCP_TUNNEL",
  "request_bytes": 500,
  "response_bytes": 12000,
  "sni": "api.anthropic.com"
}
```

Pipeline: Squid JSON log -> Fluent Bit (buffered, position-tracked) -> Loki -> Grafana dashboard.

### What is NOT Logged

| Gap | Impact | Recommendation |
|-----|--------|---------------|
| HTTPS payload content | Cannot inspect what data is sent | Deploy upstream DLP proxy or self-hosted LLM |
| Sandbox internal activity | No visibility into file access, process execution | Add process monitoring sidecar |
| DNS queries | dnsmasq logs to stdout but not shipped to Loki | Add second Fluent Bit input for DNS logs |
| SSH session content | socat is a dumb forwarder | Add terminal session recording |
| Failed SSH auth | sshd logs inside container, not shipped | Ship sshd auth logs to pipeline |
| Seccomp violations | SCMP_ACT_ERRNO is silent | Use SCMP_ACT_LOG for audit (requires kernel support) |
| Container lifecycle | Docker start/stop/restart not captured | Monitor Docker events API |

### Log Integrity

- **Tamper risk:** squid-logs volume is writable by the proxy. A compromised proxy could falsify log entries.
- **Loki auth:** Disabled by default (`auth_enabled: false`). Any container on the internal network could push fake logs.
- **No log signing:** Logs are not cryptographically chained.

**Recommendation:** For high-security environments, ship logs to an external append-only store. Enable Loki authentication. Consider hash-chaining for tamper detection.

### Recommended Grafana Alerts

| Alert | Condition | Detects |
|-------|-----------|---------|
| Denied request spike | >10 denied requests in 5 min | Probing / escape attempts |
| Unusual upload volume | >10MB upload to single domain in 1 hour | Data exfiltration |
| New User-Agent | Previously unseen UA string | Unauthorized tool usage |
| Off-hours activity | Requests outside business hours | Unauthorized access |
| Large response | `response_bytes > 1MB` | Potential bulk data access |

---

## Hardening Roadmap

Prioritized by impact. Items are additive -- each builds on previous layers.

### Tier 1: Mandatory for Enterprise (Day 1)

| # | Action | Effort | Impact |
|---|--------|--------|--------|
| 1 | Enable gVisor (`SAFE_AI_RUNTIME=runsc`) | Low | Eliminates kernel exploit escape path |
| 2 | Enable audit logging (`--profile logging`) | Low | Visibility into all proxy activity |
| 3 | Scope allowlist to minimum required domains | Low | Reduces exfiltration surface |
| 4 | Use gateway token injection (not env vars for API keys) | Low | Keeps credentials out of sandbox |
| 5 | Set `SAFE_AI_HOSTNAME` per workstation | Low | Enables per-developer audit trail |

### Tier 2: Recommended for Sensitive Environments (Week 1)

| # | Action | Effort | Impact |
|---|--------|--------|--------|
| 6 | Deploy internal package mirrors, remove public registries | Medium | Supply chain protection |
| 7 | Configure Grafana alerting rules (see table above) | Medium | Active threat detection |
| 8 | Ship logs to central SIEM | Medium | Org-wide visibility and correlation |
| 9 | Add `enable_ipv6: false` to internal network | Low | Close IPv6 gap |
| 10 | Set `AllowTcpForwarding local` in sshd_config | Low | Prevent SSH tunnel abuse |

### Tier 3: High Security / Regulated Environments (Month 1)

| # | Action | Effort | Impact |
|---|--------|--------|--------|
| 11 | Deploy self-hosted LLM, remove external API domains | High | Eliminates data leaving the org |
| 12 | Add DLP proxy upstream of Squid for content inspection | High | Payload-level exfiltration detection |
| 13 | Add volume size limits (XFS quotas) | Medium | Prevent disk exhaustion |
| 14 | Block `memfd_create` in seccomp or monitor it | Low | Prevent fileless execution |
| 15 | Ship dnsmasq + sshd logs to audit pipeline | Medium | Close monitoring gaps |
| 16 | Add seccomp audit mode (`SCMP_ACT_LOG`) for blocked calls | Low | Detect escape attempts |
| 17 | Centralize allowlist management via config management (Ansible/Puppet) | Medium | Prevent team-level policy bypass |
| 18 | Use BuildKit `--secret` for gateway tokens | Low | Remove token from image layer history |

---

## Risk Acceptance Checklist

Use this checklist when deploying safe-ai in your organization. For each item, document whether your enterprise **accepts the residual risk** or **adds additional controls**.

### Network & Data Flow

- [ ] **Allowlisted domains reviewed and approved** by security team
  - _Each domain is a potential exfiltration path. Treat like firewall rules._
- [ ] **Decision on web search**: Allow (scoped domains) / Deny
  - _Allow increases productivity; deny reduces data leakage risk._
- [ ] **Decision on package registries**: Public / Internal mirror / Air-gapped
  - _Public registries expose to supply chain attacks._
- [ ] **LLM API provider selection**: External / Self-hosted / Enterprise gateway
  - _External means code reaches third-party servers._
- [ ] **Exfiltration via allowlisted domains**: Accepted risk / MITM proxy / Self-hosted LLM
  - _Data in encrypted API calls is invisible to safe-ai._

### Container Isolation

- [ ] **gVisor enabled** (`SAFE_AI_RUNTIME=runsc`)
  - _Without gVisor, kernel exploits are the primary escape path._
- [ ] **Resource limits reviewed** (memory, CPU, PID, disk)
  - _Default: 8GB/4CPU/512 PIDs. No disk limit on /workspace._
- [ ] **memfd_create risk accepted** or blocked in seccomp
  - _Allows fileless execution bypassing noexec restrictions._

### Audit & Monitoring

- [ ] **Audit logging enabled** (`--profile logging`)
  - _Without it, there is no visibility into proxy activity._
- [ ] **Central SIEM integration** configured
  - _Local-only logs have no off-host backup._
- [ ] **Grafana alerting** configured for anomalies
  - _Logs without alerts are forensics-only._
- [ ] **Log retention period** defined (recommend: 90+ days)
  - _Required for compliance and incident response._

### Data Classification

- [ ] **Export-controlled code**: NOT in sandbox / Self-hosted LLM only
- [ ] **Classified data**: Air-gapped / Per-compartment sandboxes
- [ ] **PII**: EU endpoints / Synthetic test data / DPAs in place
- [ ] **Intellectual property**: Enterprise LLM tier / Zero-retention agreement

### Organizational

- [ ] **Allowlist change management** process defined
  - _Who can modify allowlist.yaml? How are changes reviewed?_
- [ ] **Incident response** plan for sandbox compromise
  - _What happens if an agent behaves unexpectedly?_
- [ ] **Developer onboarding** documentation for safe-ai usage
  - _Developers need to understand what is and isn't protected._

---

*Document generated by safe-ai security review team. Last updated: 2026-03-07.*

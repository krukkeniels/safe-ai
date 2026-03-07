# Enterprise Mitigation Guide: AI Coding Agent Security for Defense Sector

**Version:** 1.0
**Date:** 2026-03-07
**Classification:** CUI // NOFORN (apply appropriate marking)
**Document Owner:** Security Architecture Team
**Review Cadence:** Quarterly
**Applicability:** 3 departments, 12 teams, 120 developers

**Toolchain:** Bitbucket Data Center (on-prem) | Sonatype Nexus Repository Manager | Microsoft Azure AI Foundry (Azure Government)

**Compliance basis:** DFARS 252.204-7012, NIST SP 800-171, CMMC 2.0 Level 2

**Related documents:**
- [AI Coding Agent Security Requirements](ai-coding-agent-requirements.md) -- source framework (R1-R12)
- [Enterprise Risk Mapping](enterprise-risk-mapping.md) -- OWASP mapping and exfiltration analysis
- [Incident Response Runbook](incident-response.md) -- 4-phase IR procedure
- [Responsibility Boundary](responsibility-boundary.md) -- safe-ai scope vs enterprise scope

---

## 1. Executive Summary

AI coding agents are privileged actors in the software development lifecycle. They execute arbitrary code, access source repositories, install packages, and interact with LLM APIs. In defense environments operating under DFARS 7012, every LLM API call transmitting CUI-derived code constitutes a controlled data flow. The agent itself holds no clearance, has no accountability, and -- if compromised -- can exfiltrate controlled technical data to any allowlisted destination within seconds.

safe-ai provides infrastructure-level controls: network isolation, container sandboxing, credential separation, and audit logging. This guide defines the **enterprise-level controls** that must wrap around safe-ai to satisfy R1-R12 for a 120-developer defense organization using Bitbucket Data Center, Sonatype Nexus, and Azure AI Foundry.

### Coverage Summary

| # | Requirement | safe-ai Baseline | Enterprise Must Add | Primary Toolchain |
|---|------------|-----------------|--------------------|--------------------|
| R1 | Network Egress | Docker internal:true, Squid proxy, dnsmasq | VNet private endpoints, internal-only allowlist | Azure AI Foundry, Nexus |
| R2 | Sandbox Isolation | Seccomp whitelist, cap_drop ALL, read-only root | Compensating controls (gVisor blocked by Docker Desktop); dedicated hosts per classification | Docker Desktop, Hyper-V |
| R3 | Credential Separation | Gateway token injection, anti-spoofing | Managed Identity, deploy keys, Vault rotation | Azure AD, Bitbucket |
| R4 | Human Approval Gates | Git pre-push hook | Branch permissions, merge checks, tiered autonomy | Bitbucket |
| R5 | Audit Logging | Fluent Bit, Loki, Grafana | Multi-tenancy, SIEM integration, 7-year retention | Loki, Azure Monitor |
| R6 | Filesystem Scoping | Named workspace volume | Per-project mounts, XFS quotas, encrypted snapshots | Docker, Azure Blob |
| R7 | Resource Limits | Memory/CPU/PID cgroups | Volume quotas, API rate limits, cost alerts | Azure AI Foundry |
| R8 | Supply Chain | Domain allowlist | Nexus IQ Firewall, staged promotion, lock files | Nexus |
| R9 | Code Review | Agent commit tagging | Default reviewers, SAST, security-file webhooks | Bitbucket, SonarQube |
| R10 | Data Classification | Allowlist enforcement | Project tagging, per-tier profiles, DLP, training | Bitbucket, Purview |
| R11 | Agent Identity | SAFE_AI_HOSTNAME, git user.name | Service accounts, Co-Authored-By, Loki tenancy | Bitbucket, Loki |
| R12 | Incident Response | make kill, make snapshot, runbook | DFARS 72hr reporting, evidence custody, red-teaming | SOC, DIBNet |

---

## 2. Risk Posture Summary

### Risks Mitigated

| Risk | Threat | Mitigation | Coverage | Residual |
|------|--------|------------|----------|----------|
| Unauthorized network egress | Code exfiltration, CUI leakage to internet | Docker `internal: true` (no default gateway) + Squid domain ACLs + dnsmasq DNS filtering. Three independent layers -- all must fail for egress. | **95%** | Exfiltration to allowlisted domains remains possible (see Accepted Risks) |
| Container escape via privilege escalation | Host compromise, lateral movement | cap_drop ALL + no-new-privileges + non-root user + read-only root. No setuid/setgid exploitation path. | **90%** | Kernel exploits in allowed syscalls (see gVisor gap below) |
| Credential theft | API key exfiltration, secret leakage | Gateway token injection at proxy -- credentials never enter sandbox. Managed Identity eliminates API keys for Azure AI Foundry. Anti-spoofing strips forged headers. | **90%** | Tokens visible in `docker inspect` env vars (mitigate with Vault/BuildKit secrets) |
| Malicious package installation | Supply chain compromise, slopsquatting | Nexus IQ Firewall auto-quarantines vulnerable packages. Staged promotion (dev/test/prod). Lock file enforcement via pre-receive hook. Only internal registries reachable. | **85%** | Zero-day vulnerabilities not yet in Nexus IQ database |
| Unaudited agent activity | Forensics gaps, compliance failures | Structured JSON logging of all proxy traffic (allowed + denied). Fluent Bit ships to Loki with per-department tenancy. Azure Monitor captures LLM API calls. 90-day hot + 7-year cold retention. | **85%** | In-sandbox activity (file access, process execution) not logged. HTTPS payload content not inspectable. |
| Unauthorized code push | Unreviewed code in protected branches | Bitbucket branch permissions (2 approvals on main/develop). Agent service accounts blocked from direct push via pre-receive hook. SAST scan required as merge check. | **85%** | Approval fatigue at scale -- mitigated by risk-based routing and reviewer rotation |
| DNS tunneling | Covert data exfiltration | dnsmasq returns empty responses for all non-allowlisted domains. No recursive resolution. | **95%** | None significant |
| Fork bomb / resource exhaustion | Denial of service | Memory (8GB), CPU (4), PID (512) cgroup limits. Azure AI Foundry TPM/RPM rate limits. | **80%** | Disk exhaustion (no volume quota on ext4/Docker Desktop) |
| Syscall-based escape | Kernel exploitation | Seccomp whitelist (default-DENY). Blocks ptrace, mount, bpf, unshare, io_uring, kernel modules. Only ~60 syscalls permitted. | **80%** | Exploits in allowed syscalls (mitigated by gVisor in Iteration 2) |
| CUI spillage across projects | Regulatory violation, classification contamination | Per-project workspace mounts. Per-classification allowlist profiles. Separate Docker Desktop instances per IL level. Purview DLP on LLM prompts. | **80%** | Developer error (wrong project in wrong sandbox) -- mitigated by training and AD group checks |

### Risks Accepted

These risks are **not fully mitigated** by safe-ai + enterprise controls in the current iteration. Each is documented with its risk level, rationale, and compensating controls.

| # | Accepted Risk | Level | Rationale | Compensating Controls |
|---|--------------|-------|-----------|----------------------|
| A1 | **No gVisor kernel isolation** | MEDIUM | Docker Desktop on Windows 11 / WSL2 does not support custom OCI runtimes. Kernel exploits in the ~60 allowed syscalls remain the primary container escape path. | Seccomp whitelist + cap_drop ALL + no-new-privileges + read-only root provide defense-in-depth. Keep Docker Desktop and WSL2 kernel updated within 7 days. Hyper-V isolation where supported. Plan migration to native Linux hosts (Iteration 2). |
| A2 | **Workspace file access** | MEDIUM | The agent has full R/W on `/workspace`. It can delete files, rewrite code, corrupt git history, or embed backdoors. This is inherent to its function. | Git pre-push hook requires human confirmation. Bitbucket branch protection prevents unreviewed merges. Daily workspace snapshots to encrypted Azure Blob. `make snapshot` for ad-hoc forensics. |
| A3 | **Exfiltration to allowlisted domains** | MEDIUM | Code sent to Azure AI Foundry is HTTPS-encrypted. Metadata (domain, bytes, timing) is logged but content is not inspectable without MITM. An attacker who controls the agent can encode data in legitimate-looking API calls. | Azure AI Foundry VNet private endpoint keeps traffic within Azure Government boundary. Grafana alerts on unusual upload volume (>10MB/hr). Azure Monitor logs all API requests. No external LLM APIs in allowlist. |
| A4 | **Interpreted script execution** | LOW | noexec on `/tmp` only blocks direct ELF binary execution. `bash /tmp/script.sh` and `python3 /tmp/exploit.py` still execute. | Constrained by network isolation (scripts cannot reach unauthorized destinations) and seccomp (scripts cannot use dangerous syscalls). The blast radius is limited to `/workspace` manipulation. |
| A5 | **memfd_create fileless execution** | LOW | The `memfd_create` syscall is allowed (required by Node.js, some Python packages). It enables writing an ELF binary to anonymous memory and executing it, bypassing noexec. | Network isolation limits what a fileless payload can do. Seccomp blocks dangerous syscalls regardless of execution method. Evaluate blocking `memfd_create` if toolchain testing confirms it is not needed. |
| A6 | **Approval fatigue** | MEDIUM | 120 developers reviewing agent-generated PRs will develop review fatigue over time. This is organizational, not technical. | Risk-based routing: only security-critical file changes escalate to security team. Rotating reviewers distribute load. CODEOWNERS-based routing sends reviews to the owning team, not everyone. Target: <10% of changes require manual escalation. |
| A7 | **Agent commit attribution gaps** | LOW | Co-Authored-By trailers and service accounts provide attribution, but a developer could bypass by committing directly (not through the agent). Git trailers are not cryptographically bound. | GPG commit signing enforcement in Bitbucket. Pre-receive hook validates service account commit format. Loki proxy logs provide independent correlation. NIST Agent Standards (when finalized) may provide stronger identity binding. |
| A8 | **HTTPS payload opacity** | LOW | safe-ai does not perform MITM inspection of HTTPS traffic. The content of API calls to Azure AI Foundry is not visible in proxy logs. This is a deliberate design decision -- MITM adds certificate management burden and privacy risk. | Azure AI Foundry diagnostic logging (RequestResponse category) captures prompt/response content within the Azure boundary. Purview DLP scans for CUI patterns. Metadata-level monitoring (bytes, timing, frequency) detects anomalies. |

### Risk Matrix

```
                    LOW IMPACT          MEDIUM IMPACT         HIGH IMPACT
                ┌─────────────────┬─────────────────────┬──────────────────┐
  HIGH          │                 │                     │                  │
  LIKELIHOOD    │                 │  A6 Approval        │                  │
                │                 │     fatigue         │                  │
                ├─────────────────┼─────────────────────┼──────────────────┤
  MEDIUM        │  A4 Script exec │  A2 Workspace       │                  │
  LIKELIHOOD    │  A5 memfd       │     file access     │                  │
                │  A7 Attribution │  A3 Exfil to        │                  │
                │  A8 HTTPS       │     allowlisted     │                  │
                │     opacity     │                     │                  │
                ├─────────────────┼─────────────────────┼──────────────────┤
  LOW           │                 │  A1 No gVisor       │                  │
  LIKELIHOOD    │                 │     (kernel exploit │                  │
                │                 │      required)      │                  │
                └─────────────────┴─────────────────────┴──────────────────┘
```

**Overall posture:** No HIGH-impact risks at HIGH likelihood. The most significant accepted risk (A1, no gVisor) is LOW likelihood because it requires a kernel exploit against allowed syscalls -- a non-trivial attack with strong compensating controls. The MEDIUM-likelihood risks (A2, A3, A6) are inherent to the agent's function and are mitigated to acceptable levels through layered controls.

**Decision required:** Security leadership must formally sign off on each accepted risk above. Use the [Risk Acceptance Matrix](ai-coding-agent-requirements.md#risk-acceptance-matrix) template to document approvals.

---

## 3. Organizational Model

### 2.1 Department and Team Topology

| Department | Teams | Allowlist Profile | Nexus Repo Group | Azure AI Foundry Project | Loki Tenant ID |
|-----------|-------|-------------------|------------------|--------------------------|----------------|
| Dept A | Alpha, Bravo, Charlie, Delta | `allowlist-il4.yaml` | `dept-a-packages` | `foundry-dept-a` | `dept-a` |
| Dept B | Echo, Foxtrot, Golf, Hotel | `allowlist-il4.yaml` | `dept-b-packages` | `foundry-dept-b` | `dept-b` |
| Dept C | India, Juliet, Kilo, Lima | `allowlist-il4.yaml` | `dept-c-packages` | `foundry-dept-c` | `dept-c` |

Each department gets its own Loki tenant, Grafana folder, Nexus repository group, and Azure AI Foundry project. Teams within a department share these resources but have separate Bitbucket service accounts for agent attribution.

### 2.2 RBAC Mapping

| Role | Bitbucket DC | Nexus | Azure AI Foundry | Grafana |
|------|-------------|-------|------------------|---------|
| Security Admin | System Admin | nx-admin | Owner | Admin (all folders) |
| Team Lead | Project Admin | nx-deployer | Contributor | Editor (own dept folder) |
| Developer | Write | nx-readonly | Cognitive Services User | Viewer (own dept folder) |
| Agent Service Account | Write (feature branches only) | nx-readonly | Cognitive Services User | None |

### 2.3 Service Accounts

Create one Bitbucket service account per team for agent commits:

| Account | Team | Git Author | Purpose |
|---------|------|-----------|---------|
| `svc-safe-ai-alpha` | Alpha | `svc-safe-ai-alpha <svc-safe-ai-alpha@corp.mil>` | Agent commits for Team Alpha |
| `svc-safe-ai-bravo` | Bravo | `svc-safe-ai-bravo <svc-safe-ai-bravo@corp.mil>` | Agent commits for Team Bravo |
| ... | ... | ... | One per team (12 total) |

All agent commits include a `Co-Authored-By` trailer identifying the invoking developer and the AI model.

### 2.4 Allowlist Governance

The `allowlist.yaml` file is a security policy artifact. Treat changes like firewall rule changes:

1. Allowlist files live in a dedicated Bitbucket config repository (`safe-ai-config`)
2. Changes require a PR with **minimum 2 security team approvals**
3. Each domain addition must include a justification comment in the PR
4. Quarterly review: security team audits all allowlisted domains and removes unused entries
5. Per-classification profiles: `allowlist-il4.yaml`, `allowlist-internal.yaml`, `allowlist-airgap.yaml`

---

## 4. Requirements R1-R12: Enterprise Mitigations

### R1: Network Egress Control (Mandatory)

**Risk:** An AI agent with outbound internet access can exfiltrate CUI to any reachable destination. In a DFARS environment, even authorized LLM API calls transmit controlled technical data -- every allowlisted domain is a potential exfiltration path. DNS tunneling, HTTP POST to allowlisted endpoints, and covert channels through SNI headers are all viable vectors.

**safe-ai Baseline:**
- Docker `internal: true` network removes default gateway -- sandbox has no internet route
- Squid proxy enforces domain-level ACLs (allowlist only)
- dnsmasq returns empty responses for non-allowlisted domains (blocks DNS tunneling)
- Only ports 80/443 permitted through proxy

**Enterprise Gap:** Default allowlist includes public LLM APIs and package registries. Defense deployment must restrict to internal-only destinations.

**Mitigation Steps:**

1. Configure Azure AI Foundry with VNet private endpoint. The model inference endpoint becomes an internal FQDN (e.g., `foundry-dept-a.privatelink.openai.azure.us`) accessible only within the VNet or peered networks.

2. Deploy Nexus Repository Manager on internal network. Configure as the sole package source. Remove all public registries from the allowlist.

3. Create `allowlist-il4.yaml` containing only internal FQDNs:
   ```yaml
   domains:
     - foundry-dept-a.privatelink.openai.azure.us  # Azure AI Foundry
     - nexus.corp.mil                                # Nexus Repository Manager
     - bitbucket.corp.mil                            # Bitbucket Data Center
     - wiki.corp.mil                                 # Internal documentation
   ```

4. Set `SAFE_AI_DNS_UPSTREAM` to internal Active Directory DNS servers (not `8.8.8.8`).

5. Disable IPv6 on the internal Docker network (`enable_ipv6: false`) to close the IPv6 bypass gap.

**Verification:**
- From sandbox: `curl -v https://api.anthropic.com` -- must return connection refused or 403
- From sandbox: `curl -v https://nexus.corp.mil` -- must succeed
- Grafana: query `{job="safe-ai"} |= "TCP_DENIED"` -- confirms denied requests are logged
- `docker network inspect safe-ai-internal` -- confirm no default gateway

---

### R2: Sandbox Isolation (Mandatory)

**Risk:** The AI agent executes arbitrary code as its core function. A compromised agent -- via prompt injection, malicious repository content, or tool poisoning -- can attempt container escape via kernel exploits in allowed syscalls. Without hardware-enforced isolation, the kernel is the only barrier between the agent and the host.

**safe-ai Baseline:**
- Seccomp whitelist (default-DENY, blocks ptrace/mount/bpf/unshare/io_uring/kernel modules)
- `cap_drop: ALL`, only 5 minimal capabilities re-added
- `no-new-privileges: true` (prevents setuid/setgid escalation)
- Read-only root filesystem with noexec tmpfs on `/tmp` and `/run`
- Non-root user (`dev`, UID 1000)
- Resource limits: 8GB memory, 4 CPUs, 512 PIDs

**Enterprise Gap:** gVisor kernel isolation is the recommended target state for defense. Shared Docker daemons across classifications are not acceptable.

**Platform constraint:** The current development environment is Windows 11 + WSL2 + Docker Desktop. Docker Desktop runs containers inside a lightweight Hyper-V VM that does **not** support registering custom OCI runtimes like gVisor `runsc`. This is a Docker Desktop limitation, not a WSL2 limitation. gVisor requires a native Linux host with direct kernel access.

**Accepted residual risk (Iteration 1):** Without gVisor, kernel exploits in allowed syscalls remain the primary container escape path. The seccomp whitelist, capability drops, read-only root, and no-new-privileges still provide strong defense-in-depth -- but the kernel itself is the isolation boundary, not a userspace sandbox.

**Mitigation Steps (Iteration 1 -- without gVisor):**

1. **Maximize container-level hardening.** The existing safe-ai controls (seccomp whitelist, cap_drop ALL, no-new-privileges, read-only root, noexec tmpfs) are all active and provide the strongest isolation possible under `runc`. Keep Docker Desktop and the WSL2 kernel updated -- kernel patches are the primary mitigation for this residual risk.

2. Deploy **dedicated Docker Desktop instances per classification level**. Never share a Docker daemon across IL boundaries. CUI projects and proprietary IP projects run on physically separate developer workstations or VMs.

3. Remove the `personality` syscall from `config/seccomp.json` (obsolete, no legitimate use).

4. Evaluate blocking `memfd_create` in the seccomp profile. This syscall enables fileless execution (write ELF to anonymous memory, bypassing noexec). Test whether your development tools (Node.js, Python, Java) require it before blocking.

5. **Compensating controls** for the gVisor gap:
   - Enable Hyper-V isolation for Docker containers where supported (`--isolation=hyperv`) -- provides VM-level separation per container
   - Enable Windows Defender Application Guard policies on developer workstations
   - Restrict Docker Desktop settings via `admin-settings.json` (disable Kubernetes, disable file sharing outside project paths, disable Docker Extensions)
   - Monitor for Docker Desktop and WSL2 kernel updates -- apply within 7 days of release

**Mitigation Steps (Iteration 2 -- gVisor target state):**

6. When migrating to native Linux Docker hosts (bare metal or dedicated VMs), install gVisor: `scripts/install-gvisor.sh --default`, set `SAFE_AI_RUNTIME=runsc` in `.env`.

7. For Kubernetes deployments at scale: use gVisor `RuntimeClass` with per-team namespaces and `NetworkPolicy` isolation.

**Verification (Iteration 1):**
- `docker inspect safe-ai-sandbox | grep -i runtime` shows `runc` (expected on Docker Desktop)
- From sandbox: attempt `strace ls` (uses ptrace) -- must fail with EPERM
- From sandbox: `cat /proc/self/status | grep Seccomp` -- shows seccomp active
- Docker Desktop is on the latest stable release
- WSL2 kernel version: `wsl --version` shows latest available

**Verification (Iteration 2 -- when on native Linux):**
- `docker inspect safe-ai-sandbox | grep -i runtime` shows `runsc`
- `dmesg | grep gvisor` on host confirms gVisor interception

---

### R3: Credential Separation (Mandatory)

**Risk:** Secret leakage runs 40% higher in repositories using AI coding tools. If the agent can access API tokens, SSH private keys, or cloud credentials, a prompt injection attack becomes a full credential theft. DFARS 7012 requires protection of CUI access credentials.

**safe-ai Baseline:**
- Gateway token injection at proxy layer -- API tokens never enter sandbox
- Anti-spoofing: proxy strips sandbox-originated `X-Safe-AI-Token` headers, re-injects real token
- SSH public key auth only (no passwords), max 3 attempts

**Enterprise Gap:** Eliminate API keys entirely via Managed Identity. Establish credential rotation for Bitbucket and Nexus tokens.

**Mitigation Steps:**

1. **Azure AI Foundry:** Use Azure Managed Identity for authentication. The proxy authenticates to Azure AD using the VM's system-assigned managed identity -- no API key exists to leak. Grant the `Cognitive Services User` role to the managed identity.

2. **Bitbucket:** Use repository-scoped deploy keys (read-only). Rotate quarterly via configuration management (Ansible/Puppet). Never use personal access tokens for agent access.

3. **Nexus:** Create a service account with `nx-readonly` role. Inject the token at the proxy layer using `SAFE_AI_GATEWAY_TOKEN` or bake into the proxy image using `examples/gateway-proxy.Dockerfile`.

4. **Build-time secrets:** Use BuildKit `--secret` flag for any credentials needed during image build. Never use `ARG` or `ENV` for secrets (they persist in image layer history).

5. **Secret rotation:** Integrate with HashiCorp Vault or Azure Key Vault for automated credential rotation. Target: 90-day rotation cycle for all service account credentials.

**Verification:**
- `docker exec safe-ai-sandbox env | grep -iE "key|token|secret|password"` returns nothing
- `docker inspect safe-ai-sandbox --format='{{json .Config.Env}}'` contains no credentials
- `docker history safe-ai-sandbox:latest` shows no secret values in layer history

---

### R4: Human Approval Gates (Mandatory)

**Risk:** An autonomous agent that can push code, delete files, and modify CI pipelines without human review creates unacceptable blast radius in a defense environment. 80% of organizations report risky agent behaviors including unauthorized system access. Approval fatigue is the organizational counter-risk: developers reviewing 50+ changes/day stop meaningfully reviewing.

**safe-ai Baseline:**
- Git pre-push hook (`config/git/pre-push`) prompts for confirmation before push

**Enterprise Gap:** Infrastructure-level push hooks are insufficient. Bitbucket must enforce branch permissions, merge checks, and tiered autonomy.

**Mitigation Steps:**

1. **Bitbucket branch permissions:** Restrict `main` and `develop` branches. Require minimum 2 approvals for merge. Require all conversations resolved. Agent service accounts (`svc-safe-ai-*`) cannot push directly to protected branches -- must create feature branches and submit PRs.

2. **Bitbucket merge checks (8.10+):** Enable project-level merge checks that cannot be overridden at repository level:
   - Minimum 2 approvals (at least 1 from CODEOWNERS)
   - Successful CI build (includes SAST scan)
   - No unresolved merge check failures

3. **Pre-receive hook:** Deploy a Bitbucket pre-receive hook that rejects direct pushes from agent service accounts to protected branches:
   ```bash
   # Reject agent service account pushes to main/develop
   if [[ "$GL_USERNAME" == svc-safe-ai-* ]] && [[ "$refname" =~ refs/heads/(main|develop) ]]; then
     echo "Agent service accounts must use pull requests for protected branches"
     exit 1
   fi
   ```

4. **Tiered autonomy (Level 2 -- Propose + Apply with Review):**

   | Action | Autonomy | Gate |
   |--------|----------|------|
   | Read files, explore code | Fully autonomous | None |
   | Edit local files, run tests | Fully autonomous | None |
   | Create feature branch, commit | Autonomous | Pre-push hook confirmation |
   | Push to feature branch, create PR | Autonomous | Bitbucket notifies reviewers |
   | Merge to main/develop | Gated | 2 human approvals required |
   | Modify Dockerfile, CI config, IAM | Gated | Security team reviewer required |
   | Delete branch, force-push | Blocked | Agent cannot perform |

5. **Approval fatigue mitigation:** Use Bitbucket CODEOWNERS-equivalent (path-based reviewers) so changes to `src/` route to the owning team, while changes to `Dockerfile`, `.github/workflows/`, or `seccomp.json` automatically add a security team reviewer. Rotate reviewers weekly.

**Verification:**
- Agent service account push to `main` is rejected with pre-receive hook error
- PR without 2 approvals cannot be merged (Bitbucket merge check blocks)
- Bitbucket audit log shows all merge events with approver identities

---

### R5: Audit Logging (Mandatory)

**Risk:** DFARS 7012 requires audit capabilities per NIST 800-171 family 3.3. Without centralized logging, there is no forensics after an incident, no compliance evidence for CMMC assessors, and no anomaly detection. Only 21% of executives have complete visibility into agent permissions and data access patterns.

**safe-ai Baseline:**
- Squid structured JSON logging (timestamp, domain, method, bytes, status, SNI)
- Both allowed and denied requests logged
- Fluent Bit ships logs to Loki
- Grafana dashboard with pre-built visualizations

**Enterprise Gap:** Single-tenant Loki, no SIEM integration, no cross-platform log correlation, insufficient retention for DFARS.

**Mitigation Steps:**

1. **Loki multi-tenancy:** Enable `auth_enabled: true` in `config/logging/loki/loki-config.yaml`. Configure Fluent Bit to send `X-Scope-OrgID` per department:
   ```ini
   [OUTPUT]
       Name   loki
       Match  *
       Header X-Scope-OrgID ${SAFE_AI_DEPT_ID}
   ```

2. **Retention:** 90-day hot retention in Loki (already configured). Add Azure Blob Storage archival with immutability policy for 7-year cold retention (DFARS 7012 evidence preservation).

3. **SIEM integration:** Configure Fluent Bit dual output -- Loki for Grafana dashboards and enterprise SIEM (Splunk/Sentinel) for SOC correlation:
   ```ini
   [OUTPUT]
       Name   splunk
       Match  *
       Host   siem.corp.mil
       Port   8088
       TLS    On
   ```

4. **Azure Monitor:** Enable diagnostic logging on Azure AI Foundry deployments (Audit + RequestResponse categories). Route to Log Analytics workspace for query and to Storage Account for archival.

5. **Bitbucket audit logs:** Enable Atlassian Access audit logging. Ship to SIEM alongside safe-ai proxy logs.

6. **Grafana RBAC:** Create per-department folders. Team leads get Editor on their department folder. Security team gets Admin across all folders. LDAP/AD integration for SSO.

7. **Grafana alerting:** Configure alerts beyond the existing denied-spike alert:

   | Alert | Threshold | Action |
   |-------|-----------|--------|
   | Denied request spike | >10 in 5 minutes | Page security team |
   | Unusual upload volume | >10MB in 1 hour | Alert SOC |
   | Off-hours activity | Any request 22:00-06:00 | Alert team lead |
   | New user-agent string | First occurrence | Log for review |
   | Agent activity on weekend | Any request Sat-Sun | Alert team lead |

**Verification:**
- Loki query `{job="safe-ai", org_id="dept-a"}` returns only Dept A logs
- Cross-department query without admin credentials fails with 403
- Trigger a denied request -- Grafana alert fires within 2 minutes
- SIEM shows correlated events from safe-ai proxy + Bitbucket + Azure Monitor

---

### R6: Filesystem Scoping (Mandatory)

**Risk:** If the agent can access files outside its designated workspace, a prompt injection attack becomes a credential harvesting attack. Indirect prompt injection via workspace files (`.claude/settings.json`, `CLAUDE.md`) is a documented CVE attack vector. Cross-project access in multi-classification environments creates CUI spillage risk.

**safe-ai Baseline:**
- Workspace mounted as named Docker volume at `/workspace`
- No host directory access (sandbox cannot see host home, `.ssh/`, `.aws/`, `.kube/`)
- Read-only root filesystem prevents system modification

**Enterprise Gap:** No per-project isolation (risk of cross-classification contamination), no volume size limits, no automated snapshots.

**Mitigation Steps:**

1. **Per-project bind mounts:** Use `docker-compose.override.yaml` to mount specific project directories. Never mount parent directories or mix classifications:
   ```yaml
   services:
     sandbox:
       volumes:
         - /data/projects/project-alpha:/workspace:rw
   ```

2. **XFS quotas:** Format Docker data root as XFS. Set project quotas on workspace volumes (10GB recommended per workspace):
   ```bash
   xfs_quota -x -c 'limit -p bhard=10g project-alpha' /data/projects
   ```

3. **Automated snapshots:** Cron job running `make snapshot` daily. Store snapshots to encrypted Azure Blob with legal hold enabled for evidence preservation:
   ```bash
   0 2 * * * cd /opt/safe-ai && make snapshot && \
     az storage blob upload --account-name evidence --container snapshots \
     --file workspace-snapshot-$(date +%Y%m%d).tar.gz --auth-mode login
   ```

4. **Classification separation:** Projects at different classification levels run on separate Docker hosts with separate volume drivers. Never bind-mount a directory tree containing projects at mixed classifications.

**Verification:**
- From sandbox: `ls /` shows only expected mounts (`/workspace`, `/tmp`, `/run`)
- `df -h /workspace` shows quota applied
- Snapshot cron job produces daily tarballs in Azure Blob

---

### R7: Resource Limits (Mandatory)

**Risk:** A runaway agent or malicious prompt can exhaust host resources (memory, CPU, disk, PIDs) causing denial of service. Agents can also drive up costs through excessive API calls to Azure AI Foundry. NIST 800-171 3.14.1 requires identification and management of information system flaws.

**safe-ai Baseline:**
- Memory: 8GB (configurable via `SAFE_AI_SANDBOX_MEMORY`)
- CPU: 4 cores (configurable via `SAFE_AI_SANDBOX_CPUS`)
- PIDs: 512 (prevents fork bombs)

**Enterprise Gap:** No workspace disk quota (Docker/ext4 limitation), no API call rate limiting, no cost controls.

**Mitigation Steps:**

1. **Volume quotas:** Use XFS project quotas (see R6) to limit workspace to 10GB per sandbox instance.

2. **Azure AI Foundry rate limits:** Configure per-deployment token-per-minute (TPM) and request-per-minute (RPM) limits. Set budget alerts in Azure Cost Management:
   - Per-team daily budget: define based on expected usage
   - Alert at 80% and 100% of budget
   - Auto-disable deployment at 120% (requires Azure Policy)

3. **Per-team resource profiles:** Define in `docker-compose.override.yaml` if teams have different needs:
   ```yaml
   # Teams working on large monorepos may need more memory
   services:
     sandbox:
       deploy:
         resources:
           limits:
             memory: 16g
             cpus: '8'
   ```

4. **Proxy-level rate limiting:** Configure Squid `delay_pools` to throttle bandwidth per sandbox, or use Azure API Management as a rate-limiting gateway in front of Azure AI Foundry.

**Verification:**
- `docker stats safe-ai-sandbox` shows limits applied
- Fork bomb test: `:(){ :|:& };:` is killed at 512 PIDs
- Azure AI Foundry returns 429 when rate limit exceeded
- Azure Cost Management alert fires at 80% of daily budget

---

### R8: Supply Chain Controls (Mandatory for Defense)

**Risk:** AI agents install packages, use MCP tools, and pull dependencies. Attack surfaces include malicious packages from public registries (typosquatting, slopsquatting), compromised MCP servers, and poisoned tool dependencies. 45% of AI-generated code contains security flaws. ~1,184 malicious skills found in the ClawHub MCP registry (1 in 5 packages).

**safe-ai Baseline:**
- Domain allowlist restricts reachable registries
- Read-only root prevents system modification
- noexec `/tmp` blocks direct binary execution

**Enterprise Gap:** No vulnerability scanning at package level, no staged promotion, no lock file enforcement.

**Mitigation Steps:**

1. **Nexus IQ Server Repository Firewall:** Enable on all proxy repositories. Set policy action to `FAIL` at `PROXY` stage. Components with critical/high vulnerabilities are automatically quarantined and blocked from download.

2. **Staged promotion workflow:**

   | Stage | Repository | Access | Governance |
   |-------|-----------|--------|------------|
   | Incoming | `proxy-npm`, `proxy-pypi` | Nexus Firewall scans | Auto-quarantine on policy violation |
   | Development | `dev-npm`, `dev-pypi` | Agent sandbox | Firewall-cleared packages only |
   | Production | `prod-npm`, `prod-pypi` | CI/CD only | Manual promotion after review |

3. **Lock file enforcement:** Bitbucket pre-receive hook rejects commits that modify `package.json` without corresponding `package-lock.json` changes:
   ```bash
   changed_files=$(git diff --name-only $oldrev $newrev)
   if echo "$changed_files" | grep -q "package.json"; then
     if ! echo "$changed_files" | grep -q "package-lock.json"; then
       echo "Error: package.json changed without updating lock file"
       exit 1
     fi
   fi
   ```

4. **MCP servers:** Self-hosted only. No connections to public MCP registries. Each MCP server addition requires security team review and a corresponding allowlist PR.

5. **Slopsquatting defense:** Configure Nexus namespace restrictions. Only allow packages from known npm scopes (`@company/`) and verified PyPI maintainers. Agent-suggested dependencies must be reviewed before first install.

**Verification:**
- `npm install known-vulnerable-package` fails (quarantined in Nexus IQ)
- `npm audit` against Nexus mirror returns clean
- Nexus IQ dashboard shows scan results and quarantine events
- Commit with `package.json` change but no lock file update is rejected

---

### R9: Code Review Enforcement (Mandatory for Defense)

**Risk:** 45% of AI-generated code contains security flaws. Developers develop approval fatigue reviewing high volumes of agent output. Agents can modify security-critical files (CI pipelines, Dockerfiles, IAM configs) alongside application code. NIST 800-171 3.4.5 requires defining and documenting configuration settings.

**safe-ai Baseline:**
- Git config `user.name "dev (via safe-ai)"` tags agent commits
- Pre-push hook prompts for confirmation

**Enterprise Gap:** No automated security scanning, no mandatory reviewers, no security-critical file detection.

**Mitigation Steps:**

1. **Bitbucket default reviewers:** Configure minimum 2 reviewers on all repositories. For defense repositories, require at least 1 reviewer from the security team LDAP group.

2. **SAST integration:** Integrate SonarQube or Checkmarx in CI pipeline (Jenkins/Bitbucket Pipelines). Configure as a Bitbucket merge check -- PRs with critical or high SAST findings cannot be merged.

3. **Security-critical file detection:** Deploy a Bitbucket webhook that triggers when PRs modify sensitive paths. Automatically add a security team reviewer:

   | Path Pattern | Additional Reviewer |
   |-------------|-------------------|
   | `Dockerfile*`, `docker-compose*` | Security team |
   | `.github/workflows/`, `Jenkinsfile` | Security team + DevOps lead |
   | `**/seccomp*.json`, `**/apparmor*` | Security team |
   | `**/iam*`, `**/policy*`, `**/*role*` | Security team + ISSO |
   | `allowlist*.yaml` | Security team (2 approvals) |

4. **GPG commit signing:** Require signed commits from all agent service accounts. Enable Bitbucket's "Verify Commit Signature" hook on all repositories. Human developer commits should also be signed -- enforce via pre-receive hook.

5. **Code ownership:** Define per-directory ownership in Bitbucket. Changes to owned directories route review requests to the owning team, not to all 120 developers.

**Verification:**
- PR with critical SAST finding cannot be merged (merge check blocks)
- Modification to `Dockerfile` triggers security team notification
- Unsigned commit from agent service account is rejected
- Bitbucket audit log shows reviewer assignments and approval timestamps

---

### R10: Data Classification Policy (Mandatory for Defense)

**Risk:** DFARS 7012 requires safeguarding Covered Defense Information (CDI). AI agents processing CUI-containing code transmit that data to LLM endpoints. ITAR/EAR definitions of "technical data" and "technology" encompass AI-generated outputs derived from controlled information. Misclassification leads to CUI spillage across classification boundaries.

**safe-ai Baseline:**
- Allowlist enforcement prevents data flow to unapproved destinations
- Network isolation constrains exfiltration paths

**Enterprise Gap:** No formal classification tagging, no per-project allowlist profiles, no DLP integration, no developer training on CUI in code context.

**Mitigation Steps:**

1. **Project classification tagging:** Label every Bitbucket project with its classification level. Use Bitbucket project labels or a metadata repository:

   | Classification | Allowlist Profile | Azure AI Foundry Deployment | LLM Data Residency |
   |---------------|-------------------|----------------------------|---------------------|
   | CUI | `allowlist-il4.yaml` | Azure Government (IL4) | US sovereign |
   | Proprietary IP | `allowlist-enterprise.yaml` | Azure Government (IL4) | US sovereign |
   | ITAR (if applicable) | `allowlist-airgap.yaml` | Air-gapped self-hosted | On-premises only |
   | Public / Open Source | `allowlist-standard.yaml` | Azure Commercial | Global |

2. **Azure Content Safety:** Enable Prompt Shields on all Azure AI Foundry deployments. Configure groundedness detection. Enable content filtering for PII/CUI patterns in prompts and responses.

3. **Microsoft Purview DLP:** Integrate with Azure AI Foundry. Configure DLP policies that detect CUI markers (FOUO, CUI/NOFORN, distribution statement patterns) in prompts and block or alert.

4. **Developer training:** Mandatory briefing for all 120 developers on:
   - What constitutes CUI in source code context (comments, variable names, algorithm descriptions, system parameters, test fixtures)
   - Why AI-generated outputs derived from CUI are themselves controlled
   - Technology Control Plan (TCP) implications: agents on workstations accessible to foreign nationals
   - How to verify their project's classification before starting an agent session

5. **Per-classification safe-ai instances:** Each classification level gets its own `docker-compose.override.yaml` with the appropriate allowlist profile. Never deploy a single safe-ai instance serving projects at mixed classifications.

**Verification:**
- Developer on CUI project cannot reach external LLM endpoints
- Purview DLP alert fires when CUI pattern appears in prompt (test with synthetic CUI markers)
- Classification label present on all Bitbucket projects
- Training completion records in LMS for all 120 developers

---

### R11: Agent Identity and Attribution (Mandatory for Defense)

**Risk:** When an AI agent commits code, pushes to Bitbucket, and creates PRs, the audit trail must identify both the agent and the human who authorized it. NIST 800-171 3.3.1 requires creating audit records containing sufficient information to establish what events occurred, who caused them, and when. DFARS requires attribution for all CDI access. Indistinguishable agent commits create forensics gaps.

**safe-ai Baseline:**
- `SAFE_AI_HOSTNAME` label added to all log entries
- Git config `user.name "dev (via safe-ai)"` in sandbox Dockerfile

**Enterprise Gap:** No per-developer attribution, no per-team service accounts, no log tenant isolation, no delegation chain tracking.

**Mitigation Steps:**

1. **Per-team Bitbucket service accounts:** Create 12 service accounts (`svc-safe-ai-alpha` through `svc-safe-ai-lima`). Each team's sandbox uses its team's service account for git operations.

2. **Co-Authored-By trailers:** Configure a git `commit-msg` hook in the sandbox that appends attribution trailers to every commit:
   ```
   feat(auth): add token refresh logic

   Co-Authored-By: jsmith <jsmith@corp.mil>
   Co-Authored-By: Claude <noreply@anthropic.com>
   Agent-Session: a1b2c3d4
   ```
   The invoking developer's identity comes from `SAFE_AI_DEVELOPER_ID` environment variable set at sandbox launch.

3. **SAFE_AI_HOSTNAME per developer:** Set hostname to `[developer-id]-[team]-[classification]` for unique log attribution:
   ```bash
   SAFE_AI_HOSTNAME=jsmith-alpha-cui
   ```

4. **Loki multi-tenancy:** With `auth_enabled: true` (see R5), each department's logs are isolated. Security team queries across all tenants. Team leads query only their department.

5. **Grafana RBAC dashboards:**
   - Per-department folder with pre-built dashboards filtered by `{org_id="dept-a"}`
   - Developer self-service: dashboard filtered by `{hostname=~"jsmith-.*"}`
   - Security team: cross-department admin dashboard

6. **NIST AI Agent Standards alignment:** Document the delegation chain for CMMC assessors:
   ```
   Developer (cleared, authenticated via AD)
     → safe-ai sandbox (identified by SAFE_AI_HOSTNAME)
       → AI agent (identified by Co-Authored-By trailer)
         → Azure AI Foundry (authenticated via Managed Identity)
   ```
   Each hop is logged: SSH session in proxy log, git commits in Bitbucket, API calls in Azure Monitor.

**Verification:**
- `git log --format="%an <%ae>%n%(trailers)"` shows distinct agent author and Co-Authored-By trailers
- Loki query scoped to `dept-a` cannot return `dept-b` logs
- Non-cleared user cannot start a sandbox bound to a CUI project (AD group membership check)
- CMMC assessor can trace any commit back through the full delegation chain

---

### R12: Incident Response (Mandatory for Defense)

**Risk:** A compromised agent can poison downstream decision-making within hours. DFARS 252.204-7012 requires cyber incident reporting to DIBNet within 72 hours. Without rapid containment, evidence preservation, and practiced procedures, an incident becomes a regulatory violation.

**safe-ai Baseline:**
- `make kill` -- emergency stop all containers
- `make snapshot` -- create workspace volume tarball for forensics
- `docs/incident-response.md` -- 4-phase runbook (Contain, Preserve, Analyze, Recover)

**Enterprise Gap:** No DFARS 72-hour reporting procedure, no evidence chain of custody, no cross-host kill switch, no red-teaming program.

**Mitigation Steps:**

1. **DFARS 72-hour reporting:** Extend the incident response runbook with DFARS-specific steps:
   - Hour 0-1: Contain (`make kill` on affected hosts, revoke service account credentials in Bitbucket)
   - Hour 1-4: Preserve evidence (workspace snapshots, proxy logs, Loki export, Bitbucket audit log export)
   - Hour 4-24: Analyze (review timeline in Grafana, identify scope of compromise, determine if CDI was affected)
   - Hour 24-72: Report to DIBNet if CDI was potentially compromised, notify contracting officer

2. **Evidence chain of custody:** Snapshots and log exports are:
   - Encrypted with AES-256 at rest
   - SHA-256 hash computed and recorded in a separate tamper-evident log
   - Uploaded to Azure Blob with immutability policy and legal hold
   - Access restricted to ISSO and legal counsel

3. **Cross-host kill switch:** Ansible playbook that kills all safe-ai instances across all Docker hosts simultaneously:
   ```bash
   ansible-playbook -i inventory/safe-ai kill-all.yaml
   # Stops all safe-ai containers, revokes service account PATs,
   # blocks agent IP ranges at network firewall
   ```

4. **Red-teaming program:** Quarterly exercises testing:
   - Prompt injection attempts to exfiltrate workspace files to allowlisted domains
   - DNS tunneling attempts against dnsmasq
   - noexec bypass via interpreted scripts
   - Exfiltration via large POST bodies to Azure AI Foundry endpoint
   - Container escape attempts against seccomp/gVisor boundary

5. **Tabletop exercises:** Biannual exercises with department leads simulating:
   - Agent compromised via malicious repository content
   - CUI exfiltrated to allowlisted LLM endpoint
   - Agent modifies CI pipeline to disable security scanning

6. **SOC integration:** safe-ai Grafana alerts feed into SOC SIEM. SOC runbook includes safe-ai-specific containment procedures. SOC analysts trained on safe-ai architecture and log interpretation.

**Verification:**
- `make kill` stops all containers within 5 seconds (test on non-production host)
- Ansible kill-all playbook completes across all hosts within 30 seconds
- Evidence snapshot is encrypted and hash-verifiable
- SOC acknowledges test alert within SLA
- Red-team exercise report documents findings and remediations

---

## 5. Phased Rollout

### Phase 0: Infrastructure (Weeks 1-2, 0 developers)

| Task | Owner | Deliverable |
|------|-------|-------------|
| Deploy dedicated Docker Desktop instances per classification | Infrastructure | Separate workstations/VMs per IL level, Hyper-V isolation enabled |
| Deploy Nexus with IQ Server and Repository Firewall | Infrastructure | Nexus running, Firewall policies configured |
| Configure Azure AI Foundry with VNet private endpoints | Cloud team | Private FQDN accessible, Managed Identity assigned |
| Deploy centralized Loki with multi-tenancy | Security | `auth_enabled: true`, 3 tenant IDs configured |
| Create per-classification allowlist profiles | Security | `allowlist-il4.yaml` reviewed and approved |
| Create Bitbucket service accounts (12) | Identity team | Service accounts in AD, Bitbucket permissions set |
| Configure Bitbucket branch permissions and merge checks | DevOps | Protected branches enforced project-wide |
| SIEM integration | SOC | Fluent Bit dual output to Loki + SIEM |

### Phase 1: Pilot (Weeks 3-4, 1 team = 10 developers)

| Task | Owner | Success Criteria |
|------|-------|-----------------|
| Select lowest-risk team for pilot | Security + Dept Lead | Team identified, project classified |
| Deploy safe-ai with full R1-R12 controls (runc + compensating controls) | DevOps | All 12 requirements verified |
| Developer onboarding briefing | Security | 10 developers trained |
| Daily feedback sessions (week 1) | Team Lead | Friction points documented |
| Tune allowlist (add missing legitimate domains) | Security | No false-positive blocks for 3 consecutive days |
| Tune Grafana alert thresholds | SOC | Alert fatigue <2 false positives/day |
| Exit criteria | Security | 5 consecutive business days, no blocking issues |

### Phase 2: Department Rollout (Weeks 5-8, 1 department = 40 developers)

| Task | Owner | Success Criteria |
|------|-------|-----------------|
| Expand to all 4 teams in pilot department | DevOps | 4 service accounts active, 4 Grafana dashboards |
| Team lead training (Grafana, approval workflows) | Security | 4 team leads certified |
| First red-team exercise | Security | Report delivered, findings remediated |
| SAST integration verified in CI | DevOps | PRs with critical findings blocked |
| Allowlist governance fully operational | Security | First PR-based allowlist change processed |

### Phase 3: Full Deployment (Weeks 9-14, all 120 developers)

| Task | Owner | Success Criteria |
|------|-------|-----------------|
| Roll out Dept B (weeks 9-10) | DevOps | 40 developers onboarded |
| Roll out Dept C (weeks 11-12) | DevOps | 40 developers onboarded |
| Cross-department Grafana admin dashboard | Security | Security team has unified view |
| Tabletop exercise with all department leads | Security | Exercise completed, lessons captured |
| CMMC audit readiness check | Compliance | Evidence package assembled |

### Phase 4: Steady State (Week 15+)

| Cadence | Activity | Owner |
|---------|----------|-------|
| Monthly | Allowlist review | Security |
| Quarterly | Red-team exercise | Security |
| Quarterly | Credential rotation | Identity team |
| Quarterly | Document review (this guide) | Security Architecture |
| Biannual | Tabletop exercise | Security + Dept Leads |
| Annual | CMMC / DFARS compliance review | Compliance |
| Continuous | Grafana monitoring | SOC |
| Track | Evaluate migration to native Linux Docker hosts with gVisor | Infrastructure + Security |

---

## 6. Compliance Crosswalk

### NIST SP 800-171 Mapping

| Requirement | NIST 800-171 Control Family | Key Controls |
|------------|----------------------------|-------------|
| R1 Network Egress | 3.13 System & Comms Protection | 3.13.1 (boundary protection), 3.13.6 (deny by default) |
| R2 Sandbox Isolation | 3.13 System & Comms Protection | 3.13.4 (architectural separation), 3.4.6 (least functionality) |
| R3 Credentials | 3.5 Identification & Auth | 3.5.1 (identify users/processes), 3.5.2 (authenticate) |
| R4 Approval Gates | 3.1 Access Control | 3.1.1 (authorized access), 3.1.2 (transaction types) |
| R5 Audit Logging | 3.3 Audit & Accountability | 3.3.1 (create audit records), 3.3.2 (unique traceability) |
| R6 Filesystem | 3.1 Access Control | 3.1.3 (CUI flow control), 3.8.1 (media protection) |
| R7 Resource Limits | 3.14 System & Info Integrity | 3.14.1 (flaw identification), 3.14.6 (monitor inbound) |
| R8 Supply Chain | 3.4 Configuration Management | 3.4.8 (application usage restriction) |
| R9 Code Review | 3.4 Configuration Management | 3.4.3 (change tracking), 3.4.5 (access restrictions) |
| R10 Data Classification | 3.8 Media Protection | 3.8.1 (protect CUI on media), 3.1.3 (CUI flow control) |
| R11 Agent Identity | 3.3 Audit & Accountability | 3.3.1 (who, what, when), 3.3.2 (unique traceability) |
| R12 Incident Response | 3.6 Incident Response | 3.6.1 (IR capability), 3.6.2 (track/document/report) |

### CMMC 2.0 Level 2

All 12 requirements map to CMMC Level 2 practices (which include all NIST 800-171 controls above). Key CMMC-specific additions:

- **CA.L2-3.12.1 (Security assessments):** Quarterly red-team exercises (R12) provide assessment evidence
- **IR.L2-3.6.2 (Incident reporting):** DFARS 72-hour DIBNet reporting (R12)
- **SC.L2-3.13.6 (Network deny by default):** safe-ai `internal: true` + allowlist = deny-by-default (R1)
- **AU.L2-3.3.1 (System-level auditing):** Loki + Grafana + Azure Monitor = comprehensive audit trail (R5)

### OWASP Top 10 for Agentic Applications 2026

| OWASP Agentic | Primary Requirement(s) | Enterprise Mitigation |
|--------------|----------------------|----------------------|
| ASI01 Goal Hijacking | R6, R10 | Filesystem scoping, data classification |
| ASI02 Tool Misuse | R1, R4 | Network egress, approval gates |
| ASI03 Identity & Privilege | R3, R5, R11 | Managed Identity, audit logging, attribution |
| ASI04 Supply Chain | R8 | Nexus IQ Firewall, staged promotion |
| ASI05 Code Execution | R2 | Seccomp whitelist, compensating controls (gVisor in Iteration 2) |
| ASI06 Context Poisoning | R6 | Per-project workspace isolation |
| ASI08 Multi-Agent | R12 | IR procedures, kill switch |
| ASI09 Trust Exploitation | R4, R9 | Approval gates, code review |
| ASI10 Rogue Agents | R2, R1 | Sandbox isolation, network isolation |

### NIST AI Agent Standards Initiative (Track)

NIST CAISI launched the AI Agent Standards Initiative in February 2026. Key proposals to track and align with as they mature:

- **4-level agent trust model** (Unverified → Self-Signed → Org-Signed → Third-Party Certified): current deployment maps to Level 2 (organization-signed via Managed Identity + AD service accounts)
- **Delegation chain documentation**: already captured in R11 mitigation steps
- **Agent identity certificates**: future alignment when standards finalize (public comment period through April 2026)

---

## Glossary

| Term | Definition |
|------|-----------|
| CDI | Covered Defense Information -- unclassified information requiring safeguarding per DFARS 7012 |
| CMMC | Cybersecurity Maturity Model Certification -- DoD contractor security assessment framework |
| CUI | Controlled Unclassified Information -- information requiring safeguarding per 32 CFR 2002 |
| DFARS | Defense Federal Acquisition Regulation Supplement -- DoD procurement regulations |
| DIBNet | Defense Industrial Base Network -- DoD cyber incident reporting portal |
| IL4 | Impact Level 4 -- DoD classification for CUI in cloud, standard for DIB contractors |
| ISSO | Information System Security Officer |
| MCP | Model Context Protocol -- standard for AI agent tool access |
| Slopsquatting | Typosquatting via AI hallucinations -- attackers register package names that AI agents fabricate |
| TCP | Technology Control Plan -- document governing foreign national access to controlled technology |
| Tiered Autonomy | Framework where agent actions are classified by risk level with corresponding human oversight |

---

*Generated for defense sector deployment of safe-ai. Review with ISSO and CMMC assessor before deployment.*
*Source: [AI Coding Agent Security Requirements](ai-coding-agent-requirements.md) | [Enterprise Risk Mapping](enterprise-risk-mapping.md)*

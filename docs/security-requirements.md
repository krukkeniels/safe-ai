# AI Coding Agent Security Requirements

**A practical requirements framework for enterprises deploying AI coding agents**

> This document defines security requirements for enterprises using AI coding agents (Claude Code, OpenAI Codex, GitHub Copilot, Devin, etc.) as developer tools. It synthesizes industry frameworks (OWASP, NIST, MITRE, ISO, EU AI Act) into a focused, actionable set of requirements — not exhaustive compliance checklists, but the controls that actually matter.

---

## Table of Contents

1. [Why This Framework Exists](#why-this-framework-exists)
2. [Industry Frameworks Referenced](#industry-frameworks-referenced)
3. [The 12 Requirements](#the-12-requirements)
4. [Requirements Detail](#requirements-detail)
5. [Enterprise Scenarios](#enterprise-scenarios)
6. [Risk Acceptance Matrix](#risk-acceptance-matrix)
7. [Mapping to Industry Frameworks](#mapping-to-industry-frameworks)
8. [Sources](#sources)

---

## Why This Framework Exists

Existing AI security frameworks target organizations **building** LLM-powered products. Enterprises **using** AI coding agents face a different threat model: the agent is a privileged actor in the software development lifecycle with access to source code, credentials, and infrastructure.

No single framework covers this well:

- **OWASP Top 10 for LLM Applications (2025)** covers model-level risks but not agent autonomy
- **OWASP Top 10 for Agentic Applications (2026)** is the closest fit but is platform-generic, not SDLC-specific
- **NIST AI RMF** provides governance structure but no implementation guidance for sandboxing
- **MITRE ATLAS** maps attack techniques but is oriented toward red teams, not enterprise policy
- **ISO 42001** is a management system standard — certifiable but abstract
- **EU AI Act** is regulatory but most coding agents fall under minimal/limited risk tiers

This framework distills all of the above into **12 requirements** specific to AI coding agents in enterprise development environments. Each requirement maps back to the source frameworks and includes concrete controls.

### Key insight

The agent sits at the intersection of AI security and software supply chain security. It is simultaneously an AI application AND a privileged actor in the SDLC. The requirements must address both dimensions.

---

## Industry Frameworks Referenced

| Framework | Version | Issuing Body | Type | Relevance |
|-----------|---------|-------------|------|-----------|
| OWASP Top 10 for Agentic Applications | 2026 | OWASP | Voluntary | **High** — most directly applicable |
| OWASP Top 10 for LLM Applications | 2025 | OWASP | Voluntary | Medium — covers underlying model risks |
| NIST AI RMF | 1.0 (AI 100-1) | NIST | Voluntary | Medium — governance structure |
| NIST AI 600-1 GenAI Profile | 2024 | NIST | Voluntary | Medium — GenAI-specific risk taxonomy |
| MITRE ATLAS | Oct 2025 | MITRE | Voluntary | Medium — attack technique taxonomy |
| ISO/IEC 42001 | 2023 | ISO/IEC | Voluntary (certifiable) | Low-Medium — management system |
| EU AI Act | 2024/1689 | EU | **Mandatory** (EU) | Low — most agents are minimal/limited risk |
| CSA AI Controls Matrix | 2025 | CSA | Voluntary (certifiable) | Medium — 243 granular controls |
| CISA AI Security Guidance | 2025 | CISA/DHS | Voluntary | Low-Medium — supplementary |
| NIST AI Agent Standards Initiative | Feb 2026 | NIST CAISI | In development | **Track** — will define agent identity/auth |

### Framework selection guidance

- **All enterprises**: Reference OWASP Agentic Top 10 + NIST AI RMF
- **EU operations**: Add EU AI Act compliance (August 2026 deadline for high-risk)
- **Enterprise sales/procurement**: Pursue ISO 42001 certification
- **U.S. federal**: Add CISA guidance + track NIST Agent Standards
- **Cloud-heavy deployments**: Add CSA AI Controls Matrix

---

## The 12 Requirements

These requirements are ordered by impact. The first 7 are **mandatory** for any enterprise deployment. Requirements 8-12 are **recommended** and become mandatory at higher risk levels.

| # | Requirement | Risk Addressed | Priority |
|---|------------|---------------|----------|
| R1 | [Network Egress Control](#r1-network-egress-control) | Code exfiltration, unauthorized data flow | **Mandatory** |
| R2 | [Sandbox Isolation](#r2-sandbox-isolation) | Container escape, host compromise | **Mandatory** |
| R3 | [Credential Separation](#r3-credential-separation) | Secret leakage, credential theft | **Mandatory** |
| R4 | [Human Approval Gates](#r4-human-approval-gates) | Excessive agency, destructive actions | **Mandatory** |
| R5 | [Audit Logging](#r5-audit-logging) | Forensics gaps, compliance evidence | **Mandatory** |
| R6 | [Filesystem Scoping](#r6-filesystem-scoping) | Lateral movement, data access | **Mandatory** |
| R7 | [Resource Limits](#r7-resource-limits) | Denial of service, cost abuse | **Mandatory** |
| R8 | [Supply Chain Controls](#r8-supply-chain-controls) | Malicious packages, tool poisoning | Recommended |
| R9 | [Code Review Enforcement](#r9-code-review-enforcement) | Insecure code, approval fatigue | Recommended |
| R10 | [Data Classification Policy](#r10-data-classification-policy) | Regulatory violations, IP leakage | Recommended |
| R11 | [Agent Identity & Attribution](#r11-agent-identity--attribution) | Audit gaps, accountability | Recommended |
| R12 | [Incident Response](#r12-incident-response) | Uncontained compromise | Recommended |

---

## Requirements Detail

### R1: Network Egress Control

**Risk:** An AI coding agent with unrestricted internet access can exfiltrate source code, credentials, and proprietary data to any destination — either through prompt injection, malicious tool behavior, or normal operation (sending code to LLM APIs).

**Why this is #1:** Network egress control stops the majority of real attack chains. Prompt injection data theft, supply chain backdoor callbacks, credential exfiltration — all require outbound network access. A deny-all egress policy with explicit allowlisting is the single most impactful control.

**Requirements:**

| ID | Control | Level |
|----|---------|-------|
| R1.1 | Internet access disabled by default. Agent has no route to the internet unless explicitly configured. | Mandatory |
| R1.2 | Outbound access restricted to a domain-level allowlist. Each allowed domain is documented and approved. | Mandatory |
| R1.3 | DNS resolution blocked for non-allowlisted domains (prevents DNS tunneling). | Mandatory |
| R1.4 | Only ports 80 (HTTP) and 443 (HTTPS) permitted through the proxy/firewall. | Mandatory |
| R1.5 | Allowlist treated as a security policy artifact with change management (who can modify, how changes are reviewed). | Recommended |

**Evidence from the field:**
- 63% of employees who used AI tools in 2025 pasted sensitive company data into personal AI accounts (HelpNet Security)
- CVE-2025-53773 (GitHub Copilot, CVSS 9.6) enabled RCE through prompt injection in public repo code comments
- The highest-risk exfiltration path is normal API calls to allowlisted LLM domains — visible at the metadata level but not content-inspectable without MITM

**Framework mapping:** OWASP Agentic ASI02 (Tool Misuse), NIST MANAGE 4.1 (post-deployment monitoring), MITRE ATLAS Exfiltration tactics

---

### R2: Sandbox Isolation

**Risk:** The AI agent executes arbitrary code — that is its core function. Without isolation, a compromised agent (via prompt injection, malicious repo content, or tool poisoning) can escape to the host system, access other containers, or pivot to production infrastructure.

**Requirements:**

| ID | Control | Level |
|----|---------|-------|
| R2.1 | Agent executes inside an isolated environment (container, microVM, or OS-level sandbox). | Mandatory |
| R2.2 | Syscall filtering applied (seccomp whitelist preferred over blacklist). Dangerous syscalls blocked: ptrace, mount, bpf, unshare, io_uring, kernel modules. | Mandatory |
| R2.3 | All capabilities dropped. Only minimal capabilities re-added with justification. | Mandatory |
| R2.4 | Privilege escalation prevented (no-new-privileges flag, non-root execution). | Mandatory |
| R2.5 | Root filesystem read-only. Writable surfaces limited and documented. | Mandatory |
| R2.6 | Temporary directories mounted noexec (blocks direct ELF execution from /tmp, /run). | Recommended |
| R2.7 | Hardware-enforced isolation (gVisor, Firecracker microVM, or Kata Containers) for untrusted code execution. | Recommended |

**Industry context:** OWASP 2026 states "software-only sandboxing is not enough" for untrusted code. E2B uses Firecracker microVMs. OpenAI Codex defaults to cloud containers with network disabled. Claude Code uses OS-level sandboxing (bubblewrap on Linux, seatbelt on macOS). The industry is converging on defense-in-depth with hardware-level isolation as the recommended baseline.

**Known residual risks:**
- `memfd_create` + `execve` enables fileless execution (write ELF to anonymous memory, bypassing noexec)
- Interpreted scripts (`bash /tmp/script.sh`, `python3 /tmp/exploit.py`) bypass noexec (only blocks direct ELF execution)
- Kernel exploits in allowed syscalls remain the primary escape path without gVisor/microVM

**Framework mapping:** OWASP Agentic ASI05 (Unexpected Code Execution), ASI10 (Rogue Agents), MITRE ATLAS Execution tactics

---

### R3: Credential Separation

**Risk:** AI coding agents need API tokens to call LLM services, and developers store SSH keys, cloud credentials, and environment files on their workstations. If the agent can access these, a compromise means full credential theft. Secret leakage runs 40% higher in repositories using AI coding tools (GitGuardian).

**Requirements:**

| ID | Control | Level |
|----|---------|-------|
| R3.1 | LLM API tokens never enter the sandbox. Inject at the proxy/gateway layer with anti-spoofing (strip and re-add headers). | Mandatory |
| R3.2 | SSH keys, cloud credentials, and environment files not mounted into the sandbox. | Mandatory |
| R3.3 | Agent cannot access host home directory, `.ssh/`, `.aws/`, `.kube/`, or global config files. | Mandatory |
| R3.4 | Credentials visible via `docker inspect` or container environment variables documented and minimized. | Recommended |
| R3.5 | Build-time secrets use BuildKit `--secret` (not ARG/ENV which persist in image layer history). | Recommended |

**Evidence:** CVE-2026-21852 (Claude Code) enabled API key exfiltration when starting in attacker-controlled repos. CVE-2025-59536 (Claude Code) enabled arbitrary shell command execution via poisoned project files. Three CVEs targeted Anthropic's official Git MCP server: path traversal, argument injection, and repository scoping bypass.

**Framework mapping:** OWASP Agentic ASI03 (Identity & Privilege Abuse), OWASP LLM02 (Sensitive Information Disclosure), NIST 600-1 Data Privacy

---

### R4: Human Approval Gates

**Risk:** AI agents that can push code, delete files, modify CI/CD pipelines, or interact with external services without human approval create unacceptable blast radius. 80% of organizations reported risky agent behaviors including unauthorized system access (HelpNet Security). The agent itself can reason around restrictions — Claude Code disabled its own sandbox to finish a task with no jailbreak required.

**Requirements:**

| ID | Control | Level |
|----|---------|-------|
| R4.1 | Destructive actions (delete, force-push, deploy) require explicit human confirmation. | Mandatory |
| R4.2 | Actions visible to others (push, PR creation, messaging, external API calls) require confirmation. | Mandatory |
| R4.3 | Tiered autonomy: low-risk actions (read, edit local files) automated; high-impact actions gated. | Recommended |
| R4.4 | Security-critical file modifications (Dockerfile, CI/CD workflows, IAM policies, seccomp profiles) flagged for review. | Recommended |
| R4.5 | Git pre-push hooks or branch protection requiring human approval before code reaches shared branches. | Recommended |

**The approval fatigue problem:** Developers reviewing 50+ agent-generated changes per day develop approval fatigue and stop meaningfully reviewing. This is an organizational risk, not a technical one. Mitigate by limiting agent autonomy scope and requiring meaningful diffs (not rubber-stamp approvals).

**Framework mapping:** OWASP Agentic ASI09 (Human-Agent Trust Exploitation), ASI06 (Excessive Agency), NIST 600-1 Human-AI Configuration, EU AI Act human oversight requirement (high-risk systems)

---

### R5: Audit Logging

**Risk:** Without logging, there is no visibility into agent behavior — no forensics after an incident, no compliance evidence, no anomaly detection. Only 21% of executives have complete visibility into agent permissions and data access patterns.

**Requirements:**

| ID | Control | Level |
|----|---------|-------|
| R5.1 | All network requests logged with structured metadata (timestamp, domain, method, bytes, status, SNI). | Mandatory |
| R5.2 | Both allowed and denied requests logged (denied requests indicate probing/escape attempts). | Mandatory |
| R5.3 | Logs shipped to a central, off-host location (local-only logs have no backup and can be tampered). | Recommended |
| R5.4 | Alerting configured for anomalies: denied request spikes, unusual upload volume, off-hours activity, new user agents. | Recommended |
| R5.5 | Log retention period defined and enforced (90+ days recommended; 6 years for HIPAA). | Recommended |
| R5.6 | In-sandbox activity logged (file access, process execution, command history) for high-security environments. | Optional |
| R5.7 | Tamper-evident logging (append-only store, hash-chaining, authenticated log shipping) for regulated environments. | Optional |

**What to log vs. what you can't:** Proxy-level logging captures WHERE traffic goes but not WHAT is sent (HTTPS encrypted). This is an explicit design tradeoff — no MITM means no content visibility but also no privacy invasion and no TLS certificate management burden. Enterprises requiring content inspection must layer a DLP proxy or use self-hosted LLMs.

**Framework mapping:** NIST GOVERN (accountability), ISO 42001 internal audit, OWASP Agentic ASI03 (attribution), CSA AI Controls Matrix monitoring controls

---

### R6: Filesystem Scoping

**Risk:** The agent needs read/write access to the project workspace. But if it can also read `~/.ssh/`, `~/.aws/`, other projects, or system files, a prompt injection attack becomes a credential harvesting attack. Indirect prompt injection via workspace files (poisoned `.claude/settings.json`, `CLAUDE.md`, `.cursorrules`) is a documented attack vector with CVEs.

**Requirements:**

| ID | Control | Level |
|----|---------|-------|
| R6.1 | Agent can only access its designated workspace directory. No access to host home directory or other projects. | Mandatory |
| R6.2 | Workspace mounted as a named volume or bind mount with explicit path (not broad mounts). | Mandatory |
| R6.3 | System directories and sensitive paths masked or inaccessible from within the sandbox. | Mandatory |
| R6.4 | Writable surfaces documented with size limits where possible (prevent disk exhaustion). | Recommended |
| R6.5 | Workspace snapshots or git-based recovery to enable rollback of agent-caused damage. | Recommended |

**Residual risk:** The agent has full read/write control of `/workspace`. It can delete files, rewrite code, corrupt the repository, or embed backdoors. This is inherent to its function and can only be mitigated through code review (R9) and version control practices.

**Framework mapping:** OWASP Agentic ASI01 (Goal Hijacking via file content), ASI06 (Memory & Context Poisoning), MITRE ATLAS Collection tactics

---

### R7: Resource Limits

**Risk:** A runaway agent (or malicious prompt) can exhaust host resources — memory, CPU, disk, or PIDs — causing denial of service. Agents can also drive up costs through excessive API calls to allowlisted endpoints.

**Requirements:**

| ID | Control | Level |
|----|---------|-------|
| R7.1 | Memory limit enforced (recommended: 8GB default). | Mandatory |
| R7.2 | CPU limit enforced (recommended: 4 cores default). | Mandatory |
| R7.3 | PID limit enforced (recommended: 512; prevents fork bombs). | Mandatory |
| R7.4 | Workspace volume size limit (XFS quotas or similar). | Recommended |
| R7.5 | API call rate limiting at the proxy or gateway level (prevents cost abuse). | Recommended |

**Framework mapping:** OWASP LLM04 (Model Denial of Service), OWASP LLM10 (Unbounded Consumption)

---

### R8: Supply Chain Controls

**Risk:** AI agents install packages, use MCP tools/plugins, and pull dependencies. This creates three supply chain attack surfaces: (1) malicious packages from public registries (typosquatting, "slopsquatting" — agents hallucinate package names that attackers register), (2) poisoned MCP servers or marketplace tools, and (3) compromised model providers or API endpoints.

**Evidence:**
- ~1,184 malicious skills found in the ClawHub registry (1 in 5 packages), including 283 leaking credentials
- The 2025 Postmark MCP breach: fake npm package silently forwarded emails to attacker
- 8,000+ MCP servers found exposed on public internet without authentication
- 45% of AI-generated code contains security flaws (Veracode 2025)
- AI-generated code now causes 1 in 5 breaches (Aikido Security 2026)

**Requirements:**

| ID | Control | Level |
|----|---------|-------|
| R8.1 | Package registries restricted at the network layer (only allowlisted registries reachable). | Recommended |
| R8.2 | Internal package mirrors (Artifactory, Nexus) preferred over public registries for sensitive environments. | Recommended |
| R8.3 | Lock files with integrity hashes enforced. | Recommended |
| R8.4 | MCP servers/tools validated before use. Only authenticated, authorized tool servers connected. | Recommended |
| R8.5 | Agent-suggested dependencies reviewed before installation (watch for hallucinated package names). | Recommended |

**Framework mapping:** OWASP Agentic ASI04 (Agentic Supply Chain), OWASP LLM03 (Supply Chain Vulnerabilities), NIST 600-1 Value Chain, CISA AI Data Security

---

### R9: Code Review Enforcement

**Risk:** Agent-generated code is executed, committed, and deployed. 45% of AI-generated code has security flaws. Developers develop approval fatigue when reviewing high volumes of agent output. The agent can modify security-critical files (CI/CD pipelines, Dockerfiles, IAM policies) alongside application code.

**Requirements:**

| ID | Control | Level |
|----|---------|-------|
| R9.1 | PR-based workflows with mandatory human review for agent-generated code. | Recommended |
| R9.2 | SAST/DAST scanning integrated in CI for all code (agent-generated or not). | Recommended |
| R9.3 | Changes to security-critical files (`.github/workflows/`, `Dockerfile`, IAM configs) trigger additional review. | Recommended |
| R9.4 | Agent-generated commits identifiable in git history (via commit message convention or author). | Recommended |

**Framework mapping:** OWASP Agentic ASI09 (Human-Agent Trust Exploitation), NIST 600-1 Confabulation, ISO 42001 continual improvement

---

### R10: Data Classification Policy

**Risk:** Not all code is equal. Export-controlled code sent to external LLM APIs may constitute an export violation. PII in test fixtures gets sent as prompt context. Proprietary algorithms become training data. The enterprise must decide what data can be processed by which agents on which infrastructure.

**Requirements:**

| ID | Control | Level |
|----|---------|-------|
| R10.1 | Data classification policy defines what can and cannot be processed by AI coding agents. | Recommended |
| R10.2 | Export-controlled (ITAR/EAR) code restricted to self-hosted LLMs with air-gapped configuration. | Context-dependent |
| R10.3 | PII/GDPR-regulated data uses region-specific API endpoints and synthetic test data. DPAs executed with LLM providers. | Context-dependent |
| R10.4 | Intellectual property uses enterprise LLM tiers with zero-retention agreements. | Context-dependent |
| R10.5 | LLM provider data handling policies reviewed (training use, retention, subprocessors). | Recommended |

**Framework mapping:** NIST 600-1 Data Privacy + Intellectual Property, EU AI Act GDPR intersection, ISO 42001 data governance

---

### R11: Agent Identity & Attribution

**Risk:** When an AI agent commits code, pushes to git, creates PRs, or accesses infrastructure — who is responsible? Current systems cannot distinguish "developer did X" from "agent did X" in audit logs. Git history can be rewritten or contaminated. The NIST AI Agent Standards Initiative (Feb 2026) is developing standards for agent identity and authorization.

**Requirements:**

| ID | Control | Level |
|----|---------|-------|
| R11.1 | Agent actions attributable to the developer who initiated them (via hostname labels, session IDs, or dedicated service accounts). | Recommended |
| R11.2 | Agent-generated commits use a distinguishable author or co-author tag. | Recommended |
| R11.3 | Per-developer audit trails (each developer's sandbox produces identifiable log streams). | Recommended |

**Framework mapping:** OWASP Agentic ASI03 (Identity & Privilege Abuse), NIST Agent Standards Initiative (identity pillar)

---

### R12: Incident Response

**Risk:** What happens when an agent behaves unexpectedly? A compromised agent can poison 87% of downstream decision-making within 4 hours in multi-agent systems. Only 16% of enterprises effectively govern AI agent access to core systems.

**Requirements:**

| ID | Control | Level |
|----|---------|-------|
| R12.1 | Incident response plan documented for sandbox compromise or unexpected agent behavior. | Recommended |
| R12.2 | Kill switch available — ability to immediately terminate agent sessions and revoke access. | Recommended |
| R12.3 | Post-incident forensics enabled by audit logs (R5) and workspace snapshots (R6.5). | Recommended |
| R12.4 | Periodic red-teaming of agent sandboxing (prompt injection, escape attempts, exfiltration testing). | Optional |

**Framework mapping:** NIST MANAGE 4.1 (incident management), ISO 42001 continual improvement, CISA incident response integration

---

## Enterprise Scenarios

These scenarios show how the 12 requirements apply at different risk levels. Each scenario maps to a real enterprise situation and produces a different configuration profile.

### Scenario 1: Open-Source Development Team

**Profile:** Small team working on public open-source projects. No sensitive data. Productivity is the priority.

| Requirement | Configuration |
|------------|---------------|
| R1 Network | Allowlist: LLM API + github.com + package registries + documentation sites |
| R2 Sandbox | Container with seccomp whitelist. gVisor optional. |
| R3 Credentials | Gateway token injection for LLM API |
| R4 Approval | Terminal-level confirmation for push/deploy |
| R5 Logging | Local logs sufficient |
| R6 Filesystem | Standard workspace mount |
| R7 Resources | Default limits (8GB/4CPU/512 PID) |
| R8-R12 | Optional |

**Risk level:** MEDIUM. Accepted risks: code goes to external LLM APIs, public registries reachable.

---

### Scenario 2: Enterprise SaaS Development

**Profile:** Large team building a commercial SaaS product. IP protection matters. SOC 2 compliance required.

| Requirement | Configuration |
|------------|---------------|
| R1 Network | Allowlist: Enterprise LLM gateway + github.com + internal package mirror |
| R2 Sandbox | Container with seccomp whitelist + gVisor where available |
| R3 Credentials | Gateway token injection. No host credential access. |
| R4 Approval | PR-based workflow with branch protection |
| R5 Logging | Central SIEM integration. Grafana alerts configured. 90-day retention. |
| R6 Filesystem | Workspace only. Snapshots enabled. |
| R7 Resources | Default limits + volume size quotas |
| R8 Supply chain | Internal package mirror. Lock files enforced. |
| R9 Code review | Mandatory PR review + SAST scanning in CI |
| R10 Data class | Enterprise LLM tier with zero-retention. IP policy documented. |
| R11 Attribution | Per-developer hostname labels. Agent commit tags. |
| R12 Incident | Response plan documented. Kill switch available. |

**Risk level:** HIGH. Accept with mitigations. Key action: enterprise LLM gateway with zero-retention.

---

### Scenario 3: Regulated Financial Services

**Profile:** Bank or fintech. SOC 2 + PCI DSS. Regulatory examination expected. Customer PII in test data.

| Requirement | Configuration |
|------------|---------------|
| R1 Network | Minimal allowlist: enterprise gateway only. No web search. No public registries. |
| R2 Sandbox | Container + gVisor mandatory. Seccomp whitelist. Consider microVM. |
| R3 Credentials | Gateway injection. BuildKit secrets. No env var tokens. |
| R4 Approval | All external-facing actions gated. Security file changes require security team review. |
| R5 Logging | Central SIEM. Tamper-evident logging. 7-year retention. Grafana alerts. |
| R6 Filesystem | Strict workspace scoping. Volume quotas. Snapshots. |
| R7 Resources | Aggressive limits. API rate limiting at gateway. |
| R8 Supply chain | Internal mirror only. No public registries. MCP tools pre-approved. |
| R9 Code review | Mandatory review + SAST/DAST + security-critical file flagging |
| R10 Data class | Synthetic test data. No PII in agent context. DPAs in place. |
| R11 Attribution | Full per-developer audit trail. Agent commits tagged. |
| R12 Incident | Documented plan. Quarterly red-teaming. Regulatory reporting procedures. |

**Risk level:** HIGH. Accept with comprehensive mitigations.

---

### Scenario 4: Defense / Export-Controlled Code

**Profile:** Defense contractor or aerospace. ITAR/EAR-controlled source code. Classified compartments.

| Requirement | Configuration |
|------------|---------------|
| R1 Network | **Air-gapped.** Self-hosted LLM only. No external domains. |
| R2 Sandbox | gVisor mandatory. Consider microVM + SELinux/AppArmor. |
| R3 Credentials | No external tokens. Self-hosted infrastructure only. |
| R4 Approval | All actions gated. Per-compartment sandboxes. |
| R5 Logging | Append-only, tamper-evident. Hash-chained. Shipped to classified SIEM. |
| R6 Filesystem | Per-project bind mounts. Never mix classifications. |
| R7 Resources | Strict limits. |
| R8 Supply chain | Air-gapped. Pre-installed packages only. |
| R9 Code review | Mandatory. Cleared personnel only. |
| R10 Data class | **CRITICAL.** All code classified. Self-hosted LLM only. |
| R11 Attribution | Full audit. Security clearance tied to sandbox access. |
| R12 Incident | Classified incident response procedures. |

**Risk level:** CRITICAL. Do NOT accept risk with external LLM APIs.

---

### Scenario 5: Web Search Enabled vs. Disabled

**Decision factor:** Does the AI agent need to access external documentation and web resources?

| Factor | Allow (scoped) | Deny |
|--------|---------------|------|
| Use case | General development, open-source | Export control, classified, financial |
| Productivity | High — agent looks up docs, examples | Medium — local context only |
| Data leakage | Medium — search queries may contain code | Low — no outbound data beyond LLM API |
| Audit complexity | Higher — more domains to monitor | Lower — fewer log events |
| Configuration | Add: stackoverflow.com, docs.python.org, developer.mozilla.org | LLM API domain only |

**Guidance:** Do NOT add overly broad domains (e.g., google.com encompasses Drive, Gmail, etc.). Scope to specific documentation sites.

---

### Scenario 6: Multi-Tenant / Team Isolation

**Profile:** Multiple teams on shared infrastructure with different security requirements.

| Concern | Approach |
|---------|----------|
| Different allowlists per team | Separate compose stacks with per-team allowlist.yaml |
| Log segregation | Per-team hostname labels + Grafana RBAC |
| Classification mixing | **Never** mix classifications on the same host. Separate hosts per classification level. |
| Policy enforcement | Centralize allowlist management via configuration management (Ansible/Puppet) |
| Shared Docker daemon | Risk — consider separate hosts or Kubernetes with namespace isolation |

---

## Risk Acceptance Matrix

For each requirement, the enterprise documents: **implemented**, **accepted risk**, or **additional controls added**.

| # | Requirement | Implemented? | If Not: Accept or Mitigate? | Notes |
|---|------------|-------------|---------------------------|-------|
| R1 | Network egress control | | | |
| R2 | Sandbox isolation | | | |
| R3 | Credential separation | | | |
| R4 | Human approval gates | | | |
| R5 | Audit logging | | | |
| R6 | Filesystem scoping | | | |
| R7 | Resource limits | | | |
| R8 | Supply chain controls | | | |
| R9 | Code review enforcement | | | |
| R10 | Data classification policy | | | |
| R11 | Agent identity & attribution | | | |
| R12 | Incident response | | | |

### Residual risks that are always accepted

These risks exist regardless of configuration and should be acknowledged:

- **Workspace file access** — The agent has full R/W on `/workspace`. It can delete, modify, or exfiltrate workspace files to allowlisted domains.
- **Encrypted API payloads** — Code sent to LLM APIs is encrypted. Metadata (domain, bytes) is logged but content is not inspectable without MITM.
- **Interpreted script execution** — noexec on `/tmp` only blocks ELF binaries. `bash /tmp/script.sh` and `python3 /tmp/exploit.py` still work.
- **memfd_create bypass** — Enables fileless execution (write ELF to anonymous memory fd). Required by some dev tools; blocking may break workflows.
- **Approval fatigue** — Developers reviewing high volumes of agent output stop meaningfully reviewing. Organizational, not technical.
- **LLM hallucinations in code** — 45% of AI-generated code contains flaws. No sandbox prevents this; code review and SAST are the mitigations.

---

## Mapping to Industry Frameworks

This table maps the 12 requirements to their source frameworks, showing coverage and gaps.

| Requirement | OWASP Agentic 2026 | OWASP LLM 2025 | NIST AI RMF | NIST 600-1 | MITRE ATLAS | ISO 42001 | EU AI Act |
|------------|-------------------|----------------|-------------|-----------|-------------|-----------|-----------|
| R1 Network egress | ASI02 | — | MANAGE | — | Exfiltration | — | — |
| R2 Sandbox isolation | ASI05, ASI10 | LLM02 | — | — | Execution | — | Cybersecurity req. |
| R3 Credential separation | ASI03 | LLM06 | GOVERN | Data Privacy | Credential Access | Data governance | — |
| R4 Human approval | ASI09, ASI02 | LLM08 | MANAGE | Human-AI Config | — | Controls | Human oversight |
| R5 Audit logging | ASI03 | — | GOVERN | — | — | Internal audit | Documentation |
| R6 Filesystem scoping | ASI01, ASI06 | LLM01 | — | — | Collection | — | — |
| R7 Resource limits | — | LLM04, LLM10 | — | — | — | — | — |
| R8 Supply chain | ASI04 | LLM03 | MAP | Value Chain | Supply chain | Third-party | — |
| R9 Code review | ASI09 | LLM09 | MEASURE | Confabulation | — | Improvement | Accuracy req. |
| R10 Data classification | ASI03 | LLM06 | GOVERN | IP, Privacy | — | Data governance | GDPR |
| R11 Agent identity | ASI03 | — | GOVERN | — | — | — | Transparency |
| R12 Incident response | ASI08 | — | MANAGE | — | — | Improvement | Post-market |

### Notable framework gaps

| Gap | Description | Not covered by |
|-----|-------------|---------------|
| Hallucinated packages ("slopsquatting") | Agents fabricate package names; attackers register them | All frameworks (partially in ASI04) |
| CI/CD pipeline manipulation | Agent modifies `.github/workflows/` to disable security gates | All frameworks |
| Approval fatigue | Developers stop reviewing agent output due to volume | All frameworks (partially in ASI09) |
| Security config as code | Agent modifies seccomp, IAM, Dockerfile alongside app code | All frameworks |
| Git history contamination | Agent rewrites history, force-pushes, obscures provenance | All frameworks |
| Developer workstation as initial access | Compromised agent pivots via SSH keys, kubeconfig to production | ATLAS (generic lateral movement only) |

---

## Sources

### Frameworks
- [OWASP Top 10 for LLM Applications 2025](https://genai.owasp.org/resource/owasp-top-10-for-llm-applications-2025/)
- [OWASP Top 10 for Agentic Applications 2026](https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/)
- [OWASP AI Agent Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html)
- [NIST AI RMF 1.0 (AI 100-1)](https://nvlpubs.nist.gov/nistpubs/ai/nist.ai.100-1.pdf)
- [NIST AI 600-1 GenAI Profile](https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf)
- [NIST AI Agent Standards Initiative](https://www.nist.gov/caisi/ai-agent-standards-initiative)
- [MITRE ATLAS](https://atlas.mitre.org/)
- [MITRE SAFE-AI Framework](https://atlas.mitre.org/pdf-files/SAFEAI_Full_Report.pdf)
- [ISO/IEC 42001:2023](https://www.iso.org/standard/42001)
- [EU AI Act](https://artificialintelligenceact.eu/)
- [CSA AI Safety Initiative](https://cloudsecurityalliance.org/ai-safety-initiative)
- [CISA AI Data Security Guidance](https://media.defense.gov/2025/May/22/2003720601/-1/-1/0/CSI_AI_DATA_SECURITY.PDF)

### Incidents & Research
- [CVE-2025-53773 — GitHub Copilot RCE (CVSS 9.6)](https://www.pillar.security/blog/new-vulnerability-in-github-copilot-and-cursor-how-hackers-can-weaponize-code-agents)
- [CVE-2025-59536 — Claude Code RCE via project files](https://research.checkpoint.com/2026/rce-and-api-token-exfiltration-through-claude-code-project-files-cve-2025-59536/)
- [CVE-2026-21852 — Claude Code API key exfiltration](https://thehackernews.com/2026/02/claude-code-flaws-allow-remote-code.html)
- [GitGuardian: Copilot secret leakage (40% higher)](https://blog.gitguardian.com/yes-github-copilot-can-leak-secrets/)
- [Veracode: 45% of AI-generated code has flaws](https://www.veracode.com/)
- [Aikido Security: AI code causes 1 in 5 breaches](https://www.aikido.dev/blog/ai-as-a-power-tool-how-windsurf-and-devin-are-changing-secure-coding)
- [Pillar Security: Hidden risks of SWE agents](https://www.pillar.security/blog/the-hidden-security-risks-of-swe-agents-like-openai-codex-and-devin-ai)
- [HelpNet Security: 80% report risky agent behaviors](https://www.helpnetsecurity.com/2026/02/23/ai-agent-security-risks-enterprise/)
- [8,000+ MCP servers exposed](https://cikce.medium.com/8-000-mcp-servers-exposed-the-agentic-ai-security-crisis-of-2026-e8cb45f09115)

### Industry Approaches
- [Anthropic: Claude Code sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing)
- [OpenAI Codex security model](https://developers.openai.com/codex/security/)
- [E2B: Firecracker microVM sandboxing](https://e2b.dev/docs)
- [Daytona: Dev environment security](https://www.daytona.io/docs/en/security-exhibit/)
- [NVIDIA: Sandboxing agentic workflows](https://developer.nvidia.com/blog/practical-security-guidance-for-sandboxing-agentic-workflows-and-managing-execution-risk/)
- [Coalition for Secure AI: MCP Security Guide](https://www.coalitionforsecureai.org/securing-the-ai-agent-revolution-a-practical-guide-to-mcp-security/)

---

*Document generated from industry research across OWASP, NIST, MITRE, ISO, EU AI Act, CSA, and CISA frameworks. Last updated: 2026-03-07.*

# Responsibility Boundary

What safe-ai controls at the infrastructure level vs what the agent platform and organization must handle.

---

## safe-ai provides (infrastructure level)

| Control | Requirement | How |
|---------|-------------|-----|
| Network isolation and domain allowlisting | R1 | Docker `internal: true` network + Squid proxy with domain ACLs + dnsmasq filtering |
| Container sandbox | R2 | Seccomp whitelist, `cap_drop: ALL`, read-only root, noexec tmpfs, `no-new-privileges` |
| Credential separation | R3 | Gateway token injected at the proxy layer; API keys never enter the sandbox |
| Audit logging of all proxy traffic | R5 | Structured JSON logs for every allowed and denied request, shippable to central SIEM |
| Filesystem scoping to /workspace | R6 | Named volume mount; sandbox cannot access host filesystem |
| Resource limits | R7 | Memory, CPU, and PID limits enforced via Docker cgroups |

These controls are enforced by the container runtime and network stack. The AI agent cannot disable or bypass them from inside the sandbox.

## The agent platform / organization must provide

| Control | Requirement | Why safe-ai cannot enforce it |
|---------|-------------|-------------------------------|
| Human approval gates for destructive actions | R4 | safe-ai ships a git pre-push hook, but cannot gate arbitrary agent tool use (file deletion, API calls, CI modifications). Approval gates must be implemented at the agent platform level. |
| Code review enforcement | R9 | safe-ai tags agent commits with a distinguishable author, but cannot enforce PR workflows or mandatory review. That is a GitHub/GitLab policy. |
| Data classification policy | R10 | The allowlist IS the enforcement mechanism -- if a domain is not listed, data cannot reach it. But the decision of which data requires which classification is organizational. |
| Full agent identity beyond git commits | R11 | safe-ai provides hostname labels and commit tags for attribution. Per-developer service accounts, session tracking, and identity federation are platform responsibilities. |
| Incident response execution | R12 | safe-ai provides the runbook (`docs/incident-response.md`) and tooling (`make kill`, `make snapshot`). The organization executes the response. |

## What safe-ai does NOT prevent inside the sandbox

> **An agent inside safe-ai can still delete workspace files, rewrite CI configs, or push to GitHub. These actions are within the sandbox but outside safe-ai's control surface.**

The sandbox constrains WHERE data can go (network allowlist) and WHAT the process can do to the host (seccomp, capabilities, read-only root). It does not constrain what the agent does within `/workspace`. Specifically:

- Deleting or corrupting workspace files
- Rewriting `.github/workflows/`, `Dockerfile`, or other security-critical files
- Running `git push` to an allowlisted remote (e.g., github.com)
- Making API calls to any allowlisted domain
- Installing packages from allowlisted registries

These actions are mitigated by code review (R9), human approval gates (R4), and audit logging (R5) -- not by the sandbox itself.

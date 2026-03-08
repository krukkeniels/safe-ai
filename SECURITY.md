# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in safe-ai, please report it responsibly:

1. **Do not** open a public GitHub issue
2. Email: security@safe-ai.dev (or use GitHub's private vulnerability reporting)
3. Include: description, reproduction steps, affected versions, potential impact

We aim to acknowledge reports within 48 hours and provide a fix timeline within 7 days.

## Scope

The following are in scope for security reports:
- Container escape from sandbox
- Proxy bypass (reaching non-allowlisted domains)
- Seccomp profile bypass
- Privilege escalation within sandbox
- Credential leakage (gateway token exposure to sandbox)
- Log injection or tampering

## Out of Scope

- Vulnerabilities in upstream dependencies (report to the upstream project)
- Social engineering attacks
- Denial of service against the host
- Issues requiring host-level access (if you have root on the host, the sandbox is moot)

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest release | Yes |
| Previous release | Security fixes only |
| Older | No |

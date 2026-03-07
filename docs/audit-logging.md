# Audit Logging

Optional centralized audit logging records every allowed and denied proxy request for security review.

```
Dev Workstation                          Central Log Server (optional)
┌──────────────────────────┐             ┌──────────────────┐
│ proxy (Squid JSON logs)  │             │                  │
│   ↓ shared volume        │             │  Loki            │
│ Fluent Bit (log shipper)─│─────────────│──→ (port 3100)  │
│                          │             │                  │
│ Loki (local, optional)   │             │  Grafana         │
│ Grafana (localhost:3000) │             │  (port 3000)     │
└──────────────────────────┘             └──────────────────┘
```

## Quick start (local)

Try audit logging with zero external infrastructure:

```bash
docker compose --profile logging up -d    # starts Fluent Bit + Loki + Grafana
open http://localhost:3000                 # Grafana dashboard (admin/admin)
```

Or use `make up-logging` / `make grafana`.

## Central Loki server

Ship logs to a shared server instead of local storage:

```bash
# In .env
SAFE_AI_LOKI_URL=http://loki.internal.example.com:3100
SAFE_AI_HOSTNAME=dev-alice-laptop

# Start (local Loki/Grafana also start but Fluent Bit ships to the URL)
docker compose --profile logging up -d
```

Supports basic auth: `SAFE_AI_LOKI_URL=https://user:pass@loki.internal.example.com:3100`

See `examples/central-logging/` for a ready-to-deploy central Loki + Grafana stack.

## LogQL query examples

```bash
# All denied requests
{job="safe-ai"} | json | squid_action="TCP_DENIED"

# Requests from a specific workstation
{job="safe-ai", hostname="dev-alice-laptop"}

# Large responses (potential exfiltration)
{job="safe-ai"} | json | response_bytes > 1000000
```

## Log format

Squid outputs one JSON object per request:

```json
{"timestamp":"27/Feb/2026:10:30:45 -0500","duration_ms":123,"client_ip":"172.28.0.3",
 "method":"CONNECT","url":"api.anthropic.com:443","http_status":200,
 "squid_action":"TCP_TUNNEL","request_bytes":500,"response_bytes":12000,
 "sni":"api.anthropic.com"}
```

Key fields: `squid_action` (TCP_DENIED = blocked, TCP_TUNNEL = allowed HTTPS), `response_bytes` (data volume), `sni` (destination domain).

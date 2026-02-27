# Central Logging Server for safe-ai

Deploy Loki + Grafana on a central server to collect audit logs from all safe-ai workstations.

## Deploy

```bash
cd examples/central-logging

# Set a strong Grafana admin password
echo 'GRAFANA_ADMIN_PASSWORD=your-secure-password' > .env

# Start
docker compose up -d
```

## Configure workstations

On each dev workstation, set `SAFE_AI_LOKI_URL` to point here:

```bash
# In the workstation's safe-ai .env file:
SAFE_AI_LOKI_URL=http://<server-ip>:3100
SAFE_AI_HOSTNAME=dev-alice-laptop

# Start with logging
docker compose --profile logging up -d
```

With basic auth:

```bash
SAFE_AI_LOKI_URL=https://user:pass@loki.internal.example.com:3100
```

## View logs

Open `http://<server-ip>:3000` in your browser. The "safe-ai Audit Log" dashboard is pre-provisioned.

### Example LogQL queries

```
# All denied requests
{job="safe-ai"} | json | squid_action="TCP_DENIED"

# Requests from a specific workstation
{job="safe-ai", hostname="dev-alice-laptop"}

# Large responses (potential data exfiltration)
{job="safe-ai"} | json | response_bytes > 1000000

# All CONNECT tunnels (HTTPS traffic)
{job="safe-ai"} | json | method="CONNECT"
```

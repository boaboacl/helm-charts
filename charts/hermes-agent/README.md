# hermes-agent

Deploys [NousResearch Hermes Agent](https://github.com/NousResearch/hermes-agent) as a single stateful pod running `gateway run` under the image's internal s6-overlay supervision, with the supervised web dashboard and the OpenAI-compatible API server exposed as Services.

Built on the [bjw-s common library](https://github.com/bjw-s-labs/helm-charts) (v5.x).

## Requirements

- Kubernetes >= 1.31 (imposed by the common library)
- A default StorageClass (the chart creates an 8Gi PVC for `/opt/data`)

## Before installing

The image reads credentials from environment variables (which override `/opt/data/.env`). Create a Secret out-of-band with everything the agent needs:

```bash
kubectl create ns hermes

cat > hermes.env <<'EOF'
# Required: at least one model provider key
OPENAI_API_KEY=sk-...
# ANTHROPIC_API_KEY=sk-ant-...

# Required with default values (dashboard auth gate fails closed otherwise)
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=change-me
HERMES_DASHBOARD_BASIC_AUTH_SECRET=openssl-rand-hex-32-output

# Recommended before exposing the API service
# API_SERVER_KEY=run-openssl-rand-hex-32

# Optional: chat platform tokens
# TELEGRAM_BOT_TOKEN=...
# DISCORD_BOT_TOKEN=...
EOF

kubectl -n hermes create secret generic hermes-agent-env --from-env-file=hermes.env
```

> The chart never creates Secrets from values and no secret material belongs in `values.yaml`.

## Install

```bash
helm install hermes ./charts/hermes-agent -n hermes
# or from this repo once released:
helm repo add pperez https://pperez.github.io/helm-charts
helm install hermes pperez/hermes-agent -n hermes
```

Use a different Secret name via `secret.existingSecret=my-secret` (disable env injection with `secret.existingSecret=""`).

## Access

| Surface | Service | Port | Notes |
|---|---|---|---|
| Web dashboard | `hermes-agent-main` | 9119 | basic-auth via the Secret vars; supervised by s6 |
| OpenAI-compatible API | `hermes-agent-api` | 8642 | set `API_SERVER_KEY` (min 8 chars) before use |

Port-forward for a quick look: `kubectl -n hermes port-forward svc/hermes-agent-main 9119:9119`

### Enabling an Ingress for the dashboard

Use a values file (`my-values.yaml`) — nested arrays like `hosts` are replaced wholesale by `--set`, so `--set 'ingress.main.hosts[0].host=...'` would drop the paths:

```yaml
ingress:
  main:
    enabled: true
    hosts:
      - host: hermes.example.com
        paths:
          - path: /
            pathType: Prefix
            service:
              identifier: main
              port: 9119
```

## Values

| Key | Default | Description |
|---|---|---|
| `controllers.main.containers.main.image.tag` | `v2026.9.24` | Pinned upstream image tag (CalVer) |
| `secret.existingSecret` | `hermes-agent-env` | Existing Secret injected as env via `envFrom` |
| `persistence.data.size` | `8Gi` | Size of the `/opt/data` PVC (all agent state) |
| `persistence.data.retain` | `true` | Keep the PVC on uninstall |
| `controllers.main.containers.main.env` | see `values.yaml` | `HERMES_DASHBOARD`, `API_SERVER_*`, `TZ` |
| `service.main.ports.http.port` | `9119` | Dashboard |
| `service.api.ports.http.port` | `8642` | OpenAI-compatible API |
| `ingress.main.enabled` | `false` | Dashboard Ingress (see snippet above) |

All other options follow the [common library values](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).

## Constraints

- **Exactly one replica.** All state (sessions, memory, skills, SQLite `state.db`) lives on the single `/opt/data` volume; concurrent gateways corrupt it. The chart refuses to render with `replicas > 1`.
- **Never share `/opt/data`** between two hermes deployments.
- **Do not override the container command/entrypoint** — the s6-overlay dispatcher must own PID 1 for supervised services (gateway, dashboard, per-profile gateways).
- The pod starts as root (`runAsUser: 0`) so the image's stage2 init can fix volume ownership; s6 then drops everything to the `hermes` user (UID 10000).
- Upgrades: bump the image tag and `helm upgrade`; the image runs config migrations on boot. PVC is retained.

## Managing the agent

The setup wizard is skipped in favor of env-only bootstrap. For anything else, exec into the running pod — the `hermes` shim drops root automatically:

```bash
kubectl -n hermes exec deploy/hermes-agent -- hermes gateway status
kubectl -n hermes exec deploy/hermes-agent -- hermes profile create coder
kubectl -n hermes exec deploy/hermes-agent -- hermes logs --follow
```

Additional profiles are s6-supervised in the same pod; give each profile its own `API_SERVER_PORT` if you expose more than one API server.

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
# GLM_API_KEY=...          # z.ai / ZhipuAI GLM (provider: zai; the coding-plan
#                           # endpoint is auto-detected from the key)

# Required with default values (dashboard auth gate fails closed otherwise)
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=change-me        # what you type at login
HERMES_DASHBOARD_BASIC_AUTH_SECRET=openssl-rand-base64-32-output  # session token-signing key; set it so logins survive pod restarts

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
# or from this repo's published charts:
helm repo add boaboacl https://boaboacl.github.io/helm-charts
helm install hermes boaboacl/hermes-agent -n hermes
```

Use a different Secret name via `secret.existingSecret=my-secret` (disable env injection with `secret.existingSecret=""`).

> The model choice itself (`model.provider` / `model.default` in `config.yaml`) has no env var by design — set it after first boot via the dashboard (**Models → Change**) or `kubectl exec -it deploy/hermes-agent -- hermes model`. It persists in the PVC.

## Deploying with ArgoCD (GitOps)

This chart is deployed by [boaboa-iac](https://github.com/boaboacl/boaboa-iac) using the app-of-apps pattern:

- `applications/hermes-agent/apps/helm.yaml` — ArgoCD Application sourcing this chart (`targetRevision: "0.*"`) with `valuesObject` for `secret.existingSecret` and the ingress
- `applications/hermes-agent/resources/` — a SealedSecret (sealed for the target namespace) replacing the manual `kubectl create secret` step:

```bash
kubectl -n applications create secret generic hermes-agent-env \
  --from-env-file=hermes.env --dry-run=client -o yaml \
  | kubeseal --controller-namespace kube-system \
      --controller-name sealed-secrets-controller \
      --namespace applications -o yaml \
  > hermes-agent-env-sealed.yaml
```

Keep channel tokens in the SealedSecret only — env vars override whatever the dashboard's QR-pairing flows write to `/opt/data/.env`.

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

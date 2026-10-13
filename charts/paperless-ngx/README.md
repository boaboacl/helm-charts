# paperless-ngx

Deploys [Paperless-ngx](https://docs.paperless-ngx.com/) — the document management system that indexes, OCRs, and archives scanned documents — as a single stateful deployment plus a bundled bare Redis (task queue broker), backed by an external PostgreSQL database.

Built on the [bjw-s common library](https://github.com/bjw-s-labs/helm-charts) (v5.x), same convention as `charts/hermes-agent`.

## Requirements

- Kubernetes >= 1.31 (imposed by the common library)
- A default StorageClass (the chart creates PVCs for `media`/`data`/`export`)
- An external PostgreSQL database; credentials delivered via a Kubernetes Secret (in the target homelab this is the Crossplane-managed `paperless-pgsql-conn` connection Secret with `username`/`password` keys)

## Secret contract

The chart never creates Secrets from values and no secret material belongs in `values.yaml`. Paperless reads its credentials from environment variables, provided by two mechanisms:

1. **`secret.existingSecrets`** — Secrets injected wholesale via `envFrom` into the main container. Defaults to:

   | Secret | Contents |
   |---|---|
   | `paperless-secret-key` | `PAPERLESS_SECRET_KEY` (Django signing key) |
   | `paperless-admin` | `PAPERLESS_ADMIN_USER`, `PAPERLESS_ADMIN_PASSWORD` (superuser created on first boot) |
   | `paperless-socialaccount` | `PAPERLESS_SOCIALACCOUNT_PROVIDERS` (Authentik OIDC provider settings) |

   Set to `[]` to disable env injection entirely.

2. **`PAPERLESS_DBUSER` / `PAPERLESS_DBPASS`** — pulled per-key via `valueFrom.secretKeyRef` from the Crossplane connection Secret `paperless-pgsql-conn` (keys `username` / `password`).

> Note: a `paperless-oidc` SealedSecret (containing `CLIENT_SECRET`) also exists in the target namespace but is not consumed by this chart — it is read by the Authentik blueprint (`blueprints/paperless-ngx.yaml`) via `!File` on the Authentik side.

## Ports

| Surface | Service | Port | Notes |
|---|---|---|---|
| Web UI / API | `paperless-ngx-main` | 8000 | SSO-only login by default (`PAPERLESS_DISABLE_REGULAR_LOGIN=true`) |
| Redis broker | `paperless-ngx-redis` | 6379 | Cluster-internal, consumed by paperless only |

`PAPERLESS_REDIS` is derived automatically as `redis://<fullname>-redis:6379`, so it follows the release name.

## Install

```bash
helm repo add boaboacl https://boaboacl.github.io/helm-charts
helm install paperless-ngx boaboacl/paperless-ngx -n applications
```

### Deploying with ArgoCD (GitOps)

This chart is deployed by [boaboa-iac](https://github.com/boaboacl/boaboa-iac) using the app-of-apps pattern:

- `applications/paperless-ngx/app.yaml` — ArgoCD Application sourcing this chart (`targetRevision: "0.*"`) with `valuesObject` enabling the Traefik ingress, plus a second source with the namespace's SealedSecrets and the Crossplane database objects
- The SealedSecrets are sealed for the target namespace out-of-band; keep secret material there only

### Enabling the Ingress

Use a values file (nested arrays like `hosts` are replaced wholesale by `--set`, so `--set 'ingress.main.hosts[0].host=...'` would drop the paths):

```yaml
ingress:
  main:
    enabled: true
    className: traefik
    annotations:
      traefik.ingress.kubernetes.io/router.tls: "true"
    hosts:
      - host: paperless.example.com
        paths:
          - path: /
            pathType: Prefix
            service:
              identifier: main
              port: 8000
    tls:
      - hosts:
          - paperless.example.com
```

## Values

| Key | Default | Description |
|---|---|---|
| `controllers.main.containers.main.image.tag` | `2.20.15` | Pinned upstream image tag |
| `secret.existingSecrets` | see above | Existing Secrets injected via `envFrom` |
| `controllers.main.containers.main.env` | see `values.yaml` | `PAPERLESS_URL`, DB host/name, OCR languages, OIDC/allauth settings, `TZ` |
| `persistence.media.size` | `20Gi` | Scanned documents and thumbnails (`/usr/src/paperless/media`) |
| `persistence.data.size` | `5Gi` | App state, search index (`/usr/src/paperless/data`) |
| `persistence.export.size` | `10Gi` | `document_exporter` target (`/usr/src/paperless/export`) |
| `persistence.*.retain` | `true` | Keep PVCs on uninstall (`helm.sh/resource-policy: keep`) |
| `service.main.ports.http.port` | `8000` | Web UI / API |
| `service.redis.ports.redis.port` | `6379` | Redis broker |
| `ingress.main.enabled` | `false` | Web UI Ingress (see snippet above) |

All other options follow the [common library values](https://github.com/bjw-s-labs/helm-charts/tree/main/charts/library/common).

## Constraints

- **Exactly one replica.** All state lives on single RWO volumes and the bundled Redis is a single instance. The chart refuses to render with `controllers.main.replicas > 1`.
- **Fresh-volume policy.** The cutover from the previous raw-manifest deployment intentionally started from fresh PVCs (2026-10). Note: Argo pruned the legacy volumes during the cutover — the `Delete=false` sync option guards app-deletion cascades, not source-switch pruning.
- **Migrations on boot.** First boot (or a version bump) runs Django migrations on the database before the app serves — the startup probe allows up to 5 minutes.
- The image manages its own privilege handling at startup (volume ownership fixes); no explicit `securityContext` is imposed.

## Managing paperless

Exec into the main container for management commands:

```bash
kubectl -n applications exec deploy/paperless-ngx-main -- document_exporter /usr/src/paperless/export
kubectl -n applications exec deploy/paperless-ngx-main -- superuser --help
```

Upgrades: bump the image tag in `values.yaml` (and `appVersion` in `Chart.yaml`), bump the chart version, and let Argo/`helm upgrade` roll the deployment. PVCs are retained.

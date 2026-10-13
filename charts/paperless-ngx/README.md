# paperless-ngx

Deploys [Paperless-ngx](https://docs.paperless-ngx.com/) — the document management system that indexes, OCRs, and archives scanned documents — as a single stateful deployment plus a bundled bare Redis (task queue broker). Defaults to SQLite; an external database, SSO, and all site config are wired via consumer values.

Built on the [bjw-s common library](https://github.com/bjw-s-labs/helm-charts) (v5.x), same convention as `charts/hermes-agent`.

## Requirements

- Kubernetes >= 1.31 (imposed by the common library)
- A default StorageClass (the chart creates PVCs for `media`/`data`/`export`)
- Optional: an external PostgreSQL database; credentials delivered via a Kubernetes Secret referenced with `valueFrom.secretKeyRef`

## Secret contract

The chart never creates Secrets from values and no secret material belongs in `values.yaml`. Paperless reads its credentials from environment variables, provided by two mechanisms (both consumer-supplied; see the example below):

1. **`secret.existingSecrets`** — Secrets injected wholesale via `envFrom` into the main container. Disabled by default (`[]`); typical entries:

   | Secret (example names) | Contents |
   |---|---|
   | `paperless-secret-key` | `PAPERLESS_SECRET_KEY` (Django signing key) |
   | `paperless-admin` | `PAPERLESS_ADMIN_USER`, `PAPERLESS_ADMIN_PASSWORD` (superuser created on first boot) |
   | `paperless-socialaccount` | `PAPERLESS_SOCIALACCOUNT_PROVIDERS` (OIDC provider settings) |

2. **`PAPERLESS_DBUSER` / `PAPERLESS_DBPASS`** — pulled per-key via `valueFrom.secretKeyRef` from an existing connection Secret (keys `username` / `password`).

> Note: a `paperless-oidc` SealedSecret (containing `CLIENT_SECRET`) also exists in the target namespace but is not consumed by this chart — it is read by the Authentik blueprint (`blueprints/paperless-ngx.yaml`) via `!File` on the Authentik side.

## Ports

| Surface | Service | Port | Notes |
|---|---|---|---|
| Web UI / API | `paperless-ngx-main` | 8000 | login behavior is consumer config (SSO-only if you set the allauth env) |
| Redis broker | `paperless-ngx-redis` | 6379 | Cluster-internal, consumed by paperless only |

`PAPERLESS_REDIS` is derived automatically as `redis://<fullname>-redis:6379`, so it follows the release name.

## Install

```bash
helm repo add boaboacl https://boaboacl.github.io/helm-charts
helm install paperless-ngx boaboacl/paperless-ngx -n applications
```

### Deploying with ArgoCD (GitOps)

This chart is deployed by [boaboa-iac](https://github.com/boaboacl/boaboa-iac) using the app-of-apps pattern:

- `applications/paperless-ngx/app.yaml` — ArgoCD Application sourcing this chart (`targetRevision: "0.*"`) with `valuesObject` carrying the full site config (see below), plus a second source with the namespace's SealedSecrets and the Crossplane database objects
- The SealedSecrets are sealed for the target namespace out-of-band; keep secret material there only

## Site config is consumer-supplied

The chart ships no site identity — SQLite default, no TZ, no Secret names as
live defaults (see [docs/CHART_CONVENTIONS.md](../../docs/CHART_CONVENTIONS.md)).
The homeserver's production wiring (Postgres via a Crossplane connection
Secret, Authentik OIDC, OCR languages, TZ) lives in boaboa-iac's
`valuesObject`; adapted excerpt:

```yaml
controllers:
  main:
    containers:
      main:
        env:
          TZ: America/Santiago
          PAPERLESS_URL: https://paperless.example.com
          PAPERLESS_DBENGINE: postgres
          PAPERLESS_DBHOST: my-postgres-host
          PAPERLESS_DBNAME: paperless
          PAPERLESS_DBUSER:
            valueFrom:
              secretKeyRef:
                name: my-paperless-db-conn
                key: username
          PAPERLESS_DBPASS:
            valueFrom:
              secretKeyRef:
                name: my-paperless-db-conn
                key: password
          PAPERLESS_OCR_LANGUAGES: spa
          PAPERLESS_OCR_LANGUAGE: eng+spa
          PAPERLESS_APPS: allauth.socialaccount.providers.openid_connect
          PAPERLESS_DISABLE_REGULAR_LOGIN: "true"
          PAPERLESS_REDIRECT_LOGIN_TO_SSO: "true"
          PAPERLESS_SOCIAL_ACCOUNT_SYNC_GROUPS: "true"
secret:
  existingSecrets:
    - paperless-secret-key
    - paperless-admin
    - paperless-socialaccount
```

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
| `secret.existingSecrets` | `[]` | Existing Secrets injected via `envFrom` (disabled until set) |
| `controllers.main.containers.main.env` | see `values.yaml` | empty by default — SQLite + bundled redis; DB/auth/TZ wiring is consumer-supplied (examples commented in `values.yaml`) |
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

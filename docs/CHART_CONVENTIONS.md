# Chart Conventions: Charts vs Cluster Configuration

Charts in this repo are **generic and cluster-agnostic**. Everything that
encodes *a specific deployment's identity* is supplied by the consumer's
values — for this homelab, that means the Argo CD `valuesObject` blocks in
[boaboa-iac](https://github.com/boaboacl/boaboa-iac). The reference model is
TrueCharts
([trueforge-org/truecharts, charts/stable/prowlarr/values.yaml](https://github.com/trueforge-org/truecharts/blob/master/charts/stable/prowlarr/values.yaml)):
chart defaults describe the *application*, never the *site*.

## Chart defaults MAY contain (app-generic)

- Pinned container images, container ports, probes
- Volume mount paths and default sizes
- Default resource requests/limits (sane app-generic sizing)
- Image-specific securityContext requirements (e.g. hermes-agent boots as
  root so s6-overlay stage2 can fix volume ownership, then drops to UID 10000)
- Feature toggles, disabled by default (ingress, metrics, sidecars)
- Env derived from chart-internal values or the release fullname (e.g.
  `PAPERLESS_REDIS` → `redis://<fullname>-redis:6379`; TrueCharts derives
  `PROWLARR__SERVER__PORT` from `.Values.service.main.ports.main.port`)
- Bundled dependencies (e.g. paperless's redis) and their wiring

## Chart defaults MUST NOT contain (site identity)

- Hostnames, domains, TLS specifics, ingress classes
- `TZ` or any locale/language setting — charts omit `TZ` entirely (no UTC
  default either); consumers set it
- Cluster service FQDNs (`.svc.cluster.local`) or database hosts
- Secret *names* wired as live defaults — `secret.existingSecret(s)` defaults
  to empty/disabled; names are consumer config
- Auth-stack wiring (OIDC providers, SSO env vars)
- Storage class names, node selectors, hostPath bindings

## Optional app settings: commented examples, never live defaults

When an app setting is genuinely useful but deployment-specific (database
wiring, auth stacks, themes), the chart shows it as a **commented example**
in `values.yaml` plus a README section — it does not ship a live placeholder
value. A fresh `helm install` with no values must yield a self-contained,
working default deployment of the application (e.g. paperless-ngx defaults to
SQLite + its bundled redis).

## Secret posture

Charts never create Secrets from values and never contain secret material.
Consumers deliver Secrets out-of-band (boaboa-iac uses SealedSecrets) and
reference them by name via `secret.existingSecret` / `secret.existingSecrets`
(injected wholesale as env).

## No-behavior-change verification (render parity)

When moving config between chart and consumer, prove nothing changed:
Helm's Go templates iterate maps in sorted key order, so identical merged
values render **byte-identical** output regardless of whether a key arrived
via chart defaults or a consumer override:

```bash
helm template <release> charts/<chart> -f site-values.yaml > after.yaml
diff before-live.yaml after.yaml   # must be empty
```

## Enforcement

`scripts/check-charts-agnostic.sh` (CI: `.github/workflows/lint.yaml`) fails
when site-specific patterns appear in any `charts/*/values.yaml`: references
to this site's names/domains, `.svc.cluster.local` FQDNs, `TZ:` keys, or
IANA `Region/City` timezone values.

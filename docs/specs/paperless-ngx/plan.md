# Plan: paperless-ngx Helm Chart

Approved plan from the 2026-10-13 planning session (user confirmed all four decision points).

## Approach

Port the raw paperless-ngx manifests from boaboa-iac into a self-contained chart following the `hermes-agent` convention (bjw-s-labs common 5.2.1, minimal templates, guard, README), then refactor the boaboa-iac Argo Application to a two-source app-of-apps pointing at the published chart.

## Implementation order

1. **Chart scaffold** — `Chart.yaml` (v0.1.0, appVersion `2.20.15`, dep `common` 5.2.1), `templates/common.yaml` with the loader include + pre-loader mutations (`envFrom` from `secret.existingSecrets`, `PAPERLESS_REDIS` from fullname), `helm dependency update` (commit Chart.lock only — root `.gitignore` already excludes `**/charts/*.tgz`).
2. **Workload values** — `controllers.main` (paperless: Recreate, replicas 1, env set from live manifests, native `valueFrom` for DB creds, httpGet probes with startup window), `controllers.redis` (bare `redis:7-alpine`), `templates/guard.yaml` (fail on `replicas > 1`). Checkpoint: render review against SPEC "Values design".
3. **Services, persistence, ingress** — `service.main` (8000, controller main), `service.redis` (6379, controller redis); `persistence` media 20Gi / data 5Gi / export 10Gi, RWO, `retain: true`; `ingress.main` scaffold disabled by default.
4. **README + full verification pass** — secret contract, ports, env table, migration notes (fresh volumes; old PVCs survive via `Delete=false`; `paperless-oidc` SealedSecret currently unconsumed). Then: `helm lint`, grep-asserted default render, guard negative test, variant renders (empty secrets list, ingress on, alternate release name).
5. **boaboa-iac refactor (separate repo, own spec)** — two-source Argo Application (chart @ `"0.*"` + slimmed `resources/` with the 4 SealedSecrets + Crossplane DB yaml), update `specs/document-management/spec.md`.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| bjw-s resource naming differs from assumption | Verified against vendored `common-5.2.1.tgz`; confirmed again via `helm template` render before hand-off |
| Chart publish lag vs Argo sync | Argo app targets `targetRevision: "0.*"`; merge helm-charts PR first, confirm the chart appears on `boaboacl.github.io/helm-charts`, then merge boaboa-iac PR |
| First boot slower than probes tolerate (migrations on empty volumes) | Startup probe with generous failureThreshold; current 60s initialDelay pattern replaced by startup window |
| Old PVCs pruned/orphaned at cutover | Either outcome accepted — user explicitly abandoned the data |

## Parallelization

Tasks 1–4 are sequential (same files, cumulative render checks). Task 5 depends on the chart being publishable but can be drafted in parallel.

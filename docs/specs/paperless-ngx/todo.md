# Tasks: paperless-ngx Helm Chart

## Task 1: Chart scaffold + common dependency

**Description:** Create `charts/paperless-ngx/` with Chart.yaml (v0.1.0, appVersion `2.20.15`, dependency `common` 5.2.1 from `https://bjw-s-labs.github.io/helm-charts/`), `templates/common.yaml` containing the pre-loader mutations (envFrom injection from `secret.existingSecrets`, `PAPERLESS_REDIS` derived from fullname) and the `bjw-s.common.loader.all` include, and minimal `values.yaml` (images only). Run `helm dependency update` locally for dev rendering. Commit Chart.lock only — the vendored tgz is dev-only and NOT committed (root `.gitignore` already excludes `**/charts/*.tgz`).

**Acceptance criteria:**
- [x] `helm dependency update charts/paperless-ngx` succeeds; Chart.lock generated
- [x] `git status` does not show the vendored tgz
- [x] `helm template paperless-ngx charts/paperless-ngx` renders (even if minimal)

**Verification:**
- [x] `helm dependency update charts/paperless-ngx && helm template paperless-ngx charts/paperless-ngx`

**Dependencies:** None
**Files likely touched:** `charts/paperless-ngx/Chart.yaml`, `charts/paperless-ngx/values.yaml`, `charts/paperless-ngx/templates/common.yaml`, `Chart.lock` (generated)
**Estimated scope:** Small (3 files)

## Task 2: Workload defaults, secret wiring, single-replica guard

**Description:** Fill values.yaml per spec: two controllers — `main` (paperless-ngx 2.20.15, deployment, Recreate, replicas 1, port 8000, env defaults from live manifests, `PAPERLESS_DBUSER`/`PAPERLESS_DBPASS` via native `valueFrom.secretKeyRef` → `paperless-pgsql-conn`, httpGet `/`:8000 probes with generous startup window) and `redis` (redis:7-alpine, deployment, replicas 1). Top-level `secret.existingSecrets` (default `["paperless-secret-key", "paperless-admin", "paperless-socialaccount"]`). Implement envFrom mutation and PAPERLESS_REDIS derivation in common.yaml; replicas guard in templates/guard.yaml using `fail`.

**Acceptance criteria:**
- [x] Render contains: both Deployments with correct images, all env defaults, `envFrom` referencing all three secrets, DB user/pass via `valueFrom`, `PAPERLESS_REDIS=redis://paperless-ngx-redis:6379`, httpGet probes on 8000
- [x] `--set secret.existingSecrets={}` removes envFrom
- [x] `--set controllers.main.replicas=2` makes `helm template` exit non-zero with an explanatory message

**Verification:**
- [x] `helm template` + grep assertions for each criterion; negative test for the replicas guard
- [x] `helm lint charts/paperless-ngx`

**Dependencies:** Task 1
**Files likely touched:** `charts/paperless-ngx/values.yaml`, `charts/paperless-ngx/templates/common.yaml`, `charts/paperless-ngx/templates/guard.yaml`
**Estimated scope:** Medium (3 files)

**CHECKPOINT (after Task 2): render review against SPEC.md "Values design" before proceeding**

## Task 3: Services, persistence, ingress

**Description:** Add `service.main` (controller main, port 8000) and `service.redis` (controller redis, port 6379); `persistence` media (20Gi, `/usr/src/paperless/media`), data (5Gi, `/usr/src/paperless/data`), export (10Gi, `/usr/src/paperless/export`) — RWO, `retain: true`; `ingress.main` scaffold disabled by default.

**Acceptance criteria:**
- [x] Both Services render targeting the correct controllers; PVC names `<fullname>-{media,data,export}` with `helm.sh/resource-policy: keep` and correct sizes/mount paths
- [x] No Ingress by default; ingress overrides render a Traefik-compatible Ingress

**Verification:**
- [ ] `helm template` default + with ingress overrides

**Dependencies:** Task 2
**Files likely touched:** `charts/paperless-ngx/values.yaml`
**Estimated scope:** Small (1 file)

## Task 4: README + full verification pass

**Description:** Write `charts/paperless-ngx/README.md`: purpose, secret contract (three SealedSecrets + Crossplane connection Secret, all created out-of-band — boaboa-iac owns them), ports table, env vars summary, migration notes (fresh-volume cutover, old PVCs survive `Delete=false`, `paperless-oidc` SealedSecret noted as unconsumed), ingress snippet in the hermes style. Run the full verification matrix from the spec's Testing Strategy.

**Acceptance criteria:**
- [x] `helm lint` clean
- [x] All template variants render as expected (defaults / empty secrets / ingress on / alternate release name)
- [x] README contains secret contract, ports, values table; no secret material

**Verification:**
- [ ] `helm lint charts/paperless-ngx`
- [ ] `helm template paperless-ngx charts/paperless-ngx` (+ variants) with grep assertions

**Dependencies:** Task 3
**Files likely touched:** `charts/paperless-ngx/README.md`
**Estimated scope:** Small (1 file)

**CHECKPOINT (after Task 4): all spec success criteria met; hand off to the boaboa-iac initiative for the Argo cutover**

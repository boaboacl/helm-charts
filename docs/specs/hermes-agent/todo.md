# Tasks: hermes-agent Helm Chart

## Task 1: Chart scaffold + common dependency

**Description:** Create `charts/hermes-agent/` with Chart.yaml (v0.1.0, appVersion `v2026.9.24`, dependency `common` 5.2.1 from `https://bjw-s-labs.github.io/helm-charts/`), `templates/common.yaml` containing the `bjw-s.common.loader.all` include, and minimal `values.yaml` (image only). Add the bjw-s helm repo, run `helm dependency update` locally for dev rendering. Commit Chart.lock only — the vendored `charts/hermes-agent/charts/*.tgz` is dev-only and NOT committed (CI's chart-releaser resolves dependencies itself at package time: `DependencyUpdate = true`). Also create root `.gitignore` with the toptal helm template (`**/charts/*.tgz` under a `### Helm ###` header). Pushing to main auto-publishes via the existing release workflow.

**Acceptance criteria:**
- [x] `helm dependency update charts/hermes-agent` succeeds; Chart.lock generated and committed
- [x] Root `.gitignore` present with `**/charts/*.tgz`; `git status` does not show the vendored tgz
- [x] `helm template hermes-agent charts/hermes-agent` renders a Deployment with image `nousresearch/hermes-agent:v2026.9.24`

**Verification:**
- [x] `helm dependency update charts/hermes-agent && helm template hermes-agent charts/hermes-agent`

**Dependencies:** None
**Files likely touched:** `charts/hermes-agent/Chart.yaml`, `charts/hermes-agent/values.yaml`, `charts/hermes-agent/templates/common.yaml`, `Chart.lock` (generated)
**Estimated scope:** Small (3-4 files)

## Task 2: Workload defaults, secret wiring, single-replica guard

**Description:** Fill values.yaml per spec: controller type deployment / strategy Recreate / replicas 1; container `args: ["gateway", "run"]`; env defaults (HERMES_DASHBOARD, HERMES_DASHBOARD_HOST, API_SERVER_ENABLED, API_SERVER_HOST, TZ); tcp probes on 9119 with generous startup; resources 1CPU/1Gi → 2CPU/4Gi; `defaultPodOptions.securityContext` runAsUser/runAsGroup 0; container readOnlyRootFilesystem false; `persistence.data` (RWO, 8Gi, retain, /opt/data); top-level `secret.existingSecret` (default `hermes-agent-env`). Implement envFrom mutation in common.yaml (before loader include) and the replicas guard in templates/guard.yaml using `fail`.

**Acceptance criteria:**
- [x] Render contains: args `["gateway","run"]`, all env defaults, `envFrom` referencing `hermes-agent-env`, runAsUser 0, PVC `data` at /opt/data (retain), resource requests/limits, tcp probes on 9119
- [x] `--set secret.existingSecret=my-secret` changes the envFrom target; `--set secret.existingSecret=""` removes envFrom
- [x] `--set controllers.main.replicas=2` makes `helm template` exit non-zero with a message explaining the SQLite constraint

**Verification:**
- [x] `helm template` + grep assertions for each criterion; negative test for replicas guard
- [x] `helm lint charts/hermes-agent`

**Dependencies:** Task 1
**Files likely touched:** `charts/hermes-agent/values.yaml`, `charts/hermes-agent/templates/common.yaml`, `charts/hermes-agent/templates/guard.yaml`
**Estimated scope:** Medium (3 files)

**CHECKPOINT (after Task 2): render review against SPEC.md "Values Design" before proceeding**

## Task 3: Services and ingress

**Description:** Add `service.main` (port 9119, dashboard) and `service.api` (port 8642, OpenAI-compatible API) to values.yaml; add `ingress.main` scaffold disabled by default (homelab host placeholder in comments).

**Acceptance criteria:**
- [x] Both Services render with correct ports/targetPorts
- [x] No Ingress by default; `--set ingress.main.enabled=true --set ingress.main.hosts[0].host=hermes.example.com` renders an Ingress

**Verification:**
- [x] `helm template` default + with ingress overrides

**Dependencies:** Task 2
**Files likely touched:** `charts/hermes-agent/values.yaml`
**Estimated scope:** Small (1 file)

## Task 4: README + full verification pass

**Description:** Write `charts/hermes-agent/README.md`: purpose, install commands, env-only bootstrap (required vars: one model-provider key, `HERMES_DASHBOARD_BASIC_AUTH_USERNAME/_PASSWORD/_SECRET`; optional: chat platform tokens, `API_SERVER_KEY` ≥ 8 chars), Secret creation example, values table summary, profiles-via-exec and upgrade notes. Then run the full verification matrix: helm lint, template variants (defaults / dashboard off / ingress on / custom existingSecret), `helm template --validate` or install `--dry-run=server` against the live cluster, check default StorageClass exists.

**Acceptance criteria:**
- [x] `helm lint` clean
- [x] All template variants render as expected
- [x] Server-side dry-run accepted by the k0s cluster (validates against v1.34.2)
- [x] README contains required/optional env var tables and Secret creation command; no secret material

**Verification:**
- [x] `helm lint charts/hermes-agent`
- [x] `helm template hermes-agent charts/hermes-agent --validate` (or `helm install --dry-run=server`)
- [x] `kubectl get storageclass` shows a default

**Dependencies:** Task 3
**Files likely touched:** `charts/hermes-agent/README.md`
**Estimated scope:** Small (1 file)

**CHECKPOINT (after Task 4): all spec success criteria except live deploy; review before deploying**

## Task 5: Live deploy (gated on user credentials)

**Description:** User creates the credentials Secret out-of-band, then `helm install` into namespace `hermes`. Verify: pod Running, dashboard serves login over port-forward or ingress, `kubectl exec` → `hermes gateway status` healthy (Manager: s6), delete pod → state survives.

**Acceptance criteria:**
- [x] Pod reaches Running and stays up (no crash loop from dashboard auth gate)
- [x] Dashboard authenticates with basic-auth credentials
- [x] `hermes gateway status` inside container reports s6-managed gateway healthy
- [x] Pod deletion + recreation preserves /opt/data state

**Verification:**
- [x] `kubectl -n hermes get pods -w`, port-forward + curl login page
- [x] `kubectl -n hermes exec deploy/hermes-agent -- hermes gateway status`
- [x] `kubectl -n hermes delete pod <pod>` then re-check sessions dir

**Dependencies:** Task 4 + user-provided Secret
**Files likely touched:** none (deployment only)
**Estimated scope:** Small

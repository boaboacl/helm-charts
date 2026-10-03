# Implementation Plan: hermes-agent Helm Chart

Implements [SPEC.md](SPEC.md). Single capability → single-track plan.

## Overview

New chart `charts/hermes-agent` deploying `nousresearch/hermes-agent:v2026.9.24` (gateway mode + supervised dashboard) via the bjw-s-labs common library v5.2.1. Verified environment: cluster k0s v1.34.2, loader include is `bjw-s.common.loader.all`, v5 values schema confirmed (`controllers.<id>.pod`, `replicas`, env maps, `envFrom[].secretRef.identifier`, probes with `type`/`port`).

## Architecture Decisions

1. **bjw-s common v5.2.1**, loader `bjw-s.common.loader.all` in `templates/common.yaml` (verified against upstream templates/loader/_all.tpl).
2. **Deployment, strategy Recreate, replicas 1.** Single-instance guard implemented as a `fail`-ing template (`templates/guard.yaml`) — values-level replicas > 1 aborts rendering with an explanatory message.
3. **Secret wiring via values mutation:** top-level chart value `secret.existingSecret` (default `hermes-agent-env`, empty string = disabled). `templates/common.yaml` mutates `controllers.main.containers.main.envFrom` from it before including the loader — single source of truth, no duplication with a hardcoded envFrom in values.yaml. (Known-good bjw-s pattern; render assertions will verify.)
4. **Pod security:** `defaultPodOptions.securityContext.runAsUser/runAsGroup: 0`; container `securityContext.readOnlyRootFilesystem: false`. Image boots as root to chown /opt/data, then s6 drops to UID 10000. Entrypoint/command never overridden; `args: ["gateway", "run"]`.
5. **Env defaults:** `HERMES_DASHBOARD=1`, `HERMES_DASHBOARD_HOST=0.0.0.0`, `API_SERVER_ENABLED=true`, `API_SERVER_HOST=0.0.0.0`, `TZ=America/Santiago` (repo convention from cheshirecat).
6. **Probes:** tcp on 9119 (dashboard is supervised and on by default; s6 self-heals the gateway). Generous startup probe (image runs migrations/boot work).
7. **Networking:** `service.main` → 9119, `service.api` → 8642; `ingress.main` present but disabled by default.
8. **Persistence:** PVC `data`, ReadWriteOnce, 8Gi, `retain: true`, mounted at `/opt/data`.

## Task List

(Tracked in `tasks/todo.md`)

### Phase 1: Foundation
- [ ] Task 1: Chart scaffold + common dependency
- [ ] Task 2: Workload defaults, secret wiring, single-replica guard

### Checkpoint: Foundation
- [ ] `helm template` renders complete workload with correct args/env/envFrom/PVC/securityContext
- [ ] replicas=2 fails rendering loudly

### Phase 2: Networking + Docs
- [ ] Task 3: Services and ingress
- [ ] Task 4: README (env-only bootstrap) + full verification pass

### Checkpoint: Complete
- [ ] `helm lint` clean; server-side dry-run accepted by the k0s cluster
- [ ] README documents required/optional env vars
- [ ] Spec success criteria all met (except live-deploy items)

### Phase 3: Live deploy (gated on user-provided credentials)
- [ ] Task 5: Deploy to cluster with real Secret; verify dashboard auth, gateway status, restart persistence

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| v5 values keys drift from assumptions | Med | Schema verified upstream this session; every render assertion checks exact keys |
| envFrom values-mutation pattern breaks | Med | Task 2 asserts envFrom renders from `secret.existingSecret`; fallback = hardcode default identifier in values.yaml |
| Dashboard fails closed without basic-auth env | Med | Task 4 README marks `HERMES_DASHBOARD_BASIC_AUTH_USERNAME/_PASSWORD/_SECRET` as required for default values; Task 5 verifies live |
| s6/PID-1 semantics under K8s | Low | Container gets its own PID namespace by default → dispatcher execs `/init`; confirmed by docs; Task 5 watches first boot |
| Default StorageClass missing/wrong on k0s | Low | Check `kubectl get storageclass` before live deploy; allow `persistence.data.storageClass` override |

## Open Questions

- None blocking. Task 5 requires the user to create the credentials Secret out-of-band.

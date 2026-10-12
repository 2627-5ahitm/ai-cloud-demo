## Why

The DevBox removed the *build* from the laptop, but the *agent* still runs on it: Claude Code lives in
a local terminal, so every session is tied to one machine, dies with the laptop's lid, and cannot be
picked up from a phone. The DevBox's own acceptance test had to be driven from the laptop for exactly
that reason.

The SuperBox moves the agent into the same cluster. It is a second, deliberately small Deployment that
runs the Claude CLI in yolo mode (`--dangerously-skip-permissions`) inside tmux. The user attaches with
`kubectl exec`, logs in once, enables remote control, and from then on drives the work from the Claude
app while the session keeps running in the cluster. The SuperBox does not build anything itself — it
drives one or more DevBoxes through the Kubernetes API.

## What Changes

- New Deployment `superbox`: `debian:trixie-slim`, single replica, `sleep infinity`, `runAsUser: 0`
  plus `IS_SANDBOX=1` (verified: without it the CLI refuses `--dangerously-skip-permissions` as root),
  no Service and no Ingress — its only inbound path is `kubectl exec`.
- New `ServiceAccount superbox` with a narrow namespaced `Role`/`RoleBinding` (`superbox-driver`):
  read pods and logs, `create` on `pods/exec` and `pods/portforward`, read deployments and services,
  and `get`/`update` on exactly one Secret. **No `delete` anywhere, no access to PVCs.** A yolo-mode
  agent must not be able to destroy the namespace it lives in, which the existing `namespace-admin`
  role (bound to ServiceAccount `testc20`) would allow.
- New PVC `superbox-work` (RWO, 10Gi): SuperBox toolchain, `HOME`, and the Claude CLI state under
  `~/.claude` (verified JSON/JSONL only, no SQLite, so NFS is safe).
- New PVC `shared-projects` (**RWX**, 20Gi), mounted at `/shared` by SuperBox *and* DevBox: the agent
  edits project files directly and only runs builds through `kubectl exec`. Replaces per-iteration
  `kubectl cp` round-trips.
- New ConfigMap `superbox-bootstrap`: idempotent installer (same marker-file pattern as the DevBox)
  for tmux, git, jq, ripgrep, curl, tar, Node.js LTS, a `kubectl` client matching server 1.30, and the
  Claude CLI — all into the PVC.
- New helper commands on the SuperBox's `PATH`: `devbox-exec`, `devbox-cp`, `devbox-list` (resolve a
  DevBox by label, then exec/copy) and `superbox-creds` (push/pull/status against the credentials
  Secret).
- New Secret `superbox-claude-creds`, created out-of-band by `superbox-creds push` after an interactive
  `claude login`. It is **never** committed: the manifests reference it optionally, and the bootstrap
  seeds `~/.claude` from it only when the PVC has no credentials yet.
- **Modified DevBox** (requires a pod restart, which kills the demo apps currently running there):
  mount `shared-projects` at `/shared`, and add the labels
  `app.kubernetes.io/name=devbox` / `app.kubernetes.io/instance=<name>` so more than one DevBox can be
  addressed unambiguously.
- `k8s/` is restructured into `k8s/{shared,devbox,superbox}/` with a root `kustomization.yaml`, so the
  documented `kubectl apply -k k8s/` keeps working. `k8s/README.md` and `CLAUDE.md` are updated.
- No breaking change to the DevBox's contract: everything it does today it still does, at the same
  paths.

## Capabilities

### New Capabilities
- `superbox`: a cluster-resident home for the Claude agent — how it is reached and kept alive, how it
  authenticates to Anthropic, what cluster rights it holds, how it discovers and drives DevBoxes, and
  how multiple concurrent sessions are kept.

### Modified Capabilities
- `devbox`: the workspace requirement is **modified** (project sources may also live on a workspace
  shared with the SuperBox, writable from both sides), and a requirement is **added** for a DevBox to
  be enumerable and addressable by instance label. The `devbox` capability is currently only a delta
  inside `add-devbox-deployment` and has not been synced into `openspec/specs/` yet; that sync
  (`add-devbox-deployment` task 6.4) must happen before this change is archived.

## Impact

- **Cluster** (namespace `student-testc20`, context `leocloud`): adds one Deployment, one
  ServiceAccount, one Role, one RoleBinding, one ConfigMap and two PVCs (10Gi + 20Gi, on top of the
  DevBox's existing 20Gi). Requested ~250m CPU / 512Mi, limited to 2 CPU / 4Gi. No ResourceQuota
  exists. The DevBox Deployment is patched and rolled.
- **Disruption**: applying this change restarts the DevBox pod. The Quarkus (`:8080`) and Express
  (`:3000`) processes started for the DevBox acceptance test are `nohup`'d and do not survive a
  restart; they must be started again per `k8s/README.md`.
- **Security posture**: a long-lived OAuth credential for the user's Claude account comes to rest in
  the namespace, in a Secret and on an NFS-backed PVC. Anyone who can `exec` into the namespace can
  read it. The SuperBox's own cluster rights are deliberately narrower than the user's.
- **Verified constraints** this change depends on: SA `default` has no rights (403), only `testc20` is
  bound to `namespace-admin`; the StorageClass is `nfs-subdir-external-provisioner`, so RWX is
  available but `accessModes` are immutable per PVC (hence a *new* PVC, not a change to
  `devbox-work`); PVC roots are mode 777 and `flock` works over NFS; egress to `api.anthropic.com`,
  `registry.npmjs.org`, `github.com` and `dl.k8s.io` is open with no proxy.
- **Dependencies pulled at runtime**: deb.debian.org, nodejs.org, dl.k8s.io, registry.npmjs.org
  (`@anthropic-ai/claude-code`). Cold start is expected in the 2–3 minute range, far below the
  DevBox's 7–8.
- **Repo**: `k8s/*.yaml` and `k8s/bootstrap.sh` move under `k8s/devbox/`; new `k8s/superbox/` and
  `k8s/shared/`. Commands in `CLAUDE.md` that name `k8s/deployment.yaml` directly need updating.

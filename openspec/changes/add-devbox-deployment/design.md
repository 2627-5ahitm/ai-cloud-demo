## Context

See `proposal.md` — Why for motivation, and `specs/devbox/spec.md` for the behaviour contract.

Constraints discovered in the target cluster (namespace `student-testc20`, context `leocloud`):

- Kubernetes server 1.30 (client 1.37).
- One StorageClass, `default`, backed by `nfs-subdir-external-provisioner`, `ALLOWVOLUMEEXPANSION=true`.
- PodSecurity `enforce=baseline`, `warn=baseline` on the namespace: `runAsUser: 0` is allowed, apt
  works, privileged containers and host mounts are not allowed.
- No `ResourceQuota`, no `LimitRange`.
- The kubeconfig already selects the namespace; the RBAC subject may create deployments, pods, PVCs,
  ConfigMaps, Services and `pods/exec`.
- Whether a container image can be built and pushed anywhere was unknown, so the design had to work
  without that.

## Goals / Non-Goals

**Goals:**

- Reach a usable DevBox with nothing but `kubectl apply` against the existing context.
- Keep the second and later pod starts fast, even though the container filesystem is ephemeral.
- Make the environment work for *non-interactive* `kubectl exec`, which is how an agent calls it.
- Keep failure of a single provisioning step debuggable instead of fatal.

**Non-Goals:**

- Building container images inside the DevBox (PodSecurity `baseline` rules that out).
- Multi-user or multi-replica operation: one pod, one RWO volume, one user.
- Exposing anything through Ingress, or any network path other than `kubectl`.
- Keeping applications started inside the DevBox running across a pod restart.
- Pinning exact tool versions reproducibly (see Risks).

## Decisions

**Provision at runtime into a PVC instead of building an image.**
A custom image (Debian + JDK + Node + Playwright ≈ 2 GB) would need a build tool on the laptop and a
registry the user may not have; the laptop upload is also the slowest part of that loop, which
contradicts the point of the DevBox. Instead the pod runs public `debian:trixie-slim` and a bootstrap
script installs the toolchain into `/work/tools` on the PVC. Alternatives considered: (a) a prebuilt
public image such as `mcr.microsoft.com/playwright` — rejected, it is Ubuntu-based and the brief asks
for Debian, and it still lacks JDK/Quarkus/httpyac; (b) an `initContainer` doing the install —
rejected, it delays pod readiness for the full install and gains nothing over running in the
container, which is already ephemeral. The trade-off is a ~7–8 minute cold start and no image digest
to pin.

**Tarball installs, not apt, for the language toolchains.**
Node, the JDK, Maven and the Quarkus CLI are unpacked into the PVC, so a pod restart finds them
already there. apt packages would land on the ephemeral container filesystem and be reinstalled every
time. Only what must come from apt (base utilities, Playwright's shared libraries) is installed with
apt on each start, with `/var/cache/apt/archives` symlinked to the PVC so the `.deb` files are reused.

**Resolve tool versions at install time instead of pinning them.**
The script asks nodejs.org's `index.json`, Adoptium's `latest` API, the Apache mirror listing and the
GitHub "latest release" API. This avoids shipping version numbers that rot, at the price of
non-reproducible installs — acceptable for a dev environment, and the marker files mean a given PVC
keeps whatever it got.

**Marker files for idempotency.**
Each step writes `/work/tools/.markers/<step>` on success and is skipped when the marker exists. This
is simpler than version comparisons and makes a forced reinstall a plain `rm -rf /work/tools`. A step
that fails leaves no marker and is retried on the next start.

**Bootstrap runs in the background; the container command is `sleep infinity`.**
The spec requires the pod to be exec-able and to survive failures. Running the script in the
foreground would either delay exec access or kill the pod when the script exits. Instead the container
starts the script in the background and then `exec sleep infinity`, and the script never propagates a
failure — it logs `!!! FAILED: <step>` to `/work/bootstrap.log` and continues.

**Readiness probe on a marker file, not on a port.**
There is no server to probe. `test -f /work/.devbox-ready` turns
`kubectl wait --for=condition=ready` into a real "toolchain installed" signal.
`failureThreshold: 60 × periodSeconds: 15` allows ~15 minutes of provisioning before the probe gives
up.

**Tool environment in the pod spec, not in `/root/.bashrc`.**
`kubectl exec ... -- <cmd>` does not run a shell profile, and `/root` is ephemeral anyway. `PATH`,
`JAVA_HOME`, `NPM_CONFIG_PREFIX`, `NPM_CONFIG_CACHE`, `PLAYWRIGHT_BROWSERS_PATH` and `MAVEN_ARGS` are
therefore environment variables of the container, pointing into the PVC. `env.sh` plus a `.bashrc`
line exist only as a convenience for interactive shells.

**Bootstrap script shipped as a ConfigMap via `kustomize` `configMapGenerator`.**
`kubectl apply -k` then updates script and Deployment in one command, and the script stays a normal
executable file in the repo instead of embedded YAML. `disableNameSuffixHash: true` keeps the
ConfigMap name stable so the Deployment can reference it by plain name; the cost is that editing the
script does not by itself roll the pod, so a `kubectl rollout restart` is needed to pick it up.

**`strategy: Recreate`.**
The PVC is `ReadWriteOnce`; a rolling update would deadlock with the new pod waiting for a volume the
old pod still holds.

**Caches on the PVC.**
Maven's local repository is redirected to `/work/.m2/repository` (via `MAVEN_ARGS` and a generated
`settings.xml`), npm's global prefix and cache and Playwright's browser directory likewise. This is
what makes a restart cheap and satisfies the "dependencies are not downloaded twice" scenario.

**No namespace anywhere in the manifests.**
Neither the resources nor `kustomization.yaml` set a namespace, so `kubectl apply -k k8s/` follows the
active context — which is what the spec requires and what keeps the manifests reusable for another
student's namespace.

## Risks / Trade-offs

- **Unpinned versions can shift or a download host can change its layout** → every step is isolated and
  non-fatal, the failure is visible in `/work/bootstrap.log`, and an existing PVC is unaffected because
  markers skip completed steps. If reproducibility becomes important, move to pinned versions or a
  built image.
- **Cold start ~7–8 minutes** → readiness probe makes the wait explicit instead of surprising; the PVC
  makes it a one-time cost.
- **apt layer is reinstalled on every pod start** (~1 minute) → `.deb` cache on the PVC; accepted as
  the price of not maintaining an image.
- **NFS-backed PVC**: mediocre IOPS for large `node_modules` trees, no cross-volume hard links → fine
  for course-sized projects; a build that is IO-bound will feel it.
- **PodSecurity `baseline` forbids privileged containers** → no Docker-in-DevBox; container images must
  be built elsewhere. Documented in `k8s/README.md`.
- **Single `ReadWriteOnce` volume and a single replica** → no concurrent DevBox pods; a second pod in
  the same namespace needs its own PVC.
- **Applications started with `nohup ... & disown` die on pod restart** → documented restart commands
  in `k8s/README.md`; a supervisor was deliberately not added, since the agent starts apps on demand.
- **Bootstrap script size** → ConfigMaps cap at ~1 MiB; the script is a few KB, so headroom is ample,
  but generated project files must never be moved into the ConfigMap.

## Migration Plan

1. `kubectl apply -k k8s/` in the target namespace (first deployment: nothing to migrate).
2. `kubectl wait --for=condition=ready pod -l app=devbox --timeout=20m`, watching
   `kubectl exec deploy/devbox -- tail -f /work/bootstrap.log`.
3. Rollback: `kubectl delete -k k8s/` removes Deployment, Service and ConfigMap. The PVC is deleted
   only by an explicit `kubectl delete pvc devbox-work`, which also discards all projects and caches —
   so a redeploy against the same PVC is the cheap way back.
4. Changing the bootstrap script: `kubectl apply -k k8s/` followed by `kubectl rollout restart
   deploy/devbox` (the ConfigMap name is stable, so the pod does not roll on its own). To force a full
   reinstall, `kubectl exec deploy/devbox -- rm -rf /work/tools` before the restart.

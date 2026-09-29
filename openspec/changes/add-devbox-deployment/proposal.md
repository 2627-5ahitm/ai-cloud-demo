## Why

Building, testing and deploying projects on the user's laptop is slow and couples the work to one
machine. The HTL Leonding cloud (https://cloud.htl-leonding.ac.at, Kubernetes) can host a long-lived
container that holds the whole toolchain instead, so an AI agent can drive build/test/deploy remotely
through `kubectl exec` and `kubectl cp`.

This change records the DevBox that now exists under `k8s/`: the manifests, the PVC-based toolchain
bootstrap, and the acceptance test from the brief (Quarkus demo + httpyac, Node frontend against the
Quarkus backend + httpyac + Playwright). It is written retroactively — the implementation is already
deployed and verified in namespace `student-testc20` — so that the behaviour is captured as specs
rather than living only in the manifests.

## What Changes

- New `k8s/` deployment, applied with `kubectl apply -k k8s/`:
  - `deployment.yaml` — one replica, `debian:trixie-slim` (Debian 13, latest stable), `sleep infinity`
    as the workload, `strategy: Recreate`, `runAsUser: 0`, readiness probe on `/work/.devbox-ready`,
    tool environment (`PATH`, `JAVA_HOME`, `NPM_CONFIG_PREFIX`, `PLAYWRIGHT_BROWSERS_PATH`,
    `MAVEN_ARGS`) set in the pod spec.
  - `pvc.yaml` — `devbox-work`, 20Gi, StorageClass `default` (NFS), mounted at `/work`.
  - `bootstrap.sh` + `kustomization.yaml` (`configMapGenerator`) — idempotent toolchain install into
    `/work/tools`: Node.js LTS, Eclipse Temurin JDK 21, Maven 3.9.x, Quarkus CLI, httpyac,
    Playwright + Chromium, plus apt base packages (curl, git, jq, unzip, build-essential, …).
  - `service.yaml` — ClusterIP `devbox`, ports 8080 (Quarkus) and 3000 (Node).
- No container image build and no registry: the pod runs a public Debian image and installs the
  toolchain into the PVC on first start.
- Caches that survive pod restarts on the PVC: toolchains, Maven repo (`/work/.m2/repository`), npm
  cache, Playwright browsers, apt `.deb` archives.
- Documentation: `k8s/README.md` (layout, daily commands, reset, gotchas) and an updated `CLAUDE.md`
  (cluster facts, commands, paths).
- Acceptance test performed inside the DevBox and left in place under `/work/projects`:
  `quarkus-demo` (5 JUnit tests via `mvn package`, 6 httpyac requests) and `node-frontend`
  (6 httpyac requests, 1 Playwright/Chromium UI test).
- No breaking changes — this is the project's first deployable artifact.

## Capabilities

### New Capabilities
- `devbox`: a remote Kubernetes development environment that an agent drives exclusively through
  `kubectl exec` / `kubectl cp`: pod lifecycle, the toolchain it must provide, where state is
  persisted, and how readiness is signalled.

### Modified Capabilities

<!-- none: this is the first capability in openspec/specs/ -->

## Impact

- **Cluster** (namespace `student-testc20`, context `leocloud`): adds a Deployment, a Service, a
  ConfigMap (`devbox-bootstrap`) and a 20Gi PVC. Roughly 0.5 CPU / 2Gi requested, 4 CPU / 6Gi limit.
  No ResourceQuota exists in the namespace.
- **Constraints discovered**: PodSecurity is `baseline`, so `runAsUser: 0` and apt work, but no
  privileged containers — building container images inside the DevBox is not possible. The PVC is
  NFS-backed, so large `node_modules` trees are slower than on local disk.
- **Repo**: new `k8s/` directory; `CLAUDE.md` gains the deployment section and the concrete commands.
- **Dependencies pulled at runtime** (not vendored): deb.debian.org, nodejs.org, api.adoptium.net,
  dlcdn.apache.org, api.github.com (Quarkus CLI release), registry.npmjs.org, Playwright CDN.
  Bootstrap needs egress to those hosts.
- **Cost of a cold start**: ~7–8 minutes on an empty PVC; later pod starts only redo the apt layer.

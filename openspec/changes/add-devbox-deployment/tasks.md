<!-- This change was written retroactively: the DevBox is already deployed and verified in namespace
     student-testc20. Tasks marked [x] were carried out before this planning artifact existed; the
     verification stated in each one is the check that was actually run. Unchecked tasks are genuine
     leftovers. -->

## 1. Cluster reconnaissance

- [x] 1.1 Determine context, namespace and server version and verify `kubectl config current-context`
      reports `leocloud` with namespace `student-testc20` (server 1.30)
- [x] 1.2 List StorageClasses and verify a default one exists (`default`, nfs-subdir provisioner,
      volume expansion allowed)
- [x] 1.3 Check `ResourceQuota` / `LimitRange` and verify none constrain the namespace
- [x] 1.4 Check the namespace's PodSecurity labels and verify the level is `baseline`, so `runAsUser: 0`
      and apt are permitted and privileged containers are not
- [x] 1.5 Check RBAC with `kubectl auth can-i` and verify `create` is allowed for deployments, pvc,
      configmaps and `pods/exec`

## 2. Manifests

- [x] 2.1 Write `k8s/pvc.yaml` (`devbox-work`, 20Gi, RWO, default StorageClass) and verify the PVC
      reaches `Bound`
- [x] 2.2 Write `k8s/deployment.yaml` — `debian:trixie-slim`, `sleep infinity`, `strategy: Recreate`,
      `runAsUser: 0`, PVC at `/work`, ConfigMap at `/opt/devbox`, tool env vars in the pod spec — and
      verify the pod reaches `Running` with 0 restarts
- [x] 2.3 Add the readiness probe on `/work/.devbox-ready` and verify the pod is `0/1` while
      provisioning and `1/1` afterwards
- [x] 2.4 Write `k8s/service.yaml` (ClusterIP, ports 8080 and 3000) and verify `kubectl get svc devbox`
      shows both ports
- [x] 2.5 Write `k8s/kustomization.yaml` with a `configMapGenerator` for `bootstrap.sh`,
      `disableNameSuffixHash: true` and no namespace, and verify `kubectl apply -k k8s/` creates all
      four resources in the context's namespace

## 3. Toolchain bootstrap

- [x] 3.1 Write the idempotent `k8s/bootstrap.sh` skeleton (marker files under
      `/work/tools/.markers`, log to `/work/bootstrap.log`, per-step failure isolation) and verify a
      failing step logs `!!! FAILED` without aborting the run
- [x] 3.2 Install the apt base packages with the `.deb` cache redirected to the PVC and verify
      `curl`, `git`, `jq` and `unzip` are executable
- [x] 3.3 Install Node.js LTS from the official tarball into `/work/tools/node` and verify
      `node --version` and `npm --version`
- [x] 3.4 Install Eclipse Temurin JDK 21 from the Adoptium API into `/work/tools/jdk` and verify
      `java -version`
- [x] 3.5 Install Apache Maven 3.9.x into `/work/tools/maven`, point the local repository at
      `/work/.m2/repository`, and verify `mvn -v`
- [x] 3.6 Install the Quarkus CLI from the latest GitHub release into `/work/tools/quarkus` and verify
      `quarkus --version`
- [x] 3.7 Install httpyac globally with the npm prefix on the PVC and verify `httpyac --version`
- [x] 3.8 Install Playwright plus Chromium with `PLAYWRIGHT_BROWSERS_PATH` on the PVC, including the
      manual shared-library fallback, and verify `playwright --version` and that headless Chromium
      launches
- [x] 3.9 Write `/work/tools/env.sh` and the readiness marker and verify a non-interactive
      `kubectl exec deploy/devbox -- mvn -v` finds the toolchain without sourcing anything

## 4. Acceptance test inside the DevBox

- [x] 4.1 Create a Quarkus demo app (`rest`, `rest-jackson`) with REST endpoints for greeting and
      items, build it with `mvn -B clean package`, and verify 5 unit tests pass with 0 failures
- [x] 4.2 Start the Quarkus app in the background on port 8080 and verify
      `curl http://localhost:8080/api/greeting?name=Test` returns the expected JSON
- [x] 4.3 Write and run an httpyac suite against the Quarkus endpoints and verify all 6 requests and
      their assertions pass
- [x] 4.4 Create an Express app on port 3000 that calls the Quarkus backend via `fetch` (backend URL
      from `BACKEND_URL`), including a 502 path for backend failure, and verify `/health` answers
- [x] 4.5 Write and run an httpyac suite against the Node endpoints and verify all 6 requests pass,
      including that the greeting and item data came through from the backend
- [x] 4.6 Write and run a Playwright/Chromium test against the Node page and verify the heading and at
      least two rendered items

## 5. Documentation

- [x] 5.1 Write `k8s/README.md` (contents, build approach, PVC layout, deploy/daily-use/reset commands)
      and verify the commands in it run as written
- [x] 5.2 Record the discovered gotchas in `k8s/README.md` (httpyac assertion parsing, local
      `@playwright/test` install, NFS limits, no privileged containers) and verify each claim against
      the behaviour actually observed
- [x] 5.3 Update `CLAUDE.md` with the deployment layout, cluster facts, verified tool versions and the
      concrete commands, and verify it no longer describes the repo as having no manifests

## 6. Leftovers

- [x] 6.1 Put the project under version control (`git init`, initial commit of `k8s/`, `CLAUDE.md`,
      `openspec/`) and verify `git log` shows the commit and `git status` is clean
- [x] 6.2 Add a `.gitignore` that keeps local scratch output out of the repo and verify
      `git status --porcelain` stays empty after a build/test run
- [ ] 6.3 Fill in `openspec/config.yaml` with the now-decided tech stack and conventions and verify
      `openspec instructions proposal --change <name> --json` shows the context
- [ ] 6.4 Sync this change's delta spec into `openspec/specs/` with `/opsx:sync` and verify
      `openspec validate --strict` passes

# DevBox — remote build/test environment on leocloud

A single long-lived pod in your namespace (`student-testc20`) that holds the
whole toolchain. All interaction goes through `kubectl exec` / `kubectl cp` —
no SSH, no ingress.

## What is inside

| Area | What |
|------|------|
| OS | `debian:trixie-slim` (Debian 13, latest stable) |
| JavaScript | Node.js LTS + npm (tarball install under `/work/tools/node`) |
| Java | Eclipse Temurin JDK 21, Apache Maven 3.9.x, Quarkus CLI |
| Tools | Playwright (+ Chromium), httpyac, curl, git, jq, build-essential |

## How it is built

No container registry is involved. The pod runs the public `debian:trixie-slim`
image and a bootstrap script (mounted from the `devbox-bootstrap` ConfigMap)
installs the toolchain into the PVC at `/work/tools` on first start.

* The install is **idempotent** — marker files in `/work/tools/.markers` make a
  restart skip everything already present.
* apt packages live on the ephemeral container filesystem and are reinstalled on
  every pod start; the `.deb` cache sits on the PVC (`/work/cache/apt`) so that
  is fast.
* Toolchains, the Maven repo (`/work/.m2/repository`), the npm cache and the
  Playwright browsers all live on the PVC and survive restarts.

## Layout on the PVC (`/work`, 20 Gi)

```
/work/projects          working directory for projects (container workingDir)
/work/tools             node, jdk, maven, quarkus, npm-global, ms-playwright
/work/tools/env.sh      exports for interactive shells
/work/.m2/repository    Maven local repo (cached across restarts)
/work/bootstrap.log     bootstrap output
/work/.devbox-ready     created when bootstrap finished (readiness probe)
```

`PATH`, `JAVA_HOME`, `NPM_CONFIG_PREFIX`, `PLAYWRIGHT_BROWSERS_PATH` and
`MAVEN_ARGS` are set in the pod spec, so a non-interactive
`kubectl exec deploy/devbox -- mvn -v` finds everything without sourcing
anything.

## Deploy / redeploy

```bash
kubectl apply -k k8s/                    # create or update everything
kubectl wait --for=condition=ready pod -l app=devbox --timeout=20m
kubectl logs deploy/devbox               # only the sleep; real log is below
kubectl exec deploy/devbox -- tail -f /work/bootstrap.log
```

First start takes roughly 5–10 minutes (downloads). Later starts are fast,
because the PVC already holds the toolchains.

## Daily use

```bash
# one-off command
kubectl exec deploy/devbox -- bash -lc 'node --version && java -version && mvn -v'

# interactive shell
kubectl exec -it deploy/devbox -- bash -l

# copy code in / results out
kubectl cp ./myapp   "$(kubectl get pod -l app=devbox -o name | cut -d/ -f2)":/work/projects/myapp
kubectl cp "$(kubectl get pod -l app=devbox -o name | cut -d/ -f2)":/work/projects/myapp/target ./target
```

Ports 8080 (Quarkus) and 3000 (Node) are exposed on the `devbox` Service for
in-cluster access; for local access use
`kubectl port-forward deploy/devbox 8080:8080`.

## Reset

```bash
kubectl exec deploy/devbox -- rm -rf /work/tools        # force full reinstall
kubectl rollout restart deploy/devbox
```

Deleting the PVC (`kubectl delete pvc devbox-work`) throws away all projects
and caches as well.

## Demo apps (acceptance test from the brief)

Both live on the PVC and were built and tested inside the DevBox:

| Path | What | Tests |
|------|------|-------|
| `/work/projects/quarkus-demo` | Quarkus 3.39 REST app on :8080 (`/hello`, `/api/greeting`, `GET+POST /api/items`) | 5 JUnit/REST-assured tests via `mvn package`; 6 httpyac requests in `tests/api.http` |
| `/work/projects/node-frontend` | Express app on :3000 that calls the Quarkus backend (`BACKEND_URL`, default `http://localhost:8080`) plus an HTML page | 6 httpyac requests in `tests/api.http`; Playwright/Chromium smoke test `tests/ui.spec.js` |

Restart them after a pod rollout:

```bash
kubectl exec deploy/devbox -- bash -lc 'cd /work/projects/quarkus-demo && nohup java -jar target/quarkus-app/quarkus-run.jar > app.log 2>&1 & disown'
kubectl exec deploy/devbox -- bash -lc 'cd /work/projects/node-frontend && nohup node server.js > app.log 2>&1 & disown'
```

## Gotchas

* **httpyac assertions** (`?? js <expr>`, verified on httpyac 6.16.7):
  * Do *not* quote the expected value when the expression contains a comparison operator — httpyac
    splits on the first operator and treats the rest as a literal string, so `== "Hello, World!"`
    compares against a value that still has the quotes and fails. Write
    `?? js response.parsedBody.message == Hello, World!`.
  * For the same reason the right-hand side is never evaluated as JS: `?? js a.count == a.items.length`
    compares against the literal text. Fold it into one expression instead, e.g.
    `?? js [a.count].includes(a.items.length) == true`.
  * A boolean-only expression with no operator is silently swallowed into the request body instead of
    being asserted. Always append `== true`: `?? js Array.isArray(response.parsedBody) == true`.
  * `test` is a reserved request-block name (`### test` is rejected) — use a descriptive name.
* **Playwright test runner**: `@playwright/test` is installed globally, but Node's ESM resolver cannot
  see a global package from a project. Install it locally per project with
  `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-save @playwright/test@<version>` — the browsers
  from `PLAYWRIGHT_BROWSERS_PATH=/work/tools/ms-playwright` are reused, nothing is re-downloaded.
* **Background processes**: apps started with `nohup ... & disown` inside the pod die when the pod
  restarts (only `/work` survives). Restart them after a rollout.
* **NFS-backed PVC**: no hard links across the volume boundary and mediocre IOPS for huge
  `node_modules` trees. Works, but a big `npm ci` is slower than on a local disk.
* **PodSecurity baseline**: no privileged containers, no host mounts. Docker-in-DevBox is therefore not
  possible; build container images elsewhere.

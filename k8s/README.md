# DevBox — remote build/test environment on LeoCloud

A single long-lived pod in your LeoCloud namespace (`student-t-stuetz`) that holds the
whole toolchain. All interaction goes through `kubectl exec` / `kubectl cp` —
no SSH, no ingress.

## What is inside

| Area | What |
|------|------|
| OS | `debian:trixie-slim` (Debian 13, latest stable) |
| JavaScript | Node.js 24 LTS + npm 11 |
| Java | Eclipse Temurin JDK 21, Apache Maven 3.9.16, Quarkus CLI 3.39.5 |
| Tools | Playwright 1.63 (+ Chromium), httpyac 6.16.7, curl, git, jq, build-essential |

## How it is built

The toolchain is baked into an image built from `../image/Dockerfile` and pushed to
`ghcr.io/htl-leonding/devbox`. LeoCloud requires this: workloads run from an image built
from the project, and a PVC may request at most **2Gi**, which is too small to hold the
toolchain.

```bash
TAG=$(date +%F).1      # new tag for every build
docker buildx build --platform linux/amd64 -t ghcr.io/htl-leonding/devbox:$TAG --push image/
# then set images[0].newTag in k8s/kustomization.yaml to $TAG and apply
```

The image is `linux/amd64` (every LeoCloud node is amd64). Versions are pinned as
`ARG`s in the Dockerfile; Node and the JDK take the newest release of their LTS major at
build time.

## Layout

```
/opt/tools               node, jdk, maven, quarkus, npm-global, ms-playwright  (image)
/work                    PVC devbox-work, 2Gi, survives restarts
/work/projects           working directory for projects (container workingDir)
/work/.m2/repository     Maven local repo (set in /opt/tools/maven/conf/settings.xml)
/work/.npm               npm cache
/work/.devbox-ready      created at start (readiness probe)
```

`PATH`, `JAVA_HOME`, `M2_HOME`, `NPM_CONFIG_PREFIX`, `NPM_CONFIG_CACHE` and
`PLAYWRIGHT_BROWSERS_PATH` are `ENV` in the image, so a non-interactive
`kubectl exec deploy/devbox -- mvn -v` finds everything without sourcing anything.

## Disk limits (LeoCloud)

* **PVC**: at most 2Gi, cannot be enlarged beyond. Keep projects lean; delete `target/`
  and `node_modules` of projects you no longer need.
* **Container file system** (`ephemeral-storage`, everything outside `/work`: `/tmp`,
  logs, global `npm install -g`): the Deployment requests 500Mi and limits 4Gi. Max per
  container is 10Gi, 20Gi for all pods of the namespace together. Going over the limit
  evicts the pod.

## Deploy / redeploy

```bash
kubectl config current-context           # must print leocloud
kubectl apply -k k8s/
kubectl rollout status deploy/devbox
```

The pod is ready as soon as the image is pulled (a few minutes on a fresh node, seconds
afterwards).

## Daily use

```bash
# one-off command
kubectl exec deploy/devbox -- bash -c 'node --version && java -version && mvn -v'

# interactive shell
kubectl exec -it deploy/devbox -- bash

# copy code in / results out
kubectl cp ./myapp   "$(kubectl get pod -l app=devbox -o name | cut -d/ -f2)":/work/projects/myapp
kubectl cp "$(kubectl get pod -l app=devbox -o name | cut -d/ -f2)":/work/projects/myapp/target ./target
```

Ports 8080 (Quarkus) and 3000 (Node) are exposed on the `devbox` Service for
in-cluster access; for local access use
`kubectl port-forward deploy/devbox 8080:8080`.

## Reset

```bash
kubectl rollout restart deploy/devbox    # fresh container FS, /work stays
```

Deleting the PVC (`kubectl delete pvc devbox-work`) destroys all projects and caches at
once and for good — nobody can bring them back. Copy out what you need first.

## Demo apps (acceptance test from the brief)

Both live on the PVC and were built and tested inside the DevBox:

| Path | What | Tests |
|------|------|-------|
| `/work/projects/quarkus-demo` | Quarkus 3.39 REST app on :8080 (`/hello`, `/api/greeting`, `GET+POST /api/items`) | 6 JUnit/REST-assured tests via `mvn package`; 6 httpyac requests in `tests/api.http` |
| `/work/projects/node-frontend` | Express app on :3000 that calls the Quarkus backend (`BACKEND_URL`, default `http://localhost:8080`) plus an HTML page | 7 httpyac requests in `tests/api.http`; 1 Playwright/Chromium test `tests/ui.spec.js`; 502 on backend failure |

Restart them after a pod rollout:

```bash
kubectl exec deploy/devbox -- bash -c 'cd /work/projects/quarkus-demo && nohup java -jar target/quarkus-app/quarkus-run.jar > app.log 2>&1 & disown'
kubectl exec deploy/devbox -- bash -c 'cd /work/projects/node-frontend && nohup node server.js > app.log 2>&1 & disown'
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
  `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-save @playwright/test@1.63.0` — the browsers
  from `PLAYWRIGHT_BROWSERS_PATH=/opt/tools/ms-playwright` are reused, nothing is re-downloaded.
* **Background processes**: apps started with `nohup ... & disown` inside the pod die when the pod
  restarts (only `/work` survives). Restart them after a rollout.
* **NFS-backed PVC**: mediocre IOPS for huge `node_modules` trees. Works, but a big `npm ci` is
  slower than on a local disk. `df` shows the whole NFS share, not the 2Gi claim.
* **PodSecurity baseline**: no privileged containers, no host mounts. Docker-in-DevBox is therefore not
  possible; build container images on your machine and push to ghcr.io.

# Continuation: deploy the DevBox into a permanent namespace

Paste this whole file as the first prompt of a fresh Claude Code session in
`/Users/stuetz/work/2627-5ahitm-itp/ai-cloud-demo`.

---

## Situation

The DevBox from the brief (`prompts/chat.md`) was built and verified yesterday (2026-09-29) in the
**scratch namespace `student-testc20`**, which was deleted that night. Everything in the cluster is
gone: Deployment, Service, ConfigMap, the 20Gi PVC and the two demo apps that lived on it.

What survived is in this git repo (branch `main`, commits `a729f08`, `b942592`):

```
k8s/pvc.yaml            devbox-work, 20Gi, RWO, no storageClassName (uses the default SC)
k8s/deployment.yaml     debian:trixie-slim, sleep infinity, Recreate, runAsUser 0,
                        readiness probe on /work/.devbox-ready, tool env in the pod spec
k8s/service.yaml        ClusterIP devbox, ports 8080 (Quarkus) + 3000 (Node)
k8s/bootstrap.sh        idempotent toolchain install into the PVC
k8s/kustomization.yaml  configMapGenerator for bootstrap.sh, disableNameSuffixHash, no namespace
k8s/README.md           layout, daily commands, reset, gotchas
CLAUDE.md               cluster facts + concrete commands
openspec/changes/add-devbox-deployment/   proposal, specs/devbox/spec.md, design, tasks
```

The manifests deliberately contain **no namespace**, so they follow the active kubeconfig context.

## Your task

Deploy the DevBox into the user's **new permanent namespace** and re-run the acceptance test from the
brief. Then update the docs with whatever differs from the scratch namespace.

Work in this order:

### 1. Recon the new namespace first — do not trust yesterday's facts

The values below were true for `student-testc20` and may all differ. Verify each one and tell the user
what changed:

```bash
kubectl config current-context
kubectl config view --minify -o jsonpath='{.contexts[0].context.namespace}'; echo
kubectl version -o json | grep gitVersion
kubectl get sc                      # is there a DEFAULT StorageClass? what is it backed by?
kubectl get resourcequota,limitrange -o yaml
kubectl get ns "$NS" -o jsonpath='{.metadata.labels}'; echo   # pod-security.kubernetes.io/*
kubectl get role,rolebinding -o wide
kubectl get sa
kubectl auth can-i create deployments; kubectl auth can-i create pvc
kubectl auth can-i create configmaps; kubectl auth can-i create pods/exec
kubectl get all,pvc,configmap       # name collisions from anything already deployed there
```

Yesterday's values, for comparison only:

| Fact | Scratch namespace `student-testc20` |
|------|-------------------------------------|
| Server / client | k8s 1.30 server, 1.37 client |
| StorageClass | `default`, `nfs-subdir-external-provisioner`, is the cluster default, expansion allowed |
| PodSecurity | `enforce=baseline`, `warn=baseline` |
| Quota / LimitRange | none |
| RBAC | Role `namespace-admin` (verbs `*`) bound **only** to SA `testc20`; SA `default` unbound |
| Node observed | `kong` |
| Egress | open; npm, GitHub, deb.debian.org, Adoptium, dlcdn.apache.org, Playwright CDN, api.anthropic.com all reachable, no proxy, CoreDNS 10.96.0.10 |

**Decision points that depend on the recon — handle them, don't ignore them:**

* **No default StorageClass** → add `storageClassName: <name>` to `k8s/pvc.yaml`.
* **A `ResourceQuota` or `LimitRange` exists** → `k8s/deployment.yaml` requests 500m/2Gi and limits
  4 CPU/6Gi. Fit it to the quota (the Quarkus build wants ~2Gi to be comfortable) and say what you
  changed. A quota on `persistentvolumeclaims` or `requests.storage` may force the PVC below 20Gi;
  ~12Gi is enough for the toolchain plus the demo apps.
* **PodSecurity `restricted` instead of `baseline`** → this is a real blocker, not a tweak. The pod
  runs as root and the bootstrap uses `apt-get` (Playwright's Chromium needs system libraries).
  Under `restricted` (`runAsNonRoot`, dropped capabilities, `seccompProfile: RuntimeDefault`) that
  approach does not work. Do **not** silently degrade the DevBox: deploy everything that does work,
  then stop and tell the user the options — (a) ask the admin for `baseline` on this namespace,
  (b) build a prebuilt image that already contains the toolchain and push it to a registry (needs a
  registry + credentials, so ask first), (c) drop Playwright/Chromium and keep the rest. Let the user
  choose.
* **The namespace's SA situation differs** → nothing in the DevBox itself needs a ServiceAccount, so
  this only matters if a second pod (see "superbox" below) is supposed to drive it.

### 2. Deploy

```bash
kubectl apply -k k8s/
kubectl get pods,pvc -o wide
kubectl exec deploy/devbox -- tail -f /work/bootstrap.log     # watch progress
kubectl wait --for=condition=ready pod -l app=devbox --timeout=20m
```

The pod is exec-able within seconds; readiness arrives only when the toolchain is installed. A cold
start on an empty PVC took **7m14s** yesterday. The bootstrap never fails the pod: a broken step logs
`!!! FAILED: <step>` to `/work/bootstrap.log` and the rest continues — so read that log rather than
assuming success.

Then confirm the toolchain:

```bash
kubectl exec deploy/devbox -- bash -lc 'node --version; npm --version; java -version; mvn -v | head -1; quarkus --version; httpyac --version; playwright --version; curl --version | head -1; cat /etc/os-release | head -2'
```

Versions installed yesterday (resolved at install time, so newer ones are fine — just report them):
Node 24.21.0, npm 11.19.0, Temurin JDK 21.0.12.1 LTS, Maven 3.9.16, Quarkus CLI 3.39.5,
httpyac 6.16.7, Playwright 1.63.0 + Chromium, curl 8.14.1, Debian 13 (trixie).

### 3. Re-run the acceptance test from the brief

The demo apps were on the deleted PVC, so they must be created again **inside** the DevBox (nothing
is committed to this repo — they are throwaway verification artifacts, and that is intentional).
The brief asks explicitly to delegate this to **subagents on a cheaper model**
(`subagent_type: "general-purpose"`, `model: "sonnet"`). Do that, run them one after the other, and
**verify their claims yourself** afterwards rather than trusting the reports.

* Subagent 1 — `/work/projects/quarkus-demo`: `quarkus create app` with extensions `rest,rest-jackson`,
  group `at.htlleonding`; endpoints `GET /hello`, `GET /api/greeting?name=X` →
  `{"message":"Hello, X!"}` (default `World`), `GET /api/items`, `POST /api/items` → 201;
  `mvn -B clean package` must pass its unit tests; start it with
  `nohup java -jar target/quarkus-app/quarkus-run.jar > app.log 2>&1 & disown`; then an httpyac suite
  `tests/api.http` covering every endpoint plus a 404, all requests green. Leave it running on 8080.
* Subagent 2 — `/work/projects/node-frontend`: Express app on 3000, `BACKEND_URL` env (default
  `http://localhost:8080`), built-in `fetch`, endpoints `/health`, `/api/greeting`, `/api/items`,
  `POST /api/items`, an HTML page rendering the items into `#items`, and 502 on backend failure;
  httpyac suite plus a Playwright/Chromium test `tests/ui.spec.js`. Leave it running.

Yesterday's result, for comparison: Quarkus 5 unit tests green, 6/6 httpyac; Node 6/6 httpyac and
1 Playwright test green.

### 4. Gotchas already paid for — don't rediscover them

* **httpyac `?? js <expr>` assertions** (6.16.7): the right-hand side is never evaluated as JS, so do
  not quote expected values (`== "Hello, World!"` fails, `== Hello, World!` works) and never compare
  two expressions (`a.count == a.items.length` compares against literal text — fold it into one
  expression such as `[a.count].includes(a.items.length) == true`). A boolean-only expression with no
  operator is silently swallowed into the request body — always append `== true`. `test` is a reserved
  request-block name.
* **`@playwright/test`** installed globally is invisible to Node's ESM resolver from a project
  directory. Install it per project with
  `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-save @playwright/test@<version>` so the
  browsers under `PLAYWRIGHT_BROWSERS_PATH=/work/tools/ms-playwright` are reused.
* **Non-interactive exec has the tool env** from the pod spec — no `source`, no `-l` needed.
* **Editing `bootstrap.sh`** does not roll the pod (stable ConfigMap name): `kubectl apply -k k8s/`
  then `kubectl rollout restart deploy/devbox`. Force a full reinstall with
  `kubectl exec deploy/devbox -- rm -rf /work/tools` before the restart.
* **Apps started with `nohup ... & disown` die on a pod restart.** Only `/work` survives.
* **NFS-backed PVC**: fine for course-sized projects, slower for large `node_modules`; sqlite on it is
  untested.
* **PodSecurity `baseline` forbids privileged containers** → no Docker/Podman build inside the DevBox.

### 5. Finish up

* Update `CLAUDE.md` and `k8s/README.md` with the **new** namespace/cluster facts and any manifest
  change you had to make (StorageClass, PVC size, resources). Remove the `student-testc20` values —
  that namespace no longer exists.
* Commit with Conventional Commits (see the global commit-message rules; `chore:` or `fix:` for a
  manifest adjustment, `docs:` for documentation).
* Two OpenSpec leftovers from yesterday are still open in
  `openspec/changes/add-devbox-deployment/tasks.md`: **6.3** fill `openspec/config.yaml` with the now
  decided tech stack and conventions, **6.4** fold the delta spec into `openspec/specs/` via
  `/opsx:sync`. Do 6.4 only once the DevBox is verified in the permanent namespace, then the change
  can be archived with `/opsx:archive`.
* If the spec in `openspec/changes/add-devbox-deployment/specs/devbox/spec.md` no longer matches what
  the permanent namespace forces you to do (for example a pinned StorageClass or no Playwright under
  `restricted`), say so instead of quietly diverging — that is a spec change, not an implementation
  detail.

## Context you may need

* The brief is `prompts/chat.md` (German). `prompts/superbox.md` is a **separate** idea: a second
  deployment running claude-cli that drives the DevBox via `kubectl exec`/`cp`. It is not part of this
  task. If it comes up: a pod needs `serviceAccountName` bound to a Role with `pods`, `pods/exec`,
  `pods/log`, `pods/portforward` — in the scratch namespace only SA `testc20` had any binding, and it
  had full `namespace-admin`, which is more than such a pod should get.
* One thing was never tested: in-cluster `kubectl` from **inside** the DevBox pod. The permission
  classifier blocked reading the projected SA token, so the RBAC answer above comes from the
  RoleBindings, not from an experiment. If the user needs it proven, ask them first.

## Context

See `proposal.md` — Why for motivation, `specs/superbox/spec.md` and `specs/devbox/spec.md` for the
behaviour contracts.

Facts established by probing the target cluster (namespace `student-testc20`, context `leocloud`) and
the running DevBox, before this design was written:

- **RBAC.** One namespaced Role, `namespace-admin` (verbs `*`), bound by RoleBinding `admin-access` to
  a single subject: ServiceAccount `testc20`. ServiceAccount `default` has no binding — a pod using it
  gets 403 on `list pods`. Confirmed from both directions: `kubectl auth can-i --list` as `testc20`
  returns `*`, and a `SelfSubjectRulesReview` from inside the DevBox pod (which runs as `default`)
  returns nothing but self-review verbs.
- **Storage.** One StorageClass, `default`, `cluster.local/nfs-subdir-external-provisioner`,
  `allowVolumeExpansion: true`. NFS supports `ReadWriteMany`, but a PVC's `accessModes` are immutable,
  and `devbox-work` was created `ReadWriteOnce`. PVC roots are mode `777`, `chown` to uid 1000 works,
  a uid-1000 process can write, and `flock` works over the mount.
- **Claude CLI behaviour**, measured in the DevBox (version 2.1.284, node 24.21.0, npm 11.19.0):
  - as uid 0 without `IS_SANDBOX`: `--dangerously-skip-permissions cannot be used with root/sudo
    privileges for security reasons`, exit 1;
  - as uid 0 with `IS_SANDBOX=1`: passes that gate, fails only on `Not logged in`;
  - as uid 1000: passes the gate too.
  - State written on first run: `~/.claude.json` plus `~/.claude/{projects,sessions,backups}` —
    **JSON/JSONL only, no SQLite file anywhere**. The test install was removed afterwards.
- **Egress** from a pod: `api.anthropic.com`, `registry.npmjs.org`, `github.com`, `deb.debian.org`,
  `nodejs.org` all reachable; no proxy variables; CoreDNS at 10.96.0.10 with search domain
  `student-testc20.svc.cluster.local`. No NetworkPolicy in the namespace. `statsig.anthropic.com` did
  not answer, which affects telemetry only.
- **PodSecurity** `enforce=baseline`, `warn=baseline`. The DevBox pod (`runAsUser: 0`) was admitted
  with no warnings. Privileged containers and host mounts are out.
- No `ResourceQuota`, no `LimitRange`. Server 1.30.3 on 4 nodes.

## Goals / Non-Goals

**Goals:**

- Make an agent session outlive the terminal that started it, and the laptop that owns that terminal.
- Give the agent a single-command path to any DevBox, so it never has to reason about pod names.
- Remove the copy step from the edit/build loop.
- Keep the blast radius of a yolo-mode agent inside the namespace strictly smaller than the user's own
  rights.
- Keep the SuperBox cheap to build and cheap to restart — it is infrastructure, not a toolchain.

**Non-Goals:**

- Running language toolchains in the SuperBox. Builds belong in a DevBox; duplicating Node/JDK/Maven
  there would recreate the 7–8 minute cold start this design is trying to avoid.
- Surviving a pod restart with sessions intact. tmux dies with its pod; the agent's transcripts persist
  but the running processes do not.
- Letting the SuperBox provision its own DevBoxes. That is a deliberate consequence of the narrow Role
  (see Decisions) and can be revisited.
- Multi-user operation. One user, one SuperBox, one credential.
- Any inbound network path — no Service, no Ingress, no port published for the agent.

## Decisions

**Run as uid 0 with `IS_SANDBOX=1`, not as a non-root user.**
The Claude CLI refuses `--dangerously-skip-permissions` as root unless `IS_SANDBOX=1` is set; both
branches were measured rather than assumed. Running as uid 1000 would also work for the CLI, but the
SuperBox shares a volume with the DevBox, which runs as uid 0 and writes root-owned build output.
Different uids across a shared NFS mount means one side cannot overwrite the other's files, and the
`spec` requires that it can. The alternatives were: move the DevBox to uid 1000 (costs a `chown -R`
over a multi-gigabyte NFS toolchain, or a full re-bootstrap, and rewrites a working deployment), or
paper over it with `fsGroup` and umasks (fragile on NFS, and `fsGroup` does not retroactively fix files
the other pod already wrote). Matching uids is the cheap, robust option. The security cost is nil in
practice: the container is already unprivileged under PodSecurity `baseline`, and "root" here is root
inside one namespaced container, which is exactly the sandbox `IS_SANDBOX=1` is meant to describe.

**A dedicated ServiceAccount with a narrow Role, not `serviceAccountName: testc20`.**
Reusing `testc20` would cost nothing to build and would give the SuperBox `*` on everything in the
namespace. That identity can delete `devbox-work`, and the agent running under it has permission
prompts switched off. The narrow Role grants `get/list/watch` on pods, services and deployments, `get`
on `pods/log`, `create` on `pods/exec` and `pods/portforward`, and `get`/`update` on exactly one Secret
by `resourceNames`. No verb `delete` appears anywhere in it and PVCs are not mentioned at all, so the
worst an out-of-control session can do is run commands inside a DevBox — which is its job — rather than
dismantle the namespace. The price is that the SuperBox cannot roll out further DevBoxes itself; the
user does that from the laptop with `kubectl apply -k k8s/`. If that becomes annoying, the Role can be
widened later to `create`/`patch` on deployments, services and configmaps without touching anything
else in this design.

**A new RWX PVC for shared projects, rather than sharing `devbox-work`.**
`accessModes` are immutable, so making `devbox-work` shareable means deleting and recreating it —
which, with `archiveOnDelete: "false"`, discards the installed toolchain and the acceptance-test
projects for a 7–8 minute rebuild. A second PVC, `shared-projects`, declared `ReadWriteMany` and
mounted at `/shared` by both pods, costs one extra volume and leaves each pod's private `/work`
untouched. It also draws a useful line: `/work` is per-pod machinery (toolchains, caches, agent state),
`/shared` is the code. Rejected alternative: keep strict `kubectl cp` per the original DevBox brief —
correct but it turns every file the agent reads or writes into a round trip over NFS plus an exec, which
is precisely the friction this change exists to remove. `kubectl cp` stays available through a helper for
the cases it is still right for, such as pulling an artifact out of a DevBox's private `/work`.

**Credentials: the PVC is authoritative, the Secret is a seed and a backup.**
The OAuth credential the CLI writes is refreshed over time, so a Secret alone is a snapshot that goes
stale — after a restart the pod would come up with a credential older than the one it last used. Keeping
`HOME` on the PVC lets the CLI own its own state and refresh in place. The Secret then serves the two
jobs it is actually good at: seeding a fresh or wiped PVC, and being the place credentials are kept out
of the repository. The bootstrap seeds `~/.claude` from the Secret **only** when the PVC holds no
credentials, so a restart never clobbers a newer token with an older one; `superbox-creds push` is the
explicit, user-driven way to refresh the Secret. Storing `~/.claude` on NFS is safe here because the CLI
writes JSON/JSONL and no SQLite, and `flock` was verified to work on the mount. Rejected alternative:
`ANTHROPIC_API_KEY` from a Secret via `envFrom` — the cleanest possible fit for "use k8s secrets", but it
bills API credits instead of the user's subscription and removes the `claude login` step the brief asks
for.

**tmux as the session host, entered through a wrapper.**
An `exec` session dies with its connection; a tmux server started inside the pod does not. `tmux new -As
<name>` is idempotent — it attaches if the session exists and creates it otherwise — which makes one
command serve both "start" and "reattach" and satisfies the concurrency requirement with no extra
machinery. The tmux configuration and the agent's scrollback live on the PVC. Deliberately not used: a
systemd-style supervisor or a second container, both of which add moving parts to a box whose entire job
is to keep one interactive process alive.

**DevBox addressing by `app.kubernetes.io/{name,instance}`, resolved by a helper.**
The DevBox currently carries only `app=devbox`, which cannot distinguish two of them. Adding the standard
labels is free in the rollout this change already needs. `devbox-exec` resolves
`app.kubernetes.io/name=devbox` (optionally `+ instance=<name>`), errors out listing the candidates when
the result is ambiguous, and otherwise execs into the single match — so the agent never handles a pod
name, and a second DevBox does not silently change where a command lands. The existing `app=devbox`
label and the `devbox` Service selector stay as they are, so nothing that works today breaks; a second
DevBox would get its own Service and its own instance label.

**Reuse the DevBox's bootstrap pattern verbatim.**
ConfigMap-mounted script, marker files under `/work/tools/.markers`, per-step failure isolation, log to
`/work/bootstrap.log`, background start with `exec sleep infinity` as PID 1, readiness probe on a marker
file. It is known to work in this cluster and keeps the two boxes legible side by side. Two adjustments
carried over from the DevBox's own retrospective: environment variables go in the **pod spec**, not in
`.bashrc`, because `kubectl exec -- cmd` runs no profile; and because `disableNameSuffixHash: true` keeps
the ConfigMap name stable, editing the script does not roll the pod, so a `kubectl rollout restart` is an
explicit step in the task list rather than an assumed side effect.

**`k8s/` restructured into `shared/`, `devbox/`, `superbox/` under a root kustomization.**
Three related but independently-owned deployments in one flat directory would be unreadable, and the
DevBox's files already occupy the generic names (`deployment.yaml`, `pvc.yaml`, `bootstrap.sh`). The root
`kustomization.yaml` keeps the documented `kubectl apply -k k8s/` working unchanged, and each subdirectory
stays applicable on its own. `git mv` preserves the DevBox's history. Rejected: leaving the DevBox flat and
nesting only the SuperBox — less churn now, but a layout nobody can explain later.

## Risks / Trade-offs

- **A long-lived Claude credential comes to rest in the namespace**, in a Secret and on an NFS PVC, both
  readable by anyone who can exec into the namespace (today: the holder of the `testc20` kubeconfig)
  → Accepted deliberately; it is the point of the change. Mitigated by keeping it out of git entirely,
  by never printing it from the helper, and by the SuperBox's own Role being able to read that one
  Secret and nothing else. The user can revoke the session from their Anthropic account at any time,
  and `kubectl delete secret superbox-claude-creds` plus wiping `~/.claude` on the PVC removes it from
  the cluster.
- **A yolo-mode agent with `pods/exec` can still do damage inside a DevBox** — it can delete `/shared`
  and `/work` contents from the inside, which no RBAC rule prevents → Mitigated only by the DevBox's
  data being reproducible (toolchain reinstalls, projects are in git once the repo exists). Worth
  stating plainly: the narrow Role bounds *Kubernetes* damage, not filesystem damage.
- **Applying this change restarts the DevBox** and kills the Quarkus and Express processes from its
  acceptance test → The restart is unavoidable (a volume mount is being added). Mitigated by making it
  an explicit, announced task with the restart commands from `k8s/README.md` beside it.
- **Two writers on one NFS volume**, with no coordination beyond the filesystem → In practice one agent
  edits and one build reads, so conflicts are unlikely; `flock` was verified to work if anything ever
  needs it. Not mitigated further, because introducing locking would be speculative complexity.
- **Concurrent tmux sessions all write `~/.claude.json`** on the same PVC → This race exists for
  concurrent Claude CLI instances on any machine and is not specific to NFS; the file is small and
  rewritten atomically via a `.tmp` file. Accepted. If it does bite, the fallback is a separate
  `CLAUDE_CONFIG_DIR` per session.
- **Tool versions resolved at install time, not pinned** (Node, kubectl, the CLI itself) → Same trade-off
  the DevBox already made: convenient, not reproducible. The marker files mean a given PVC keeps whatever
  it got, so a working SuperBox does not drift under the user; only a fresh PVC picks up new versions.
- **`IS_SANDBOX=1` is an undocumented-ish escape hatch** and a future CLI version could tighten or remove
  it, which would leave yolo mode refusing to start → The measurement is recorded here with the version it
  was made against (2.1.284). The fallback is switching both pods to uid 1000, which is a known-good path
  and was rejected only on cost, not on feasibility.
- **`kubectl` client/server skew**: server is 1.30.3, the laptop's client is 1.37 → The SuperBox installs a
  client in the supported skew window for 1.30 rather than simply taking "latest".
- **The SuperBox cannot deploy DevBoxes**, by design → If the workflow turns out to need it, widen the Role;
  the change is additive and touches nothing else.

## Migration Plan

1. Restructure `k8s/` with `git mv` and a root kustomization; verify `kubectl apply -k k8s/` still produces
   the DevBox unchanged (a diff of the rendered output before and after should be empty).
2. Apply `shared-projects` (RWX) and confirm it binds.
3. Patch the DevBox to mount `/shared` and to carry the instance labels; roll it; restart the demo apps per
   `k8s/README.md`.
4. Apply the SuperBox: ServiceAccount, Role, RoleBinding, PVC, ConfigMap, Deployment. Wait for readiness.
5. `kubectl exec -it deploy/superbox -- tmux new -As main`, `claude` → `/login`, then
   `superbox-creds push` to capture the credential into the Secret.
6. Enable remote control in that session and verify from the Claude app.
7. Run the acceptance test from inside the session.

**Rollback.** The SuperBox is additive: `kubectl delete -k k8s/superbox/` removes it, and the DevBox is
unaffected except for the `/shared` mount, which is reverted by removing the volume from its Deployment and
rolling it. `shared-projects` can be kept (it holds project sources) or deleted separately. Nothing in this
change modifies `devbox-work`.

## Open Questions

- How many DevBoxes the workflow actually wants. The labelling and the `devbox-exec` resolver are built for
  more than one, but only one is deployed; a second DevBox's manifests are not part of this change.
- Whether the acceptance-test applications now living in the DevBox's private `/work/projects` should be
  moved to `/shared/projects`. Deferred: it changes nothing about the design, and the DevBox change's own
  verification refers to their current location.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The task brief is `chat.md`; `k8s/` holds the DevBox deployment (see `k8s/README.md`). No application code
of its own — apps are created *inside* the DevBox under `/work/projects`.

Goal (`chat.md`, German): build a **DevBox** — a Kubernetes deployment on the HTL Leonding cloud
(https://cloud.htl-leonding.ac.at) that serves as a remote build/test/deploy environment, so work does
not run on the user's laptop. A later AI agent drives that container via `kubectl exec` and `kubectl cp`.

DevBox image requirements from the brief:

| Area | Requirement |
|------|-------------|
| OS | Debian, latest stable |
| Runtimes | Node.js (JavaScript), Quarkus (Java) |
| Tools | Playwright, httpyac, curl |

Acceptance test defined in the brief: create a Quarkus demo app inside the DevBox, build it and test it
with httpyac; then create a Node.js app that calls the Quarkus backend and test that too.

## Key constraints

- The kubeconfig already points at the user's namespace — do **not** create or switch namespaces, and do
  not add `-n <ns>` unless the user asks.
- The agent-facing interface to the DevBox is `kubectl exec` / `kubectl cp` only. No SSH, no ingress for
  the dev loop. Anything the DevBox needs must be baked into the image or installed via exec.
- The pod must stay alive with no foreground workload (e.g. `sleep infinity` as the command), because all
  work arrives through `exec`.
- The brief asks explicitly to delegate implementation subtasks to subagents on a **cheaper model**
  (e.g. `subagent_type: "general-purpose"` with `model: "haiku"` or `"sonnet"`).

## Workflow: OpenSpec

Planning is spec-driven via OpenSpec (`openspec/`, schema `spec-driven`). Use the slash commands /
skills rather than hand-editing the tree:

- `/opsx:propose` — create a change with proposal.md, `specs/<capability-path>/spec.md` (a delta),
  design.md, tasks.md. **Planning only** — this workflow never edits project code.
- `/opsx:apply` — implement the tasks of an existing change.
- `/opsx:sync` — fold a change's delta specs into `openspec/specs/`.
- `/opsx:archive` — finalize a completed change into `openspec/changes/archive/`.
- `/opsx:explore` — think through a problem before proposing.

These require the `openspec` CLI on PATH. `openspec/config.yaml` is still all-comments; put tech stack,
conventions and per-artifact rules there once decisions are made.

`.agents/` mirrors `.claude/skills/` for other agent runtimes — keep the two in sync if a skill changes.

## The DevBox deployment (`k8s/`)

| File | What |
|------|------|
| `pvc.yaml` | `devbox-work`, 20Gi, StorageClass `default` (NFS) |
| `deployment.yaml` | one pod, `debian:trixie-slim`, `sleep infinity`, PVC on `/work`, env (PATH/JAVA_HOME/...) baked into the pod spec |
| `service.yaml` | ClusterIP `devbox`, ports 8080 (Quarkus) / 3000 (Node) |
| `bootstrap.sh` | idempotent toolchain install into `/work/tools`, mounted via ConfigMap at `/opt/devbox` |
| `kustomization.yaml` | `configMapGenerator` for `bootstrap.sh`, no name-suffix hash, no namespace |

No container registry and no image build: the pod runs the public Debian image and installs the toolchain
into the PVC on first start (~7-8 min). Marker files in `/work/tools/.markers` make restarts skip the work.
apt packages are ephemeral and reinstalled on every start (`.deb` cache on the PVC).

Cluster facts (namespace `student-testc20`, context `leocloud`): k8s server 1.30, StorageClass `default`
(nfs-subdir provisioner), PodSecurity **baseline** (so `runAsUser: 0` and apt are fine, privileged is not),
no ResourceQuota / LimitRange.

Installed and verified: Node 24 LTS + npm 11, Temurin JDK 21 LTS, Maven 3.9, Quarkus CLI 3.39,
httpyac 6.16, Playwright 1.63 + Chromium, curl 8.14, git, jq, build-essential.

## Commands

```bash
kubectl apply -k k8s/                                        # deploy / update
kubectl wait --for=condition=ready pod -l app=devbox --timeout=20m
kubectl exec deploy/devbox -- tail -f /work/bootstrap.log    # bootstrap progress
kubectl exec -it deploy/devbox -- bash -l                    # shell
kubectl exec deploy/devbox -- bash -lc 'cd /work/projects/<app> && mvn -B package'
kubectl cp ./src "$(kubectl get pod -l app=devbox -o name | cut -d/ -f2)":/work/projects/<app>/src
kubectl port-forward deploy/devbox 8080:8080                 # reach an app locally
```

Paths inside the pod: projects `/work/projects`, toolchains `/work/tools`, Maven repo
`/work/.m2/repository`, bootstrap log `/work/bootstrap.log`, readiness marker `/work/.devbox-ready`.

## Not yet set up

No git repo and no CI.

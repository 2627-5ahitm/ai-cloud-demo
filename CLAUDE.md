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

- Do **not** read the user's files in `prompts/` — no open, list, search, grep, or delegating that to
  subagents. Enforced by a `Read(./prompts/**)` deny rule in `.claude/settings.json`.
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

## The DevBox deployment (`k8s/`, `image/`)

| File | What |
|------|------|
| `image/Dockerfile` | `debian:trixie-slim` + whole toolchain under `/opt/tools`, versions pinned as `ARG`s, tool env as `ENV` |
| `k8s/pvc.yaml` | `devbox-work`, 2Gi (LeoCloud allows up to 20Gi), default StorageClass |
| `k8s/deployment.yaml` | one pod, image `ghcr.io/htl-leonding/devbox`, `sleep infinity`, PVC on `/work`, ephemeral-storage 500Mi/4Gi |
| `k8s/service.yaml` | ClusterIP `devbox`, ports 8080 (Quarkus) / 3000 (Node) |
| `k8s/kustomization.yaml` | resources + `images:` with the current tag, no namespace |

The toolchain lives in the image, built `linux/amd64` and pushed to ghcr.io (`docker login ghcr.io` already
done by the user). New build → new tag → bump `newTag` in `kustomization.yaml` → `kubectl apply -k k8s/`.
The PVC only holds projects, the Maven repo and the npm cache.

LeoCloud rules (skills `.claude/skills/leocloud/SKILL.md` and `.claude/skills/ghcr/SKILL.md`, follow them for
anything deployment-related): PVC max 20Gi and never enlarged beyond; ephemeral-storage default 2Gi/container,
max 20Gi/container, 40Gi per namespace (quota `leocloud-node-disk`); every image build gets a new tag
`$(date -u +%Y%m%d-%H%M%S)`, and after a rollout the pod's image digest must match the pushed tag; PodSecurity **baseline** (`runAsUser: 0` fine, privileged not);
ClusterIP services only; images must be built from the project and pushed, not public base images + scripts.
Never delete a PVC or the namespace without explicit user confirmation.

Cluster facts (namespace `student-t-stuetz`, context `leocloud`): k8s server 1.30, StorageClass `default`
(nfs-subdir provisioner). The namespace also runs an unrelated `tombox` deployment with its own PVCs — leave
it alone.

Installed and verified: Node 24.21 + npm 11.19, Temurin JDK 21.0.12 LTS, Maven 3.9.16, Quarkus CLI 3.39.5,
httpyac 6.16.7, Playwright 1.63.0 + Chromium, Claude Code 2.1.296 (config in `/work/.claude`), curl 8.14, git,
jq, build-essential.

## Commands

```bash
docker buildx build --platform linux/amd64 -t ghcr.io/htl-leonding/devbox:<tag> --push image/
kubectl apply -k k8s/                                        # deploy / update
kubectl rollout status deploy/devbox
kubectl exec -it deploy/devbox -- bash                       # shell
kubectl exec deploy/devbox -- bash -c 'cd /work/projects/<app> && mvn -B package'
kubectl cp ./src "$(kubectl get pod -l app=devbox -o name | cut -d/ -f2)":/work/projects/<app>/src
kubectl port-forward deploy/devbox 8080:8080                 # reach an app locally
```

Paths inside the pod: projects `/work/projects`, toolchains `/opt/tools`, Maven repo
`/work/.m2/repository`, readiness marker `/work/.devbox-ready`.

## Not yet set up

No CI.

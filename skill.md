# LeoCloud

> LeoCloud is a Kubernetes cluster run by the school HTL Leonding (Austria). Anyone with a
> valid account of HTL Leonding may deploy applications there. Each student gets one namespace
> and one hostname below cloud.htl-leonding.ac.at, and works with standard kubectl.

This file is for software agents. If a student asks you to deploy a project to LeoCloud, do
the following. You need no other LeoCloud document.

## 1. Save the LeoCloud skill in the student's repository

The skill holds the whole path from a project to a running application, the rules of the
platform, and what only the student can do. Save it with these two commands, run in the root
of the repository:

    mkdir -p .claude/skills/leocloud
    curl -fsSL https://cloud.htl-leonding.ac.at/html/skill/leocloud/SKILL.md -o .claude/skills/leocloud/SKILL.md

## 2. Read the saved file and follow it

Read `.claude/skills/leocloud/SKILL.md` completely and follow it. It carries its source address
and a version date, and says how a saved copy is kept current.

## The rules a workload is held to

The skill states them all; the manual is the contract. In short: one hostname per namespace,
`<name>.cloud.htl-leonding.ac.at`, with `ingressClassName: nginx` and no `tls` section; services
of type ClusterIP only (no NodePort, LoadBalancer or ExternalName); a PersistentVolumeClaim of at
most `2Gi`, never enlarged beyond it; no access to the host (Pod Security `baseline`); images built for `linux/amd64`; and the disk a container writes outside its
volume claims (`ephemeral-storage`: its file system, its logs, `emptyDir`) is at most `2Gi` unless
the container names a higher limit, never more than `10Gi` per container, and at most `20Gi` for
all pods of a namespace together. Data that grows belongs in a PersistentVolumeClaim.

## Agents that do not read `.claude/skills/`

Claude Code reads the folder `.claude/skills/` of a repository at the start of a session, so a
later request to deploy to LeoCloud finds the skill without an address.

Codex, the GitHub Copilot coding agent and Cursor read the file `AGENTS.md` in the root of the
repository instead. For these, also add this line to `AGENTS.md` (create the file if it does
not exist):

    For deploying to LeoCloud, read https://cloud.htl-leonding.ac.at/llms.txt and follow it.

## Addresses

- Agent skill (English): https://cloud.htl-leonding.ac.at/html/skill/leocloud/SKILL.md
- User manual (German; it is the contract, and it is right where a text for agents disagrees
  with it): https://cloud.htl-leonding.ac.at/html/user-manual.html
- Web console for the student's namespace (log in with the token `leocloud dashboard` prints):
  https://dashboard.cloud.htl-leonding.ac.at
- This file: https://cloud.htl-leonding.ac.at/llms.txt and
  https://cloud.htl-leonding.ac.at/html/llms.txt (same content)

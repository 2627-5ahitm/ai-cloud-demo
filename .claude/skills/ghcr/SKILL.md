---
name: ghcr
description: Lead a student through the GitHub container registry (ghcr.io) - create a token, log in with docker, find the pushed package and make it public. Use when the user asks how to push an image to ghcr.io or the GitHub container registry, when docker login ghcr.io or a push to ghcr.io fails, or when a cluster cannot pull an image from ghcr.io.
---

# The GitHub container registry (ghcr.io)

Source: https://cloud.htl-leonding.ac.at/html/skill/ghcr/SKILL.md
Version: 2026-10-05.3

## If you are reading a saved copy

This file may be a copy saved in a repository at `.claude/skills/ghcr/SKILL.md`.
This is the first thing you do, every time, before any other step: fetch the source address
above (for example with `curl -fsSL`) and compare the two `Version:` lines. Then tell the
student in one sentence which of the three cases it was.

- The served file has a newer date: follow the served file, and replace the saved copy with it.
- The dates are equal: go on with this file.
- The source cannot be fetched (no answer, or an error such as 404): go on with this file, and
  tell the student that this copy of the ghcr skill may be out of date.

## How to lead the student

The student has probably never used the registry. Steps 2, 3 and 7, and deleting a package,
happen in the student's browser or need the student's password. For these, **you explain one
step, the student does it, and you wait** until the student says it is done. Then you check the
result where this file gives a check, and go to the next step. Do not give all steps at once.

**Everything else is yours:** the checks, building and pushing the image, and looking at the
`.dockerignore` and the `Dockerfile`. Do not hand these to the student. Before building, ask
once (step 4), and then do it.

**You never see the token.** Do not ask for it in the conversation, do not run the login
yourself, and never write the token into a file: not into a script, not into an `.env` file, not
into a manifest, not into a commit. If the student pastes a token into the conversation, tell
them to delete that token on GitHub and create a new one.

Ask the student for their GitHub user name at the start. The image is named
`ghcr.io/<github-user>/<image>`, **all in lower case**, even if the user name has capital letters.

## Step 1 — Check whether a login already exists

```
docker login ghcr.io < /dev/null
```

With the input closed it uses only the credential that is already stored and cannot ask for
one. If it prints `Login Succeeded`, go to step 4. Otherwise go on with step 2.

## Step 2 — The student creates a token

The registry accepts only a **personal access token (classic)**. A fine-grained token does not
work for the registry, even though GitHub offers it first.

Give the student this address. It opens GitHub's form for a new classic token with the
permission `write:packages` already selected (it allows pushing and pulling images):

    https://github.com/settings/tokens/new?scopes=write:packages&description=LeoCloud

(Without the address: GitHub → Settings → Developer settings → Personal access tokens →
Tokens (classic) → Generate new token (classic), and tick `write:packages`.)

Tell the student:

- **Expiration:** choose *Custom* and a date at the end of the current school year (early July).
  The default of 30 days runs out in the middle of a project.
- Click *Generate token* at the bottom of the page.
- **GitHub shows the token only once.** Copy it now, before leaving the page, and keep it
  somewhere safe, for example in a password manager. It starts with `ghp_`.

Wait until the student says the token is copied.

## Step 3 — The student logs in

The student runs this in their own terminal, with their GitHub user name in place of
`<github-user>`:

```
docker login ghcr.io -u <github-user>
```

At `Password:` the student pastes the token and presses Enter. Nothing is shown while pasting;
that is normal. On Linux and in WSL Docker may warn that the password is stored unencrypted in
`~/.docker/config.json`; the login still worked.

When the student says it is done, run the check of step 1 again. It must print
`Login Succeeded`. If the student's login printed `unauthorized` or `denied`, the token was
wrong, expired or lacks `write:packages`: go back to step 2.

## Step 4 — Push the image

Ask the student once:

> May I build the image and push it to ghcr.io now? (Or would you rather run the command
> yourself?)

When the student agrees, run the build and the push yourself. Give the student the command to run
only if they chose to run it themself, and check the result after they say it is done. (If the
LeoCloud skill already asked whether you may build, push and deploy, that was this question; do
not ask again.)

Build for `linux/amd64` (for LeoCloud, the LeoCloud skill gives the same command). **Every
build gets a new tag, made from the date and time to the second.** Never reuse a tag, not even one
from an earlier conversation, and never use only `latest`: a node that already holds an image
under that tag starts the old image without asking the registry.

```
tag="$(date -u +%Y%m%d-%H%M%S)"
docker buildx build --platform linux/amd64 -t ghcr.io/<github-user>/<image>:$tag --push .
```

If the push is refused with `denied` or `unauthorized` although step 1 printed
`Login Succeeded`, the stored token cannot write packages or has expired. The cure is a new
token (step 2) and a new login by the student (step 3).

## Step 5 — Find the package

After the first push the image appears as a **package** on the student's GitHub profile:

    https://github.com/<github-user>?tab=packages

The package has the name of the image, without the tag. **A new package is private.** A cluster
cannot pull a private image without a credential, and the pod then shows `ImagePullBackOff` or
`ErrImagePull`.

## Step 6 — Before making it public: tell the student, and check for secrets

Making the package public is the recommended way: then nobody needs a credential to pull it,
and nothing secret has to be stored in the cluster. But first tell the student, in these words
or close to them:

> A public package cannot be made private again. Everything inside the image — your code, and
> every file that was copied into it — can then be downloaded and read by anyone.

Then check, and tell the student what you found:

- The repository has a `.dockerignore` that keeps out at least `.env`, `.env.*`, `.git`, private
  keys (`*.pem`, `*.key`, `id_rsa*`) and local configuration files with passwords. If it is
  missing or incomplete, write it.
- The `Dockerfile` has no `ENV` or `ARG` with a password, token or key in it, and copies no such
  file. Secrets belong into the cluster at run time (for example a Kubernetes secret), not into
  the image.
- Every version already pushed to the package becomes public too. If an earlier version may
  hold a secret, the student deletes the whole package first (package settings → *Delete this
  package*), and you push again with the corrected build.

If the student decides that the package must stay private, stop here: a cluster then needs a
pull credential (the LeoCloud skill describes it, and the student supplies the token for it).

## Step 7 — The student makes the package public

The student opens the package's settings, either by the address

    https://github.com/users/<github-user>/packages/container/<image>/settings

or from the package page with *Package settings* (on the right). At the bottom, under
*Danger Zone*: *Change visibility* → *Public* → type the package name → confirm.

When the student says it is done, check it **with no credential at all**. The empty
configuration directory makes sure that the stored login is not used, and it leaves the
student's login untouched:

```
DOCKER_CONFIG="$(mktemp -d)" docker manifest inspect ghcr.io/<github-user>/<image>:<tag>
```

- It prints a manifest (JSON): the package is public. Tell the student.
- `unauthorized`: the package is still private. Ask the student to look at step 7 again.
- `denied`: there is no image of that name and tag. Check the user name, the image name (lower
  case) and the tag.

Report the package as public only after this check printed a manifest.

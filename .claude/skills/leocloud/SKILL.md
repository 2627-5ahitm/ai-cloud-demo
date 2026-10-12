---
name: leocloud
description: Deploy a project to LeoCloud, the Kubernetes cluster of HTL Leonding. Use when the user mentions LeoCloud or cloud.htl-leonding.ac.at, or asks to deploy, update or repair an application there.
---

# LeoCloud

Source: https://cloud.htl-leonding.ac.at/html/skill/leocloud/SKILL.md
Version: 2026-10-07

## If you are reading a saved copy

This file may be a copy saved in a repository at `.claude/skills/leocloud/SKILL.md`.
This is the first thing you do, every time, before any other step: fetch the source address
above (for example with `curl -fsSL`) and compare the two `Version:` lines. Then tell the
student in one sentence which of the three cases it was.

- The served file has a newer date: follow the served file, and replace the saved copy with it.
- The dates are equal: go on with this file.
- The source cannot be fetched (no answer, or an error such as 404): go on with this file, and
  tell the student that this copy of the LeoCloud skill may be out of date.

Then check that the repository also holds the ghcr skill, which leads the student through the
container registry. If `.claude/skills/ghcr/SKILL.md` does not exist, save it:

```
mkdir -p .claude/skills/ghcr
curl -fsSL https://cloud.htl-leonding.ac.at/html/skill/ghcr/SKILL.md -o .claude/skills/ghcr/SKILL.md
```

## What LeoCloud is

- LeoCloud is a Kubernetes cluster run by the school HTL Leonding. Anyone with a valid account
  of HTL Leonding may use it; the normal school account is used, there is no registration.
- Each student has exactly one namespace and exactly one hostname.
- You work with standard `kubectl`. The command `leocloud` is only needed to log in and to read
  the starting template.
- The cluster has a web console at https://dashboard.cloud.htl-leonding.ac.at. The student
  opens it with `leocloud dashboard`, which prints a token for one hour to paste into its login
  page. No template and nothing in the namespace is needed for it.
- `kubectl top pod` shows the CPU and memory use of the student's own pods, and so does the web
  console. The use of the nodes (`kubectl top node`) is refused.
- The user manual is the contract. It is in German:
  https://cloud.htl-leonding.ac.at/html/user-manual.html
  If this file and the manual disagree, the manual is right.

## What the student must do themself

Ask the student at the moment you need one of these. Do not try to do them alone.

1. **Installing `leocloud`.** The installer asks for the student's `sudo` password. Give the
   student this command to run in their own terminal, and do not try to supply a password:

   ```
   bash -c "$(curl -fsSL https://cloud.htl-leonding.ac.at/html/install.sh)"
   ```

   There is no `leocloud` for Windows. Under Windows all work is done inside WSL (Ubuntu),
   with the Linux version of `leocloud`.
   `kubectl` is installed as described at https://kubernetes.io/docs/tasks/tools/#kubectl

2. **Logging in to LeoCloud.** The student runs this command in their own terminal, not you.
   Never run it yourself, in no form:

   ```
   leocloud auth login
   ```

   It prints a login address and opens it in a browser, and it waits for the sign-on with the
   school account. It waits longer than you may be allowed to wait for a command, so do not
   run it yourself, not even in the background. Ask the student to run it, and wait until the
   student says the login is done.

3. **Installing and starting Docker.** If Docker is missing or not running, the student
   installs or starts it. You do not install it.

4. **Creating a registry token and logging in to the container registry.** The student
   creates a GitHub token and runs `docker login ghcr.io` in their own terminal. Lead them
   through it with the ghcr skill (`.claude/skills/ghcr/SKILL.md`, steps 2 and 3). You do not
   run the login and you do not ask for the token in the conversation.

5. **Making the image's package public.** The student changes the visibility on GitHub. This
   is the recommended way to let the cluster pull the image (step 7 of the path). Lead them
   through it with the ghcr skill (steps 5 to 7), including its warning first.

6. **A credential for a private image.** Only if the student decides that the package must stay
   private, the cluster needs a credential to pull the image (step 7 of the path). Ask the
   student for it at that moment. Never write a credential into a file of the repository: not
   into a manifest, not into a script, not into an `.env` file, not into a commit.

## The path from a project to a running application

Do the steps in this order. **Steps 1 to 4 are checks. All four must pass before you write a
file, build anything or apply anything.** If one does not pass, stop there, tell the student
what is missing, and go on only when the check passes.

**The application always runs from an image that you build from this project and push to the
registry.** Do not go around the build: do not put the project's source files into a ConfigMap
and run them on a public base image, and do not deploy a public image in place of the project.

1. **Check the tools.** `kubectl version --client` and `leocloud --version` must both answer.
   If `leocloud` is missing, see "Installing `leocloud`" above.

2. **Check that Docker is installed and running.** `docker version` must print a `Server:`
   part without an error. If the command is missing, Docker is not installed; if it cannot
   reach the daemon, Docker is not running. In both cases ask the student to install or start
   Docker, and wait.

3. **Check the login to the container registry.** The registry is ghcr.io. Ask the student for
   their GitHub user name; the image is named `ghcr.io/<github-user>/<image>`, all lower case.
   Then run:

   ```
   docker login ghcr.io < /dev/null
   ```

   It must print `Login Succeeded`. With the input closed it uses only the credential that is
   already stored and cannot ask for one. If it prints anything else, the student has no
   working login: lead them through the ghcr skill, steps 2 and 3 (a token, then
   `docker login ghcr.io` in their own terminal), wait until they say it is done, and run the
   check again.

4. **Check the login to LeoCloud.** Run `kubectl config current-context`. It must print
   `leocloud`, and `kubectl get pods` must answer without an error.
   - If there is no such context, or `kubectl get pods` is refused, ask the student to run
     `leocloud auth login` in their own terminal (see above) and wait.
   - If the current context is another cluster, stop. Apply nothing. Tell the student, and ask
     them to run `leocloud auth login`, which makes `leocloud` the current context. Check again
     before every `kubectl apply` and `kubectl delete` in a new session.

5. **Read the namespace and the hostname.**
   - Namespace: `kubectl config view --minify -o jsonpath='{..namespace}'`
   - Hostname: run `leocloud get template nginx`. It only prints manifests and changes
     nothing. The line `- host:` of the ingress in that output is the student's hostname. It is
     `<name>.cloud.htl-leonding.ac.at`, where `<name>` is the namespace without the leading
     `student-`.

   **Then ask the student once:**

   > The checks passed. May I build the image, push it and deploy it to LeoCloud now? (Or would
   > you rather run the commands yourself?)

   When the student agrees, do steps 6 to 10 yourself without asking again. Stop only where the
   student must act: making the package public in step 7. Do not give the student a build, push
   or apply command to run. Only if the student chose to run the commands themself, give them one
   at a time and check each result after the student says it is done. A later deploy in the same
   conversation is asked for again, once.

6. **Build the image for `linux/amd64` and push it.** Every node of the cluster is `amd64`; an
   image built on an Apple Silicon Mac without the platform option does not start. If the
   project has no `Dockerfile`, write one. **Every build gets a new tag, made from the date and
   time to the second.** Never reuse a tag, not even one from an earlier conversation, and never
   use only `latest`: a node that already holds an image under that tag starts the old image
   without asking the registry, and the new build never runs.

   ```
   tag="$(date -u +%Y%m%d-%H%M%S)"
   docker buildx build --platform linux/amd64 -t ghcr.io/<github-user>/<image>:$tag --push .
   ```

   If the push is refused although step 3 passed, the stored token may not write packages or
   has expired. Lead the student through a new token and a new login with the ghcr skill,
   steps 2 and 3.

7. **Give the cluster access to the image.** A new package on ghcr.io is private. The
   cluster then cannot pull it, and the pod shows `ImagePullBackOff` or `ErrImagePull`.
   **Recommend making the package public**, and lead the student through it with the ghcr
   skill, steps 5 to 7: it warns first that this cannot be undone, checks the image for
   secrets, and proves afterwards that the image can be pulled without a credential.

   Only if the student decides that the package must stay private, create a pull secret. Ask
   the student for a GitHub token that may read packages, and create the secret directly with
   `kubectl`, not from a file:

   ```
   kubectl create secret docker-registry ghcr-pull \
     --docker-server=ghcr.io \
     --docker-username=<github-user> \
     --docker-password=<token>
   ```

   Then name it in the pod template of the deployment:

   ```yaml
   spec:
     template:
       spec:
         imagePullSecrets:
           - name: ghcr-pull
   ```

8. **Write the manifests.** Start from the output of `leocloud get template nginx`. It shows
   the shape that is accepted: a Deployment, a Service without a type, and an Ingress with
   `ingressClassName: nginx`, one host and no `tls` section. Replace the demo web server by the
   image of step 6 and its port, and keep to the rules below. Do not apply the template itself
   unless the student wants the demo page. Do not write a `namespace:` into the manifests; the
   context already names the student's namespace.

   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: <app>
   spec:
     ingressClassName: nginx
     rules:
       - host: <name>.cloud.htl-leonding.ac.at
         http:
           paths:
             - path: /
               pathType: Prefix
               backend:
                 service:
                   name: <app>
                   port:
                     number: 80
   ```

9. **Apply.** Check the context once more (step 4), then `kubectl apply -f <file or folder>`.

10. **Verify.** Do not report success before both of these hold:
   - `kubectl rollout status deployment/<app>` succeeds and `kubectl get pods` shows the pods
     `Running`. If not, read `kubectl describe pod <pod>` and `kubectl get events`.
   - `curl -s -o /dev/null -w '%{http_code}' https://<name>.cloud.htl-leonding.ac.at/` answers
     with the status the application is expected to give, normally `200`.
   - **The pods run the image you just built.** Compare the digest the new tag points to in the
     registry with the image ID of every pod of the deployment:

     ```
     docker buildx imagetools inspect ghcr.io/<github-user>/<image>:$tag --format '{{.Manifest.Digest}}'; echo
     kubectl get pods -l app=<app> -o jsonpath='{range .items[*]}{.status.containerStatuses[0].imageID}{"\n"}{end}'
     ```

     Every image ID must end in `@` followed by exactly that digest. If one differs, an old image
     is running: tell the student so, build again with a new tag, and apply again. A hostname
     that answers is not success on its own.

## The rules for every workload

These are the rules of the platform. Write manifests that keep all of them.

- **One hostname.** An ingress may name exactly one host:
  `<name>.cloud.htl-leonding.ac.at`, where `<name>` is the namespace without `student-`. No
  other hostname, no second host, no ingress without a host, no own domain.
- **No TLS settings.** Encrypted transport ends at the edge of the cluster, with a certificate
  the platform holds. The ingress has no `tls` section and no certificate annotations (no
  cert-manager, no issuer). The application is reachable at `https://` anyway.
- **Ingress class.** Every ingress names `ingressClassName: nginx`.
- **Services are of type ClusterIP only.** Leave the type out, or write `ClusterIP`. No
  `NodePort`, no `LoadBalancer`, no `ExternalName`. An application is reachable from outside
  only through an ingress on the student's hostname.
- **Storage.** A PersistentVolumeClaim requests at most `20Gi`, and a claim cannot be enlarged
  beyond `20Gi`. Leave `storageClassName` out; the claim then gets the default storage class.
  The manual: https://cloud.htl-leonding.ac.at/html/user-manual.html#services-und-speicher
- **No access to the host.** Every namespace is held to the Kubernetes Pod Security level
  `baseline`. A pod must not ask for `hostNetwork`, `hostPID`, `hostIPC`, a `hostPath` volume,
  a `hostPort`, `privileged: true` or added capabilities. The list is in the manual:
  https://cloud.htl-leonding.ac.at/html/user-manual.html#pod-security
- **Disk on the node.** What a container writes outside its volume claims — into its own file
  system (for example `/tmp`), into its logs, and into `emptyDir` volumes — is bounded
  (`ephemeral-storage`). A container that names no value gets a limit of `2Gi` and a request of
  `100Mi`. A container may name a limit of at most `20Gi`. The limits of all pods of a namespace
  together are at most `40Gi`; during a rollout the old and the new pod both count. Data that
  grows — a database, uploaded files, backups, archives — belongs in a PersistentVolumeClaim.
  If a container needs more than `2Gi`, name both the request and the limit; a container that
  names only a request above `2Gi` is refused:

  ```yaml
  resources:
    requests:
      ephemeral-storage: 1Gi
    limits:
      ephemeral-storage: 5Gi
  ```

  What the student sees when a pod is stopped for it is in the manual:
  https://cloud.htl-leonding.ac.at/html/user-manual.html#speicher-am-rechner
- **Images are built for `amd64`** (`linux/amd64`).

## When something is refused

- **The ingress is refused with a message like**
  `The host "<host>" named in <place> of this ingress is not allowed. The namespace "<namespace>" may use exactly one hostname: write "- host: <hostname>".`
  The ingress names a hostname that is not the student's own. Write exactly the hostname the
  message gives.
- **A pod is refused with**
  `pods "..." is forbidden: violates PodSecurity "baseline:latest": host namespaces (hostNetwork=true)`
  or `kubectl apply` of a Deployment, Job, CronJob or StatefulSet prints
  `Warning: would violate PodSecurity "baseline:latest": ...`
  The workload asks for access to the host. With the warning the Deployment is accepted, but
  its pods are not created: `kubectl get pods` shows none, and `kubectl get events` shows
  `FailedCreate` with the same message. Remove the field the message names and apply again.
  The level cannot be changed or switched off in the namespace.
- **A pod is stopped: `kubectl get pods` shows it `Evicted` or `Error`**, and
  `kubectl describe pod <pod>` says under `Message` that it went over its local storage limit.
  The pod wrote more than its `ephemeral-storage` limit outside its volume claims. Move the data
  that grows into a PersistentVolumeClaim, or name a higher limit, at most `20Gi`. A Deployment
  starts a new pod, which is stopped again if it writes as much.
- **A pod is refused with a message naming the quota `leocloud-node-disk`**, or a Deployment's
  pods are not created and `kubectl get events` shows `FailedCreate` with that message. The pods
  of the namespace together would name more than `40Gi` of `ephemeral-storage` limits. Delete
  workloads that are no longer needed, or name smaller limits. A refusal that names the maximum
  per container means a container asked for more than `20Gi`. These limits cannot be changed
  in the namespace. Manual:
  https://cloud.htl-leonding.ac.at/html/user-manual.html#speicher-am-rechner
- **A service is refused with**
  `LeoCloud: a service of type NodePort is not allowed in this namespace. Only type ClusterIP is allowed (leave the type out). An application is reached from outside through an ingress on your hostname.`
  (or the same with `LoadBalancer` or `ExternalName`). Remove the `type:` line from the service,
  or write `type: ClusterIP`, and reach the application through the ingress.
- **A PersistentVolumeClaim is refused with**
  `LeoCloud: this volume claim requests 25Gi of storage. A claim in this namespace may request at most 20Gi, and an existing claim cannot be enlarged beyond 20Gi.`
  Request at most `20Gi`. For a StatefulSet with `volumeClaimTemplates` the StatefulSet is
  accepted, but its claim is not created and its pod does not start; `kubectl get events` shows
  `FailedCreate` with the same message. Manual:
  https://cloud.htl-leonding.ac.at/html/user-manual.html#services-und-speicher
- **`leocloud auth login` is refused with**
  `Your previous namespace of this name is still being removed. Please run the command again in a few seconds.`
  The namespace was deleted a moment ago. Ask the student to run the login again after a few
  seconds. They then get a new, empty namespace.

## Deleting

Deleting a namespace or a PersistentVolumeClaim destroys the data in the volumes at once and
for good. There is no period in which it can be brought back, and nobody can bring it back,
not the administrators either.

- Never run `kubectl delete namespace` or `kubectl delete pvc`, and never apply anything that
  removes a PersistentVolumeClaim, on your own decision.
- If you conclude that one of them should be deleted, first tell the student exactly that: the
  stored data is destroyed at once and cannot be brought back by anyone. If something should be
  kept, it must be copied out first, for example with `kubectl cp`.
- Delete only after the student has confirmed it in this conversation. If the student does not
  confirm, delete nothing.
- After a namespace was deleted, the student logs in again (`leocloud auth login`, run by the
  student) and gets an empty namespace.

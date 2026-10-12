<!-- The brief asks for implementation subtasks to be delegated to subagents on a cheaper model
     (general-purpose with model haiku/sonnet). Groups 1-3 and 8 are good candidates; groups 4-7
     involve credentials, a live rollout and the acceptance test and should stay in the main session. -->

## 1. Repository restructure

- [ ] 1.1 `git mv` the DevBox manifests into `k8s/devbox/` (`pvc.yaml`, `deployment.yaml`,
      `service.yaml`, `bootstrap.sh`, `kustomization.yaml`) and verify `git status` shows renames, not
      delete+add
- [ ] 1.2 Write `k8s/kustomization.yaml` at the root with `resources: [shared/, devbox/, superbox/]`
      and no namespace, and verify `kubectl kustomize k8s/devbox/` renders the same four DevBox objects
      as before the move (diff against `kubectl kustomize` output captured beforehand — must be empty)
- [ ] 1.3 Create `k8s/shared/` and `k8s/superbox/` with their own `kustomization.yaml` and verify
      `kubectl kustomize k8s/` renders every object of all three directories without error

## 2. Shared volume and DevBox changes

- [ ] 2.1 Write `k8s/shared/pvc-shared-projects.yaml` (`shared-projects`, **ReadWriteMany**, 20Gi,
      StorageClass `default`), apply it, and verify the PVC reaches `Bound` with `ACCESS MODES = RWX`
- [ ] 2.2 Add the `shared-projects` volume and its `/shared` mount to `k8s/devbox/deployment.yaml` and
      verify `kubectl kustomize k8s/devbox/` shows the mount before applying
- [ ] 2.3 Add labels `app.kubernetes.io/name: devbox` and `app.kubernetes.io/instance: devbox` to the
      DevBox pod template (keeping `app: devbox` and the existing Service selector untouched) and
      verify `kubectl get pods -l app.kubernetes.io/name=devbox` returns exactly the DevBox pod while
      `kubectl get endpoints devbox` still lists its IP
- [ ] 2.4 Apply the DevBox change, wait for the rolled pod to be Ready, and verify
      `kubectl exec deploy/devbox -- touch /shared/.probe && kubectl exec deploy/devbox -- ls -la /shared`
      succeeds and that `/work/tools` is still populated (no re-bootstrap was triggered)
- [ ] 2.5 Restart the Quarkus (`:8080`) and Express (`:3000`) demo processes killed by the rollout using
      the commands in `k8s/README.md`, and verify `curl` against both ports from inside the DevBox
      answers

## 3. SuperBox cluster identity

- [ ] 3.1 Write `k8s/superbox/rbac.yaml` — ServiceAccount `superbox`, Role `superbox-driver`
      (`pods`/`services`/`deployments` get,list,watch; `pods/log` get; `pods/exec` and
      `pods/portforward` create; `secrets` get,update restricted to `resourceNames:
      [superbox-claude-creds]`), RoleBinding `superbox-driver` — and verify no rule contains `delete`
      and no rule mentions `persistentvolumeclaims`
- [ ] 3.2 Apply the RBAC objects and verify with
      `kubectl auth can-i <verb> <resource> --as=system:serviceaccount:student-testc20:superbox` that
      `create pods/exec` is **yes**, and that `delete pods`, `delete deployments`, `get pvc` and
      `get secret/testc20` are all **no**

## 4. SuperBox workload

- [ ] 4.1 Write `k8s/superbox/pvc.yaml` (`superbox-work`, RWO, 10Gi), apply it and verify it reaches
      `Bound`
- [ ] 4.2 Write `k8s/superbox/deployment.yaml` — `debian:trixie-slim`, one replica,
      `strategy: Recreate`, `serviceAccountName: superbox`, `runAsUser: 0`, `command` starting
      `bootstrap.sh` in the background then `exec sleep infinity`, `superbox-work` at `/work`,
      `shared-projects` at `/shared`, ConfigMap at `/opt/superbox`, optional Secret
      `superbox-claude-creds` mounted at `/opt/superbox-creds` with `optional: true`, requests
      250m/512Mi and limits 2/4Gi — and verify the pod reaches `Running`
- [ ] 4.3 Put the environment in the pod spec (`HOME=/work/home`, `IS_SANDBOX=1`, `TOOLS=/work/tools`,
      `NPM_CONFIG_PREFIX`, `NPM_CONFIG_CACHE`, `PATH` covering `/work/tools/{node/bin,npm-global/bin,bin}`,
      `LANG=C.UTF-8`) and verify `kubectl exec deploy/superbox -- printenv HOME IS_SANDBOX PATH` prints
      them without a login shell
- [ ] 4.4 Add the readiness probe on `/work/.superbox-ready` and verify the pod is `0/1` while
      provisioning and `1/1` afterwards
- [ ] 4.5 Add the `configMapGenerator` for the bootstrap and helper scripts to
      `k8s/superbox/kustomization.yaml` with `disableNameSuffixHash: true`, and verify
      `kubectl apply -k k8s/` creates all SuperBox objects in the context's namespace with no
      `-n` argument
- [ ] 4.6 Confirm no Service selects the SuperBox and verify `kubectl get svc,ingress -o wide` shows no
      selector matching `app=superbox`

## 5. SuperBox bootstrap and helpers

- [ ] 5.1 Write `k8s/superbox/bootstrap.sh` reusing the DevBox pattern (markers under
      `/work/tools/.markers`, log to `/work/bootstrap.log`, per-step failure isolation, apt cache on the
      PVC) and verify a deliberately failing step logs `!!! FAILED` without aborting the run
- [ ] 5.2 Install the apt base packages (`tmux git curl jq ripgrep less tar gzip unzip ca-certificates
      procps openssl locales bash-completion`) with the `.deb` cache on the PVC and verify `tmux -V`,
      `git --version`, `jq --version` and `rg --version` all answer
- [ ] 5.3 Install Node.js LTS from the official tarball into `/work/tools/node` and verify
      `node --version` and `npm --version`
- [ ] 5.4 Install a `kubectl` client in the supported skew window for server 1.30 into
      `/work/tools/bin` and verify `kubectl version` reports client and server with no skew warning,
      and that `kubectl get pods` succeeds using only the in-cluster ServiceAccount token
- [ ] 5.5 Install `@anthropic-ai/claude-code` globally with the npm prefix on the PVC and verify
      `claude --version` answers through a non-interactive `kubectl exec`
- [ ] 5.6 Write the credential seed step — copy the mounted Secret into `$HOME/.claude` **only** when
      no credentials are present there — and verify that with credentials already on the PVC and a
      Secret also mounted, a restart leaves the PVC copy untouched (compare checksums before and after)
- [ ] 5.7 Write `/work/tools/bin/devbox-list` (enumerate `app.kubernetes.io/name=devbox` with instance
      name and readiness) and verify it lists the running DevBox
- [ ] 5.8 Write `/work/tools/bin/devbox-exec` (resolve by instance label, default to the sole match,
      exit non-zero listing the candidates when ambiguous, pass through exit status) and verify
      `devbox-exec -- mvn -v` runs Maven in the DevBox and that a fabricated ambiguous case prints the
      candidate names
- [ ] 5.9 Write `/work/tools/bin/devbox-cp` on the same resolver and verify a file copied into a DevBox
      arrives with its contents intact
- [ ] 5.10 Write `/work/tools/bin/superbox-creds` (`push`, `pull`, `status`) writing and reading
      Secret `superbox-claude-creds`, never printing secret material, and verify `status` reports
      presence/absence correctly and that `push` output contains no credential value
- [ ] 5.11 Write `/work/tools/tmux.conf` and a default session helper, write the readiness marker at the
      end of the bootstrap, and verify `kubectl exec deploy/superbox -- cat /work/bootstrap.log` ends
      with a version summary and that cold start completes in under 5 minutes

## 6. Bring-up and credentials

- [ ] 6.1 Attach with `kubectl exec -it deploy/superbox -- tmux new -As main` and verify a tmux status
      line appears and `tmux ls` inside the pod shows the session
- [ ] 6.2 Run `claude` in that session, complete `/login`, and verify `claude --version` and a trivial
      prompt both succeed
- [ ] 6.3 Run `superbox-creds push` and verify `kubectl get secret superbox-claude-creds` exists and
      that the Secret is not referenced by any committed file containing its value
- [ ] 6.4 Detach from tmux, close the `kubectl exec` connection, reattach, and verify the session and
      its scrollback are intact
- [ ] 6.5 Start a second session (`tmux new -As build`) and verify both sessions run concurrently and
      independently
- [ ] 6.6 Delete `$HOME/.claude` on the PVC, restart the pod, and verify the seed step restores
      credentials from the Secret and a session starts without a login
- [ ] 6.7 Enable remote control in the session and verify a prompt sent from the Claude app is executed
      in the cluster and its output appears in the attached session

## 7. Acceptance test driven from the SuperBox

- [ ] 7.1 From an agent session in the SuperBox, create a small application under `/shared/projects/`
      and verify the files are visible from the DevBox with `devbox-exec -- ls -la /shared/projects/...`
- [ ] 7.2 Build and test it with `devbox-exec -- ...` and verify the build runs inside the DevBox and
      the tests pass
- [ ] 7.3 Edit a source file from the SuperBox, rebuild in the DevBox without any copy step, and verify
      the new build reflects the edit
- [ ] 7.4 Overwrite a build artifact written by the DevBox from the SuperBox and verify no permission
      error occurs (uid parity across the shared volume)
- [ ] 7.5 Reach the DevBox's running application at `devbox.student-testc20.svc.cluster.local:8080` from
      the SuperBox with `curl` and verify it answers without an exec or a port-forward
- [ ] 7.6 Confirm the whole test was driven without a laptop-side `kubectl` beyond the initial attach,
      and verify by reviewing the session transcript

## 8. Documentation and follow-up

- [ ] 8.1 Write `k8s/superbox/README.md` (layout, attach/login/remote-control flow, helper commands,
      credential handling, reset) and verify every command in it runs as written
- [ ] 8.2 Update `k8s/README.md` for the new directory layout, the `/shared` mount and the DevBox
      restart note, and verify the paths it names exist
- [ ] 8.3 Update `CLAUDE.md` (SuperBox section, new `k8s/` layout, corrected manifest paths, SuperBox
      commands, cluster facts verified in this change) and verify it no longer points at
      `k8s/deployment.yaml`
- [ ] 8.4 Add `openspec/config.yaml` context for the now-decided stack and conventions, and verify
      `openspec instructions proposal --change add-superbox-deployment --json` shows the context
- [ ] 8.5 Sync `add-devbox-deployment`'s delta into `openspec/specs/` (its task 6.4) so this change's
      `devbox` delta has a base, then run `openspec validate --strict` and verify both changes pass

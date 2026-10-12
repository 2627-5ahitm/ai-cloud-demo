## Purpose

The SuperBox is the Claude agent's home inside the user's Kubernetes namespace: a long-lived pod where
the Claude CLI runs in yolo mode under tmux, authenticated once and reachable only through
`kubectl exec`, from which it drives one or more DevBoxes to build, test and deploy applications.

## ADDED Requirements

### Requirement: Always-reachable agent pod with no foreground workload

The SuperBox SHALL run as a single-replica Deployment whose container has no foreground workload, so
the pod stays Running and every unit of work arrives through `kubectl exec`. It MUST NOT require SSH,
an Ingress, or any inbound network path.

#### Scenario: Pod stays alive with no agent running

- **WHEN** the SuperBox is deployed and no Claude session has been started
- **THEN** the pod's status is `Running` with 0 restarts
- **AND** `kubectl exec deploy/superbox -- true` succeeds

#### Scenario: A crashing agent does not take the pod down

- **WHEN** a Claude session inside the SuperBox exits or crashes
- **THEN** the pod remains `Running`
- **AND** a new session can be started through a further `kubectl exec`

### Requirement: Concurrent, detachable agent sessions

The SuperBox SHALL host multiple independent agent sessions at the same time, and a session MUST
survive the loss of the `kubectl exec` connection that created it, so the user can detach, close the
laptop and reattach later. Sessions are not required to survive a pod restart.

#### Scenario: Reattaching to a running session

- **GIVEN** an agent session is running in the SuperBox
- **WHEN** the user's `kubectl exec` connection is closed and a new one is opened
- **THEN** the same session is still running and can be reattached
- **AND** the output produced while detached is still there

#### Scenario: Two sessions at once

- **WHEN** the user starts a second, differently named session
- **THEN** both sessions run simultaneously and independently
- **AND** each can be attached to and detached from without disturbing the other

### Requirement: Authenticated to Anthropic by an interactive login

The SuperBox SHALL let the user authenticate the Claude CLI once, interactively, through
`kubectl exec`. The resulting credentials SHALL persist across pod restarts and SHALL remain valid as
the CLI refreshes them, without requiring a new login after every restart.

#### Scenario: Login once, use after a restart

- **GIVEN** the user has completed an interactive login inside the SuperBox
- **WHEN** the pod is restarted
- **THEN** a new agent session starts without asking for a login
- **AND** the session can reach the Anthropic API

#### Scenario: Refreshed credentials are not lost

- **GIVEN** the CLI has refreshed its access token since the login
- **WHEN** the pod is restarted
- **THEN** the refreshed credentials are the ones in effect, not the ones captured at login time

### Requirement: Credentials held in a Kubernetes Secret, never in the repository

Credentials and other confidential values SHALL be stored in a Kubernetes Secret in the namespace. The
Secret's content MUST NOT be committed to the repository and MUST NOT be reconstructable from the
manifests. A SuperBox whose persistent state is empty SHALL be able to start from that Secret alone,
and the user SHALL be able to write the current credentials back into it on demand.

#### Scenario: Seeding a fresh workspace from the Secret

- **GIVEN** the credentials Secret exists and the SuperBox's persistent workspace holds no credentials
- **WHEN** the SuperBox starts
- **THEN** its credential state is seeded from the Secret
- **AND** an agent session starts without asking for a login

#### Scenario: Capturing the current credentials

- **WHEN** the user runs the SuperBox's credential-push command after a login
- **THEN** the Secret is created or updated with the current credentials
- **AND** the command reports which Secret it wrote, without printing the credentials

#### Scenario: No credentials in the repository

- **WHEN** the change's manifests are inspected
- **THEN** no credential value appears in any committed file
- **AND** a missing credentials Secret does not prevent the SuperBox from starting

#### Scenario: Existing credentials are not overwritten by the seed

- **GIVEN** the SuperBox's persistent workspace already holds credentials
- **WHEN** the pod restarts and a credentials Secret is also present
- **THEN** the persisted credentials are kept
- **AND** the Secret is not applied over them

### Requirement: Unattended operation without permission prompts

The SuperBox SHALL run the agent with tool-permission prompts disabled, so that work driven remotely
proceeds without someone at the terminal to approve each step.

#### Scenario: Agent runs without prompting

- **WHEN** an agent session is started in the SuperBox
- **THEN** it runs in its permission-skipping mode without refusing to start
- **AND** tool calls proceed without an interactive approval prompt

### Requirement: Remote control from the Claude app over an outbound connection only

Once a session is running, the user SHALL be able to drive it from the Claude app. That connection
MUST be established outbound from the pod; the SuperBox MUST NOT expose a Service, an Ingress or any
listening port for this purpose.

#### Scenario: Driving a session from the app

- **GIVEN** an authenticated agent session is running in the SuperBox with remote control enabled
- **WHEN** the user sends a prompt from the Claude app
- **THEN** the session in the cluster receives and acts on it
- **AND** its output is visible both in the app and in the attached session

#### Scenario: Nothing is exposed inbound

- **WHEN** the namespace's Services and Ingresses are listed
- **THEN** none of them selects the SuperBox pod

### Requirement: Least-privilege cluster identity

The SuperBox SHALL act against the Kubernetes API under its own identity, granted only the rights it
needs to drive DevBoxes: reading pods, deployments, services and pod logs, and creating exec and
port-forward connections. It MUST NOT be able to delete objects, and MUST NOT be able to read, modify
or delete PersistentVolumeClaims. Its access to Secrets MUST be limited to its own credentials Secret.

#### Scenario: Driving a DevBox is allowed

- **WHEN** the SuperBox lists pods and executes a command in a DevBox
- **THEN** both succeed without any credential beyond its own in-cluster identity

#### Scenario: Destructive actions are refused

- **WHEN** the SuperBox attempts to delete a Deployment, a pod or a PersistentVolumeClaim
- **THEN** the API rejects the attempt as forbidden

#### Scenario: Unrelated Secrets stay unreadable

- **WHEN** the SuperBox attempts to read a Secret other than its own credentials Secret
- **THEN** the API rejects the attempt as forbidden

#### Scenario: The user's own rights are not borrowed

- **WHEN** the SuperBox's filesystem and environment are inspected
- **THEN** they contain no copy of the user's kubeconfig or of a token belonging to another identity

### Requirement: DevBox discovery and driving

The SuperBox SHALL discover the DevBoxes present in the namespace by label and address a chosen one by
instance name, defaulting to the only one when exactly one exists. It SHALL run commands in a DevBox,
copy files to and from it, read its logs, and reach applications running in it over the in-cluster
Service, all without the user supplying connection details.

#### Scenario: Listing the available DevBoxes

- **WHEN** the agent asks the SuperBox which DevBoxes exist
- **THEN** it gets each DevBox's instance name and readiness

#### Scenario: Running a build in a DevBox

- **WHEN** the agent runs a build command against a DevBox from the SuperBox
- **THEN** the command executes inside that DevBox
- **AND** its output and exit status are returned to the caller

#### Scenario: Choosing between several DevBoxes

- **GIVEN** more than one DevBox exists in the namespace
- **WHEN** the agent runs a command without naming one
- **THEN** it is told that the target is ambiguous and which names it may choose from

#### Scenario: Testing an application running in a DevBox

- **GIVEN** an application is running inside a DevBox on its conventional port
- **WHEN** the SuperBox makes an HTTP request to that DevBox's in-cluster Service address
- **THEN** the application answers, without an exec or a port-forward

### Requirement: Shared project workspace with the DevBoxes

Project sources SHALL live on a volume that the SuperBox and the DevBoxes mount at the same path, so
the agent edits a file in the SuperBox and a build started in a DevBox sees that edit without any copy
step. Files written by either side MUST be readable and writable by the other.

#### Scenario: An edit is visible to the build without copying

- **WHEN** the agent changes a source file in the shared workspace from the SuperBox
- **AND** immediately starts a build in a DevBox against the same path
- **THEN** the build uses the changed file

#### Scenario: Build output is readable back in the SuperBox

- **GIVEN** a build in a DevBox has written artifacts into the shared workspace
- **WHEN** the agent reads and overwrites those files from the SuperBox
- **THEN** both succeed without a permission error

#### Scenario: Shared work survives a restart

- **WHEN** either pod is restarted
- **THEN** the shared project files are still present and unchanged

### Requirement: Toolchain provided inside the SuperBox

The SuperBox SHALL provide, on the latest stable Debian release, the Claude CLI, a terminal
multiplexer, a Kubernetes client compatible with the cluster's API server, and the tools needed to
work with source: git, curl, jq and a fast text search. It MUST NOT carry the DevBox's language
toolchains — building is the DevBox's job. Each tool MUST be executable by name without the caller
installing anything first.

#### Scenario: Every required tool reports its version

- **WHEN** the version of each provided tool is requested inside the SuperBox
- **THEN** each command succeeds and prints a version
- **AND** the operating system reported by `/etc/os-release` is the latest stable Debian release

#### Scenario: The Kubernetes client matches the server

- **WHEN** the client's version is compared with the cluster's API server version
- **THEN** the two are within the supported skew

#### Scenario: File transfer needs no extra service

- **WHEN** a directory is copied into the SuperBox with `kubectl cp`
- **THEN** the files appear with their contents intact

### Requirement: Tool environment available to non-interactive commands

Tool locations, the agent's home directory and the setting that permits unattended operation SHALL be
part of the container environment rather than of a shell profile, so a non-interactive
`kubectl exec ... -- <command>` finds everything without sourcing anything.

#### Scenario: Non-interactive exec finds the toolchain

- **WHEN** the Claude CLI's version is requested through a non-interactive `kubectl exec` with no
  login shell and no explicit sourcing
- **THEN** the command runs and prints a version

### Requirement: Idempotent, registry-free provisioning with a readiness signal

The SuperBox SHALL be created from a publicly available base image and provision itself, without a
container image build or a registry. Provisioning MUST be idempotent: a restart reuses everything
already present. The pod MUST report Ready only once it is usable, and provisioning progress MUST be
readable from inside the pod.

#### Scenario: First start provisions the SuperBox

- **WHEN** the SuperBox is applied with an empty persistent workspace
- **THEN** its tools are installed into that workspace
- **AND** no registry credentials or image push are required

#### Scenario: Restart skips completed work

- **GIVEN** the tools are already installed on the persistent volume
- **WHEN** the pod is restarted
- **THEN** the already-installed components are skipped
- **AND** the SuperBox becomes usable markedly faster than on the first start

#### Scenario: A failing install step does not block access

- **WHEN** one provisioning step fails
- **THEN** the remaining steps still run
- **AND** the pod stays reachable via `kubectl exec` so the failure can be diagnosed from its log

#### Scenario: Waiting for readiness yields a usable SuperBox

- **WHEN** a caller waits for the SuperBox pod to become Ready
- **THEN** the wait returns only after provisioning has finished
- **AND** an agent session can be started at that point

### Requirement: Coexists with the DevBoxes in the same namespace

The SuperBox SHALL deploy into the namespace of the active kubeconfig context, without creating or
switching namespaces and without hard-coding a namespace in its manifests. Its object names and label
selectors MUST NOT collide with any DevBox's, and it MUST satisfy the namespace's PodSecurity level
without privileged containers or host mounts.

#### Scenario: Applying uses the context's namespace

- **WHEN** the manifests are applied without a namespace argument
- **THEN** all resources are created in the namespace of the active context
- **AND** no namespace is created, switched or referenced by name in the manifests

#### Scenario: No selector collision

- **WHEN** the SuperBox and the DevBoxes are deployed together
- **THEN** no Service or Deployment selector matches a pod of the other kind

#### Scenario: Admission accepts the pod

- **WHEN** the pod is admitted under the namespace's PodSecurity level
- **THEN** it is accepted without warnings about privileged mode or host access

### Requirement: Verified by an end-to-end acceptance test

The SuperBox SHALL be demonstrated by an acceptance test driven from inside it: an agent session that,
without the user touching the DevBox directly, creates an application in the shared workspace, builds
and tests it in a DevBox, and reports the result.

#### Scenario: The agent builds and tests an application through a DevBox

- **GIVEN** an authenticated agent session is running in the SuperBox
- **WHEN** it is asked to create, build and test an application
- **THEN** the sources are created in the shared workspace
- **AND** the build and the tests run inside a DevBox and pass
- **AND** no `kubectl` command was issued from the user's laptop other than the one that attached to
  the session

#### Scenario: The session survives the laptop going away

- **GIVEN** the agent is working on a long-running task
- **WHEN** the user detaches and closes the laptop
- **THEN** the task continues in the cluster
- **AND** its result is there when the user reattaches

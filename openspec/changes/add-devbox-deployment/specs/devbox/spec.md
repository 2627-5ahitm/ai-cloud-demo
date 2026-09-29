## Purpose

The DevBox is a long-lived remote development environment in the user's Kubernetes namespace that an
AI agent drives entirely through `kubectl exec` and `kubectl cp`, so building, testing and deploying
projects happens in the cloud instead of on the user's laptop.

## ADDED Requirements

### Requirement: Always-reachable pod with no foreground workload

The DevBox SHALL run as a single-replica Deployment whose container has no foreground workload, so the
pod stays Running and every unit of work arrives through `kubectl exec`. The pod MUST NOT require SSH
or an Ingress for the development loop.

#### Scenario: Pod stays alive without any work

- **WHEN** the DevBox is deployed and no command has been executed against it
- **THEN** the pod's status is `Running` with 0 restarts
- **AND** `kubectl exec deploy/devbox -- true` succeeds

#### Scenario: Command failure does not take the pod down

- **WHEN** a command executed inside the DevBox exits non-zero or crashes
- **THEN** the pod remains `Running`
- **AND** further `kubectl exec` calls still succeed

### Requirement: Toolchain provided inside the DevBox

The DevBox SHALL provide, on the latest stable Debian release, a JavaScript runtime (Node.js LTS with
npm), a Java runtime and build system able to build Quarkus applications (JDK 21 LTS, Maven, Quarkus
CLI), and the tools Playwright (with a working Chromium), httpyac and curl. Each tool MUST be
executable by name without the caller installing anything first.

#### Scenario: Every required tool reports its version

- **WHEN** the agent runs `node --version`, `npm --version`, `java -version`, `mvn -v`,
  `quarkus --version`, `httpyac --version`, `playwright --version` and `curl --version` inside the
  DevBox
- **THEN** each command succeeds and prints a version
- **AND** the operating system reported by `/etc/os-release` is the latest stable Debian release

#### Scenario: Chromium can actually be launched

- **WHEN** a Playwright test runs headless Chromium inside the DevBox
- **THEN** the browser starts and the test executes
- **AND** no browser download is triggered, because the browsers are already present

### Requirement: Tool environment available to non-interactive commands

Tool locations SHALL be part of the container environment rather than of a shell profile, so a
non-interactive `kubectl exec ... -- <command>` finds every tool without sourcing anything.

#### Scenario: Non-interactive exec finds the toolchain

- **WHEN** the agent runs `kubectl exec deploy/devbox -- mvn -v` (no login shell, no `-l`, no
  `source`)
- **THEN** Maven runs and reports the JDK it uses
- **AND** `JAVA_HOME` points at the installed JDK

### Requirement: Persistent workspace and caches

Project sources and build caches SHALL live on a persistent volume so they survive pod restarts and
rescheduling. Persisted state MUST include the projects directory, the installed toolchain, the Maven
local repository, the npm cache and the Playwright browsers.

#### Scenario: Projects survive a restart

- **GIVEN** a project directory exists in the DevBox workspace
- **WHEN** the pod is restarted
- **THEN** the project directory and its build output are still present

#### Scenario: Dependencies are not downloaded twice

- **GIVEN** a Maven build has already resolved its dependencies
- **WHEN** the pod is restarted and the build runs again
- **THEN** the dependencies are taken from the persisted local repository instead of being downloaded
  again

### Requirement: Idempotent, registry-free provisioning

The DevBox SHALL be created from a publicly available base image and provision its toolchain itself,
without requiring a container image build or a container registry. Provisioning MUST be idempotent: a
restart reuses everything already present and MUST NOT redo completed installation work.

#### Scenario: First start provisions the toolchain

- **WHEN** the DevBox is applied to an empty namespace
- **THEN** the toolchain is installed into the persistent volume
- **AND** no registry credentials or image push are required

#### Scenario: Restart skips completed work

- **GIVEN** the toolchain is already installed on the persistent volume
- **WHEN** the pod is restarted
- **THEN** the already-installed components are skipped
- **AND** the DevBox becomes usable markedly faster than on the first start

#### Scenario: A failing install step does not block access

- **WHEN** one provisioning step fails (for example a download is unavailable)
- **THEN** the remaining steps still run
- **AND** the pod stays reachable via `kubectl exec` so the failure can be diagnosed from its log

### Requirement: Readiness signals that the DevBox is usable

The DevBox SHALL report Ready only once its toolchain is installed, so a caller can wait for
"usable" rather than merely "scheduled". Provisioning progress MUST be readable from inside the pod.

#### Scenario: Waiting for readiness yields a usable DevBox

- **WHEN** a caller waits for the DevBox pod to become Ready
- **THEN** the wait returns only after provisioning has finished
- **AND** every tool of the toolchain requirement is executable at that point

#### Scenario: Progress is observable while provisioning

- **WHEN** the DevBox is still provisioning
- **THEN** a log of the provisioning steps and their outcome can be read from the pod

### Requirement: File transfer between laptop and DevBox

The DevBox SHALL accept files copied in and out with `kubectl cp`, into and out of the persistent
workspace, without any additional service.

#### Scenario: Copy sources in and artifacts out

- **WHEN** the agent copies a directory into the DevBox workspace with `kubectl cp`
- **THEN** the files appear in the workspace with their contents intact
- **AND** build artifacts produced inside the DevBox can be copied back out the same way

### Requirement: Applications under test are reachable

Applications started inside the DevBox SHALL be reachable for testing, both from within the DevBox
itself and, for a backend/frontend pair, from another process in the same pod. The conventional ports
are 8080 for a Java/Quarkus backend and 3000 for a Node.js frontend, exposed in-cluster by a Service.

#### Scenario: Backend and frontend talk to each other

- **GIVEN** a backend runs on port 8080 and a frontend on port 3000 inside the DevBox
- **WHEN** an HTTP test calls the frontend
- **THEN** the frontend's response reflects data it fetched from the backend

#### Scenario: Reaching an app from the laptop

- **WHEN** the user port-forwards a DevBox port
- **THEN** the application answers on the forwarded local port

### Requirement: Stays inside the user's namespace and security policy

The DevBox SHALL deploy into the namespace of the active kubeconfig context, without creating or
switching namespaces and without hard-coding a namespace in its manifests. It MUST satisfy the
namespace's PodSecurity level and MUST NOT require privileged containers or host mounts.

#### Scenario: Applying uses the context's namespace

- **WHEN** the manifests are applied without a namespace argument
- **THEN** all resources are created in the namespace of the active context
- **AND** no namespace is created, switched or referenced by name in the manifests

#### Scenario: Admission accepts the pod

- **WHEN** the pod is admitted under the namespace's PodSecurity level
- **THEN** it is accepted without warnings about privileged mode or host access

### Requirement: Verified by an end-to-end acceptance test

The DevBox SHALL be demonstrated by an acceptance test carried out inside it: a Quarkus application
that is created, built, unit-tested and exercised with httpyac, and a Node.js application that calls
that Quarkus backend and is exercised with httpyac and Playwright.

#### Scenario: Quarkus application builds and passes its HTTP tests

- **WHEN** a Quarkus demo application is created and built inside the DevBox
- **THEN** its unit tests pass
- **AND** an httpyac suite against its running REST endpoints passes every request and assertion

#### Scenario: Node.js application consumes the Quarkus backend

- **GIVEN** the Quarkus backend is running inside the DevBox
- **WHEN** a Node.js application that calls that backend is started inside the DevBox
- **THEN** an httpyac suite against the Node.js endpoints passes, with responses containing data
  obtained from the backend
- **AND** a Playwright test against the Node.js page renders the backend's data in a headless browser

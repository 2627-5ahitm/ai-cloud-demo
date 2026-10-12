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
rescheduling. Persisted state MUST include the projects directory, the Maven local repository and the
npm cache. The volume claim MUST request no more than the platform's per-claim maximum (20Gi on
LeoCloud). The toolchain lives in the image, not on the volume.

#### Scenario: Projects survive a restart

- **GIVEN** a project directory exists in the DevBox workspace
- **WHEN** the pod is restarted
- **THEN** the project directory and its build output are still present

#### Scenario: Dependencies are not downloaded twice

- **GIVEN** a Maven build has already resolved its dependencies
- **WHEN** the pod is restarted and the build runs again
- **THEN** the dependencies are taken from the persisted local repository instead of being downloaded
  again

### Requirement: Toolchain shipped as a prebuilt image

The DevBox SHALL run from a container image that is built from this repository (`image/Dockerfile`)
for `linux/amd64`, contains the whole toolchain, and is pushed to a container registry (ghcr.io)
under a new tag for every build. The pod MUST NOT install the toolchain at start-up, and MUST NOT run
a public base image with provisioning scripts injected via ConfigMap.

#### Scenario: Fresh deployment is usable without provisioning

- **WHEN** the DevBox is applied to an empty namespace with an empty volume
- **THEN** every tool of the toolchain requirement is executable as soon as the pod is Ready
- **AND** nothing is downloaded or installed into the volume at start-up

#### Scenario: Restart is as fast as the image pull

- **GIVEN** the image is already present on the node
- **WHEN** the pod is restarted
- **THEN** the DevBox becomes Ready within seconds and the workspace volume is unchanged

#### Scenario: A toolchain update is a new image tag

- **WHEN** a tool version is changed in the Dockerfile
- **THEN** a new image is built and pushed under a new tag and the manifests reference that tag
- **AND** applying the manifests rolls the pod onto the new image

### Requirement: Readiness signals that the DevBox is usable

The DevBox SHALL report Ready only once its workspace directories on the volume exist, so a caller
can wait for "usable" rather than merely "scheduled".

#### Scenario: Waiting for readiness yields a usable DevBox

- **WHEN** a caller waits for the DevBox pod to become Ready
- **THEN** the wait returns only after the workspace (`/work/projects`, Maven repository, npm cache)
  is initialised
- **AND** every tool of the toolchain requirement is executable at that point

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
namespace's PodSecurity level and MUST NOT require privileged containers or host mounts. It MUST keep
the platform's storage limits: a volume claim of at most 20Gi, and an explicit `ephemeral-storage`
request and limit for the container that stays within the per-container (20Gi) and per-namespace
(40Gi) maximum. Services MUST be of type ClusterIP.

#### Scenario: Applying uses the context's namespace

- **WHEN** the manifests are applied without a namespace argument
- **THEN** all resources are created in the namespace of the active context
- **AND** no namespace is created, switched or referenced by name in the manifests

#### Scenario: Admission accepts the pod

- **WHEN** the pod is admitted under the namespace's PodSecurity level
- **THEN** it is accepted without warnings about privileged mode or host access

#### Scenario: Admission accepts the storage requests

- **WHEN** the volume claim and the Deployment are applied
- **THEN** the claim is bound and the pod is created without a refusal naming the claim size or the
  `leocloud-node-disk` quota

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

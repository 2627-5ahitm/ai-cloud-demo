## MODIFIED Requirements

### Requirement: Persistent workspace and caches

Project sources and build caches SHALL live on a persistent volume so they survive pod restarts and
rescheduling. Persisted state MUST include the projects directory, the installed toolchain, the Maven
local repository, the npm cache and the Playwright browsers.

In addition, the DevBox SHALL mount a shared project workspace that is writable by more than one pod
at a time, at a well-known path, so an agent running in another pod can edit sources that a build in
this DevBox then compiles without any copy step. Files written into the shared workspace by the DevBox
MUST be readable and writable by the other mounting pods, and vice versa. The DevBox's own private
workspace and its caches remain separate from the shared one.

#### Scenario: Projects survive a restart

- **GIVEN** a project directory exists in the DevBox workspace
- **WHEN** the pod is restarted
- **THEN** the project directory and its build output are still present

#### Scenario: Dependencies are not downloaded twice

- **GIVEN** a Maven build has already resolved its dependencies
- **WHEN** the pod is restarted and the build runs again
- **THEN** the dependencies are taken from the persisted local repository instead of being downloaded
  again

#### Scenario: A build sees an edit made from another pod

- **GIVEN** a source file in the shared workspace was changed from another pod
- **WHEN** a build is started in the DevBox against that path
- **THEN** the build uses the changed file, with no copy step in between

#### Scenario: Build output is writable by the other side

- **GIVEN** a build in the DevBox has written artifacts into the shared workspace
- **WHEN** another pod mounting the same workspace reads and overwrites those files
- **THEN** both succeed without a permission error

#### Scenario: The private workspace is unaffected

- **WHEN** the shared workspace is unavailable or empty
- **THEN** the DevBox's toolchain, Maven repository and existing projects in its private workspace are
  still present and usable

## ADDED Requirements

### Requirement: Addressable as one of several DevBoxes

Every DevBox SHALL carry labels that identify it as a DevBox and distinguish it from any other DevBox
in the namespace, so a caller can enumerate the DevBoxes present and select one by instance name
rather than by pod name. The labels MUST be stable across pod restarts and rescheduling, and adding a
second DevBox MUST NOT make an existing Service or Deployment select the wrong pod.

#### Scenario: Enumerating the DevBoxes

- **WHEN** the DevBoxes in the namespace are listed by their common label
- **THEN** every DevBox appears exactly once, each with its own instance name

#### Scenario: Selecting one DevBox by name

- **GIVEN** more than one DevBox exists
- **WHEN** a caller selects a DevBox by its instance name
- **THEN** exactly one pod is resolved

#### Scenario: A second DevBox does not hijack the first one's Service

- **WHEN** a second DevBox is deployed alongside the first
- **THEN** each DevBox's Service routes only to its own pod

#### Scenario: Labels survive a restart

- **WHEN** a DevBox pod is replaced by a restart or rescheduling
- **THEN** the new pod carries the same identifying and instance labels

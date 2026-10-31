# Swift Package Test Workflow Architecture

## Goals

The Swift Package Test workflow is intended to give maintainers of open-source Swift packages a low-friction way to give contributors confidence in the code they write. This means making testing against a range of Swift versions and platforms as simple as possible, and making the results as accessible as possible.

To move an existing repository onto these workflows, see [the migration guide](migration.md).

The following key features are treated as requirements by the unified architecture.

### 1. GitHub-release-based versioning

Workflows and actions must be versioned using GitHub releases to guarantee stability to adopters. Properly tagged SemVer will allow even breaking changes to be rolled out safely. This method of versioning also lets adopters use Dependabot to automatically open PRs which bump their pinned references.

### 2. No skipped jobs

No reusable workflow offered should show skipped jobs. Skipped jobs add visual noise, look confusing to contributors and imply that something is configured incorrectly.

### 3. Scripts must be cloned not curled

Some jobs rely on scripts to execute their functionality. This is often preferred over inline scripts in the workflow definition `yml` files since it gives a better developer experience to the maintainers of those scripts. However, one downside of this approach is that these scripts are not present when a reusable workflow is executed from another repository. It is important that a unified solution checks the scripts out explicitly rather than curling them, since curling frequently runs into rate limiting with GitHub's API.

### 4. Custom matrix builds

Some packages need additional checks, such as their own integration tests or a custom script. Those checks often need the same matrix of builds that the recommended test workflow, `package_test.yml`, uses. Hence, a unified solution should offer lower level primitives that can execute a matrix. Furthermore, it should provide a workflow with a matrix that is already configured with the recommended Swift versions and platforms that just executes a command across them. The [migration guide](migration.md#customization-calling-execute_matrixyml-directly) has worked examples.

### 5. Detect minimum version

Any matrix that is generated should take the tools-version of the package manifest into consideration to automatically remove unsupported Swift versions. This matters most for newly released packages, which often support only the latest Swift version.

## High level design

Provide one workflow which can be adopted to run a range of common test and build configurations on a variety of platforms against multiple Swift versions. This workflow sits atop a "matrix generation" layer which takes inputs and produces a canonical work definition (in YAML or JSON). That definition is then expanded into one job per entry, each executing one slice of the work. Benchmarking is a further consumer of the same layer rather than part of the recommended test workflow.

The design is intended to be layered, so that adopters may use the whole stack or, where the top-level workflow does not offer the customization they need, drop down a level and supply that part themselves:

* Use the `package_test.yml` workflow for the full suite of conveniences
* Use a custom workflow (perhaps with custom inputs) which calls `toolchain_matrix.yml` for the matrix and `execute_matrix.yml` to run its own command across it
* Generate the work definition in YAML or JSON by some other means, or hard-code it into a workflow, and pass it to `execute_matrix.yml`

## Components of the design

* `package_test.yml`: top-level workflow for the full suite of conveniences
* `benchmarks.yml`: top-level workflow for benchmarking, consuming the same matrix layer
* `toolchain_matrix.yml`: produces a matrix of toolchains with no command attached, for callers supplying their own
* `execute_matrix.yml`: expands a work definition into one job per entry and dispatches each to its platform. FreeBSD runs in a VM step here rather than through a job runner
* `generate-matrix.swift`: produces the canonical work definition YAML or JSON. It reads the workflow's inputs from the environment and fails the run rather than emitting a matrix that would silently drop a job the caller asked for
* `job-runner-linux.sh`, `job-runner-macos.sh`, `job-runner-windows.ps1`: helper scripts which execute the defined work. They handle the complexity of running inside/outside Docker and installing Swift if required.

## Swift version labels

A version list names toolchains with labels: a version such as `6.3`, `nightly-release`, `nightly-main`, or a position counted back from the current release, `current`, `current-1` and `current-2`. A job's name carries the label the caller wrote. Job names are required status checks, so the default lists use the relative labels: a new Swift release changes which versions they name and leaves the checks alone. A caller who writes versions out gets those names, and the two spellings can be mixed in one list.

The workflow supplies what the relative labels resolve against, in `swift_current_release` and `swift_nightly_release`. They are inputs with defaults in the workflow files rather than values in the generator, so a workflow pinned to a release tag keeps the versions it was released with. Setting `swift_current_release` holds a repository at an earlier release without changing its check names.

## The matrix definition

`execute_matrix.yml` takes the work definition as a YAML string (JSON is valid YAML, so a JSON document works too) in `matrix_yaml_string`. `generate-matrix.swift` writes it, and a caller can write it by hand or generate it some other way. It is a map with one key, `config`, holding a list of entries. Each entry becomes one job, named by its `name`. An empty list is valid and runs no jobs. A missing or non-list `config`, an unknown `platform`, or an entry left with no `command` fails before any job starts.

Fields every entry carries:

| Field | Type | Meaning |
| --- | --- | --- |
| `platform` | `Linux`, `macOS`, `Windows` or `FreeBSD` | Which runner script the job dispatches to. |
| `name` | string | The job name, which is also the status check name. |
| `runner` | list of strings | The `runs-on` labels. |
| `command` | string | The command to run. An entry that omits it takes `execute_matrix.yml`'s `command` input. |
| `setup_command` | string | Run before the command. Defaults to the `setup_command` input. |
| `command_arguments` | list of strings | Appended to the command. Defaults to the `command_arguments` input. |
| `timeout_minutes` | number | The job's timeout. An entry that omits it takes `execute_matrix.yml`'s `job_timeout` input. |
| `env` | map | Environment variables for the job. The `env` input supplies defaults and an entry's own keys win. |

The toolchain is described by one further key, by platform:

* **Linux and Windows** use `swift_build`:
  * `swift_version` is the label, such as `6.3`, `nightly-release` or `nightly-main`. It is the only required key.
  * `toolchain` and `swiftly` are the resolved forms of a nightly (for example `nightly-6.4.x` and `6.4.x-snapshot`). Leave them out for a release.
  * `container` (`image`, and optionally `dockerfile`, `capabilities`, `security_options`) runs the job in a Docker container. Leave it out to run on the runner.
  * `sdk` (`type`, one of `static-linux`, `wasm`, `embedded-wasm`, `android`; plus `triples` and, for Android, `ndk_version`) installs a Swift SDK and runs the command as the build with it. An entry cannot carry both `sdk` and `container`.
* **macOS** uses `xcode_build`:
  * `swift_version` or `xcode_version` selects the Xcode, and `swiftly_toolchain` adds a swiftly-managed toolchain under it.
  * `targets` is a list of `platform`, `scheme`, `build_destination`, `test_destination`, `build` and `test`, for building and testing on simulators.
  * `debug_output` prints the `xcodebuild` output.
* **FreeBSD** uses `freebsd`: `os_version`, `swift_version`, `swift_url`, `build_flags` and `env_vars`.

Linux entries may also set `android_emulator: true` to run the Android emulator tests after an Android SDK build.

For example, one release and one nightly on Linux:

```yaml
config:
  - name: Linux Swift 6.3
    platform: Linux
    runner: [ubuntu-latest]
    command: swift test
    swift_build:
      swift_version: "6.3"
  - name: Linux Swift nightly-release
    platform: Linux
    runner: [ubuntu-latest]
    command: swift test
    swift_build:
      swift_version: nightly-release
      toolchain: nightly-6.4.x
      swiftly: 6.4.x-snapshot
```

The shortest way to see every field a platform takes is to run `swift generate-matrix.swift` with the relevant `ENABLE_*` variable set and read its output.

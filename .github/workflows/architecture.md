# Swift Package Test Workflow Architecture

## Aims

The Swift Package Test workflow is intended to give maintainers of open-source Swift packages a low-friction way to give contributors confidence in the code they write. This means making testing against a range of Swift versions and platforms as simple as possible, and making the results as accessible as possible.

This workflow builds on the GitHub Actions workflows from [apple/swift-nio](https://github.com/apple/swift-nio/tree/main/.github/workflows) and [swiftlang/github-workflows](https://github.com/swiftlang/github-workflows/tree/main/.github/workflows), taking from both repositories the key features listed below, which the unified architecture treats as requirements.

### 1. GitHub-release-based versioning

Workflows and actions must be versioned using GitHub releases to guarantee stability to adopters. Properly tagged SemVer will allow even breaking changes to be rolled out safely. This method of versioning also lets adopters use Dependabot to automatically open PRs which bump their pinned references.

### 2. No skipped jobs

No reusable workflow offered should show skipped jobs. Skipped jobs add visual noise, look confusing to contributors and imply that something is configured incorrectly.

### 3. Scripts must be cloned not curled

Some jobs rely on scripts to execute their functionality. This is often preferred over inline scripts in the workflow definition `yml` files since it gives a better developer experience to the maintainers of those scripts. However, one downside of this approach is that these scripts are not present when a reusable workflow is executed from another repository. It is important that a unified solution checks the scripts out explicitly rather than curling them, since curling frequently runs into rate limiting with GitHub's API.

### 4. Custom matrix builds

Some packages need additional checks, such as their own integration tests or a custom script. Those checks often need the same matrix of builds that the recommended test workflow, `package_test.yml`, uses. Hence, a unified solution should offer lower level primitives that can execute a matrix. Furthermore, it should provide a workflow with a matrix that is already configured with the recommended Swift versions and platforms that just executes a command across them.

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


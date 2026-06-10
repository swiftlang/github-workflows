# Documentation Check

The Soundness workflow can verify that your Swift package's [DocC](https://www.swift.org/documentation/docc/) documentation builds without warnings. Two jobs are available:

- **`docs-check`** — runs on Linux. Enabled by default.
- **`docs-check-macos`** — runs on a self-hosted macOS runner. Opt-in.

Running both lets you catch documentation issues that only surface on one toolchain.

Documentation warnings (and, by default, DocC analyzer findings) cause the job to fail.

## Requirements

### For both jobs

1. **A `Package.swift`** (or any `Package*.swift`) at the repository root.

2. **At least one documentation target**, supplied via either:
   - the `docs_check_targets` / `docs_check_macos_targets` input, **or**
   - a `documentation_targets` entry in a `.spi.yml` file at the repository root.

   If neither is provided, the job exits successfully without checking anything.

The `.spi.yml` file is also where you can declare per-target DocC parameters via `custom_documentation_parameters`. Read the [official documentation](https://swiftpackageindex.com/SwiftPackageIndex/SPIManifest/1.12.0/documentation/spimanifest/commonusecases) for the full schema. For example:

```yaml
version: 1
builder:
  configs:
    - documentation_targets: [MyLibrary, MyOtherLibrary]
      custom_documentation_parameters:
        - --include-extended-types
```

Target names must match real SwiftPM target names declared in `Package.swift`.

You do not need to add `swift-docc-plugin` to your package — CI provides it for you.

### Additional requirement for the macOS job

A self-hosted runner must be registered with the label set `[self-hosted, macos, <version>, <arch>]` matching the values you pass to `docs_check_macos_version` and `docs_check_macos_arch`, with the requested Xcode version installed.

## Enabling the check

Add (or extend) a workflow file under `.github/workflows/` in your repository:

```yaml
name: Pull request

on:
  pull_request:
    branches: [main]

jobs:
  soundness:
    name: Soundness
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@<to-be-updated>>
    with:
      docs_check_enabled: true
```

This enables the Linux documentation check along with the other soundness checks. The macOS variant remains off unless you opt in.

## Configuration

### Linux job (`docs-check`)

| Input | Type | Default | Description |
|---|---|---|---|
| `docs_check_enabled` | boolean | `true` | Enable or disable the job. |
| `docs_check_container_image` | string | `swift:6.2-noble` | Docker image used to run the check. |
| `docs_check_targets` | string | `""` | Space-separated list of documentation targets to check. When empty, targets are read from `.spi.yml` (if present). |
| `docs_check_additional_arguments` | string | `""` | Extra arguments to pass to DocC. |
| `docs_check_analyze` | boolean | `true` | Set to `false` to skip DocC's analyzer pass. |
| `linux_pre_build_command` | string | `""` | Shell command to run before the check (e.g., installing system dependencies). |

### macOS job (`docs-check-macos`)

| Input | Type | Default | Description |
|---|---|---|---|
| `docs_check_macos_enabled` | boolean | `false` | Enable or disable the job. |
| `docs_check_macos_version` | string | `tahoe` | macOS version label of the runner to target. |
| `docs_check_macos_arch` | string | `ARM64` | Architecture label of the runner to target. |
| `docs_check_macos_xcode_version` | string | `26.0` | Xcode version to use. |
| `docs_check_macos_targets` | string | `""` | Space-separated list of documentation targets to check. When empty, targets are read from `.spi.yml` (if present). |
| `docs_check_macos_additional_arguments` | string | `""` | Extra arguments to pass to DocC. |
| `docs_check_macos_analyze` | boolean | `true` | Set to `false` to skip DocC's analyzer pass. |

The macOS job requires a self-hosted runner registered with the label set `[self-hosted, macos, <version>, <arch>]`.

## Common scenarios

### Enable the macOS check

```yaml
jobs:
  soundness:
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@main
    with:
      docs_check_macos_enabled: true
      docs_check_macos_version: "tahoe"
      docs_check_macos_arch: "ARM64"
      docs_check_macos_xcode_version: "26.0"
```

### Check only specific targets

By default the check documents every target listed in `.spi.yml`. To override that list without editing `.spi.yml`, provide the target names explicitly:

```yaml
jobs:
  soundness:
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@main
    with:
      docs_check_targets: "MyLibrary MyOtherLibrary"
```

### Pin a different Swift toolchain or pass extra DocC flags

```yaml
jobs:
  soundness:
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@main
    with:
      docs_check_container_image: "swift:nightly-noble"
      docs_check_additional_arguments: "--include-extended-types"
      linux_pre_build_command: "apt-get update && apt-get install -y libxml2-dev"
```

### Skip the DocC analyzer

```yaml
jobs:
  soundness:
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@main
    with:
      docs_check_analyze: false
```

### Disable the check

If you want to skip the documentation check entirely (regardless of whether your package has documentation targets), turn it off:

```yaml
jobs:
  soundness:
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@main
    with:
      docs_check_enabled: false
```

If you simply have no documentation targets to check, you can leave the job enabled — it will exit successfully without doing anything.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Job logs `No '.spi.yml' found, no documentation targets to check.` and exits successfully. | Neither `docs_check_targets` nor a `.spi.yml` was provided. Add one of them if you expected the check to run. |
| `Package.swift not found.` | The check expects a SwiftPM package at the repo root. |
| Warnings cause the job to fail. | Intentional. Resolve the DocC warnings, or pass DocC flags via `.spi.yml`'s `custom_documentation_parameters` to suppress them. |
| macOS job stays queued. | No self-hosted runner matches the requested labels. Verify the `version` and `arch` inputs against your runner inventory. |
| macOS job cannot find Xcode. | The requested Xcode version is not installed on the runner. |

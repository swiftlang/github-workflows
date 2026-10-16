# API Breakage Check

The Soundness workflow can verify that a change to your Swift package does not introduce source-breaking changes to its public API. The **`api-breakage-check`** job runs on Linux, is enabled by default, and wraps [`swift package diagnose-api-breaking-changes`](https://github.com/swiftlang/swift-package-manager).

The job fails when the command reports API breakages that are not covered by an allowlist.

## How it works

1. Checks out the repository with full history, tags, and submodules (`fetch-depth: 0`, `fetch-tags: true`). Credentials are persisted because `diagnose-api-breaking-changes` clones the repository again, which would otherwise fail for private repositories.
2. Marks the workspace as a safe git directory.
3. Runs `linux_pre_build_command`, if provided.
4. Determines the **baseline** to compare against:
   - if `api_breakage_check_baseline` is set, that tag or ref is used;
   - otherwise the pull request's base branch (`GITHUB_BASE_REF`) is fetched into a local `pull-base-ref` ref and used.
5. Runs `swift package diagnose-api-breaking-changes <baseline>`, adding `--breakage-allowlist-path <path>` when `api_breakage_check_allowlist_path` is set, followed by any `api_breakage_check_additional_tool_arguments`.

The job has a 40 minute timeout.

## Requirements

1. **A SwiftPM package** with a `Package.swift` at the repository root.
2. **At least one library product** whose public API can be compared.
3. **A `pull_request` trigger**, unless you set `api_breakage_check_baseline`. The default baseline relies on `GITHUB_BASE_REF`, which GitHub only sets for pull request events.

## Enabling the check

The check is on by default, so calling the Soundness workflow is enough:

```yaml
name: Pull request

on:
  pull_request:
    branches: [main]

jobs:
  soundness:
    name: Soundness
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@main
```

## Configuration

| Input | Type | Default | Description |
|---|---|---|---|
| `api_breakage_check_enabled` | boolean | `true` | Enable or disable the job. |
| `api_breakage_check_allowlist_path` | string | `""` | Path to a file passed as `--breakage-allowlist-path`. Relative paths are resolved from the repository root. |
| `api_breakage_check_baseline` | string | `""` | Tag or ref to compare against. When empty, the pull request's base branch is used. |
| `api_breakage_check_container_image` | string | `swift:6.3-noble` | Docker image used to run the check. |
| `api_breakage_check_additional_tool_arguments` | string | `""` | Extra arguments appended to the `swift package diagnose-api-breaking-changes` invocation. |
| `linux_pre_build_command` | string | `""` | Shell command to run before the check (e.g., installing system dependencies). Shared with other Soundness jobs. |

## Common scenarios

### Compare against a release tag

Useful for catching breakages relative to the last release rather than the PR base:

```yaml
jobs:
  soundness:
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@main
    with:
      api_breakage_check_baseline: "1.2.0"
```

### Allow known breakages

Create an allowlist file listing the breakages you intend to accept (one per line, in the format emitted by the tool) and point the job at it:

```yaml
jobs:
  soundness:
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@main
    with:
      api_breakage_check_allowlist_path: ".github/api-breakage-allowlist.txt"
```

### Pass additional arguments to the tool

Arguments are appended verbatim, so any flag supported by `swift package diagnose-api-breaking-changes` can be used. For example, to check only specific products:

```yaml
jobs:
  soundness:
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@main
    with:
      api_breakage_check_additional_tool_arguments: "--products MyLibrary"
```

The value is word-split by the shell, so it cannot contain arguments with embedded spaces.

### Use a different Swift toolchain or install dependencies

```yaml
jobs:
  soundness:
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@main
    with:
      api_breakage_check_container_image: "swift:nightly-noble"
      linux_pre_build_command: "apt-get update && apt-get install -y libxml2-dev"
```

### Disable the check

Packages that expose no public API (for example, executables only) can turn the job off:

```yaml
jobs:
  soundness:
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@main
    with:
      api_breakage_check_enabled: false
```

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `git fetch` fails with an empty ref name, or the baseline cannot be resolved. | The workflow was not triggered by a `pull_request` event, so `GITHUB_BASE_REF` is empty. Set `api_breakage_check_baseline` or trigger the workflow on `pull_request`. |
| The baseline tag is not found. | The tag does not exist in the repository. Tags are fetched by the checkout step, so confirm the name matches exactly. |
| Job fails on a breakage you intend to make. | Add the reported breakage to the allowlist file referenced by `api_breakage_check_allowlist_path`. |
| Allowlist file is not found. | The path is resolved from the repository root, not from the workflow file's location. |
| Build fails before the comparison runs. | A system dependency is missing. Install it with `linux_pre_build_command`. |
| Job fails to clone the repository (private repositories). | The checkout step must persist credentials. The workflow already does this, so check that the calling workflow grants `contents: read`. |

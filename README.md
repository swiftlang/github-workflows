# GitHub Actions Workflows

This repository will contain reusable workflows to minimize redundant workflows
across the organization. This effort will also facilitate the standardization of
testing processes while empowering repository code owners to customize their
testing plans as needed. The repository will contain workflows to support
different types of repositories, such as Swift Package and Swift Compiler.

For more details on reusable workflows, please refer to the [Reusing
workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows)
section in the GitHub Docs.

## Reusable workflow for Swift package repositories

There are different kinds of workflows that this repository offers:

### Soundness

The soundness workflows provides a multitude of checks to ensure a repository is
following the best practices. By default each check is enabled but can be
disabled by passing the appropriate workflow input. We recommend to adopt all
soundness checks and enforce them on each PR.

A recommended workflow looks like this:

```yaml
name: Pull request

on:
  pull_request:
    types: [opened, reopened, synchronize]

jobs:
  soundness:
    name: Soundness
    uses: swiftlang/github-workflows/.github/workflows/soundness.yml@main
    with:
      license_header_check_project_name: "Swift.org"
```

### Testing

To enable pull request testing for all supported Swift versions (5.9, 5.10,
6.0, 6.1, nightly, and nightly-6.1) on Linux and Windows, add the following code example in
`.github/workflows/pull_request.yml`:

```yaml
name: pull_request

on:
  pull_request:
    types: [opened, reopened, synchronize]

jobs:
  tests:
    name: tests
    uses: swiftlang/github-workflows/.github/workflows/swift_package_test.yml@main
```

If your package only supports newer compiler versions, you can exclude older
versions by using the `*_exclude_swift_versions` workflow input:

```yaml
linux_exclude_swift_versions: "[{\"swift_version\": \"5.9\"}]"
windows_exclude_swift_versions: "[{\"swift_version\": \"5.9\"}]"
```

Additionally, if your package requires additional installed packages, you can
use the `pre_build_command`. For example, to install a package called
`example`:

```yaml
pre_build_command: "which example || (apt update -q && apt install -yq example"
```

macOS platform support will be available soon.

## Running workflows locally

You can run the Github Actions workflows locally using
[act](https://github.com/nektos/act). To run all the jobs that run on a pull
request, use the following command:

```bash
% act pull_request
```

To run just a single job, use `workflow_call -j <job>`, and specify the inputs
the job expects. For example, to run just shellcheck:

```bash
% act workflow_call -j soundness --input shell_check_enabled=true
```

To bind-mount the working directory to the container, rather than a copy, use
`--bind`. For example, to run just the formatting, and have the results
reflected in your working directory:

```bash
% act --bind workflow_call -j soundness --input format_check_enabled=true
```

If you'd like `act` to always run with certain flags, these can be be placed in
an `.actrc` file either in the current working directory or your home
directory, for example:

```bash
--container-architecture=linux/amd64
--remote-name upstream
--action-offline-mode
```

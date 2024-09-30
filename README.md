# GitHub Actions Workflows

This repository will contain reusable workflows to minimize redundant workflows across the organization. This effort will also facilitate the standardization of testing processes while empowering repository code owners to customize their testing plans as needed. The repository will contain workflows to support different types of repositories, such as Swift Package and Swift Compiler.

For more details on reusable workflows, please refer to the [Reusing workflows](https://docs.github.com/en/actions/using-workflows/reusing-workflows) section in the GitHub Docs.

## Reusable workflow for Swift package repositories

To enable pull request testing for all supported Swift versions (5.8, 5.9, 5.10, 6.0, and nightly) on Linux, add the following code example in `.github/workflows/pull_request.yml`:

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

If your package only supports newer compiler versions, you can exclude older versions by using the `exclude_swift_versions` workflow input:

```yaml
exclude_swift_versions: "[{\"swift_version\": \"5.8\"}]"
```

Additionally, if your package requires additional installed packages, you can use the `pre_build_command`:

```yaml
pre_build_command: "apt-get update -y -q && apt-get install -y -q example"
```

macOS and Windows platform support will be available soon.

# Unified workflows migration guide

This guide lays out how to migrate your existing GitHub Actions jobs from the existing `swiftlang/github-workflows` and `apple/swift-nio` workflows. Mostly this should be relatively straightforward as the changes are mostly additive, but some behavior and names have changes.

Where to start:

* If you are coming from `swiftlang/github-workflows` and `swift_package_test.yml`: read *Before your first run*, then [Migrating from `swiftlang/github-workflows`](#migrating-from-swiftlanggithub-workflows-swift_package_testyml).
* If you are coming from `apple/swift-nio`'s workflows: read *Before your first run*, then [Migrating from `apple/swift-nio` workflows](#migrating-from-appleswift-nio-workflows).
* Needing a matrix that's not a plain product of versions and operating systems: read [Calling `execute_matrix.yml` directly](#calling-execute_matrixyml-directly).

## Before your first run

Four things change what a repository's CI does, whichever workflow it comes from.

**The standard checks are on by default.** The unified workflows enable a larger set of jobs and platforms by default, reflecting the expected supported Swift platforms and features.

| Check | Turn it off with |
|---|---|
| Linux tests | `enable_linux: false` |
| Windows tests, run natively | `enable_windows: false` |
| macOS tests | `enable_macos: false` |
| macOS with a swiftly toolchain | `enable_macos_swiftly: false` |
| Static Linux SDK build | `enable_linux_static_sdk_build: false` |
| Wasm SDK build | `enable_wasm_sdk_build: false` |
| Embedded Wasm SDK build | `enable_embedded_wasm_sdk_build: false` |
| Android SDK build and emulator tests | `enable_android_sdk_build: false`; to drop only the emulator, `android_emulator_test_triples: '[]'` |
| Cxx interop check | `enable_cxx_interop: false` |
| FreeBSD tests | `enable_freebsd: false` |

**Job names change.** Several job names change in their details, especially if you use the new relative naming, such as `Linux Swift current-1`, `Release-Build Linux Swift 6.3`, or `Android SDK Swift current NDK r30 x86_64-android28`. 

This likely requires changes in repository branch protection rules or required checks.

**Commands and setup commands behave differently.** A build command is no longer unescaped once by the shell, and a setup command has to work with or without `sudo`. See *Commands are no longer shell-unescaped* and *Setup commands run privileged or not*.

**A release pins the scripts as well as the workflow.** `uses: swiftlang/github-workflows/.github/workflows/package_test.yml@<version>` runs that release's workflow YAML *and the scripts* it ships with. Previously the scripts floated on `main`, which was a bug. 

**Several workflows now default to running outside of Docker.** Previously many jobs ran in Docker containers on the GitHub runners (all in the SwiftNIO case); to speed up workflows they mostly default to running natively on the GitHub runner.

## Migrating from `swiftlang/github-workflows` (`swift_package_test.yml`)

### Switch the workflow name

Replace:

```yaml
uses: swiftlang/github-workflows/.github/workflows/swift_package_test.yml@0.0.11
```

With:

```yaml
uses: swiftlang/github-workflows/.github/workflows/package_test.yml@<version>
```

 Most inputs have the same names, and the mapping table below lists the ones that don't. 

### What's different

#### Changes that alter what runs

1. **Windows now runs by default, natively.** 
2. **The standard checks are on by default.** 
3. **The Android emulator tests run in their own jobs.** You now specify the Android SDK triples to build and the ones to test with an emulator as separate entries.
4. **The Cxx interop check runs on every Linux version.**
5. **SDK builds no longer follow the Linux distribution.** The static-linux, wasm, and embedded-wasm SDK builds ran in a container tagged for each distribution in the Linux OS list. All four SDK builds now run on the GitHub-hosted Ubuntu runner whatever that list says, so a package pinned to `amazonlinux2` gets its tests on amazonlinux2 and its SDK builds on Ubuntu.
6. **A Windows container runs its commands under `cmd`.** `Invoke-Program` and the rest of PowerShell don't exist there.
7. **Workflows detect a package's minimum version.** The matrix infrastructure detects the minimum `swift-tools-version` and won't generate jobs below that version, since those jobs would fail.

#### Changes that alter what you write

7. **No `exclude_*` arrays.** The new system uses **explicit version lists**: pass the versions you want. 
8. **Swift versions are relative by default**. Defaults are `["current-2", "current-1", "current", "nightly-release", "nightly-main"]` for both Linux and Windows, `["current-2", "current-1", "current"]` for macOS, and `["current", "nightly-release", "nightly-main"]` for the SDK builds, where `current` is the release the workflow version targets (see [Swift version labels](architecture.md#swift-version-labels)). A job takes its name from the label, so `Linux Swift current-1` keeps its name when a new release moves the versions under it. Write versions out (`["6.2", "6.3"]`) to name them literally. 
9. **macOS uses Swift versions by default.** Instead of `macos_xcode_versions: '["16.3", "16.4", "26.0"]'`, the default is `macos_swift_versions: '["current-2", "current-1", "current"]'`. The runners have symlinks (`Xcode_swift_6.3.app`) that resolve the correct Xcode. You can still pass `macos_xcode_versions` if you prefer Xcode version numbers.
10. **`nightly-release` replaces `nightly-6.3`.** Use `nightly-release` in version lists. It resolves to the current/upcoming release branch nightly. When Swift cuts a new release branch, no workflow file needs to change. 
11. **Per-version overrides are a YAML (or JSON) object.** Instead of `linux_6_1_arguments_override`, `linux_6_2_arguments_override`, etc., give the arguments every version takes under `default`, and a key for each version that differs. The keys use the same spelling as the version list: relative labels for the default list, versions if you wrote them out.

    ```yaml
    linux_version_overrides: |
      default: -Xswiftc -warnings-as-errors --explicit-target-dependency-import-check error
      nightly-main: --explicit-target-dependency-import-check error
    ```

12. **Timeouts are one input.** `job_timeout` bounds each job and defaults to 90 minutes (60 for `benchmarks.yml`). `windows_job_timeout` and `freebsd_job_timeout` raise the limit for those two platforms, where installing a toolchain takes longer; `0` uses `job_timeout`. A hand-written matrix can set `timeout_minutes` on an entry.
13. **You can specify a `package_path`.** To support packages which aren't at a repository's root.




### Labeled commands

In addition to specifying one command for a platform, say a `linux_command`, the input now also takes a map of label to command, which produces one job per toolchain *and* command, so a debug and a release pass come from one call rather than two:

```yaml
linux_command: |
  Debug-Test: swift test
  Release-Build: swift build -c release
```

That gives `Debug-Test Linux Swift 6.3` and `Release-Build Linux Swift 6.3`. The label leads the job name, and only when the call configures more than one command, so a single labeled command leaves existing names alone. A label is one word of letters, digits, `_`, `.`, and `-`, starting with a letter or digit. A label with a space makes the whole value read as one shell command. A label may narrow itself to part of the version list:

```yaml
linux_command: |
  Debug-Test: swift test
  Release-Build:
    command: swift build -c release
    versions: ["6.3"]
```


### Commands are no longer shell-unescaped once on the way in

The old SwiftNIO workflow interpolated a build command into a `run:` block, so the shell parsed it before the script saw it. A command referring to a variable it wanted expanded *later* had to escape the dollar:

```yaml
linux_static_sdk_build_command: |
  for triple in aarch64-swift-linux-musl x86_64-swift-linux-musl ; do
    swift build --swift-sdk "\$triple"      # old: one unescape happens on the way in
  done
```

The unified workflows carry the command through the matrix as data, so there is no such step. Write the variable plainly, under the renamed input:

```yaml
linux_static_sdk_command: |
  for triple in aarch64-swift-linux-musl x86_64-swift-linux-musl ; do
    swift build --swift-sdk "$triple"       # new
  done
```


### Example migration of swift-format

**Before:**

```yaml
tests:
  uses: swiftlang/github-workflows/.github/workflows/swift_package_test.yml@0.0.11
  with:
    enable_cross_pr_testing: true
    linux_exclude_swift_versions: "[{\"swift_version\": \"5.9\"}, {\"swift_version\": \"5.10\"}]"
    windows_exclude_swift_versions: "[{\"swift_version\": \"5.9\"}]"
```

**After:**

```yaml
tests:
  uses: swiftlang/github-workflows/.github/workflows/package_test.yml@<version>
  with:
    enable_cross_pr_testing: true
    # The package runs none of the other standard checks.
    enable_macos: false
    enable_macos_swiftly: false
    enable_linux_static_sdk_build: false
    enable_wasm_sdk_build: false
    enable_embedded_wasm_sdk_build: false
    enable_android_sdk_build: false
    enable_cxx_interop: false
    enable_freebsd: false
```

### Apple platforms other than macOS

`enable_ios_checks` no longer exists. It ran `swift build --build-tests --sdk … --triple arm64-apple-ios` on a macOS runner of its own: it compiled the package and its tests for iOS but never ran anything.

The same check now rides on the macOS entries, so it costs no extra runner:

```yaml
# macOS is on by default
xcode_scheme: my-package-Package
xcode_targets: "[iOS]"
```

`xcode_targets` names the platforms to drive through `xcodebuild`. The platforms are `macOS`, `Catalyst`, `iOS`, `watchOS`, `tvOS`, and `visionOS`. A bare list asks for each named platform with every setting at its default, which is to build and not test. The map form sets them per target:

```yaml
xcode_targets: |
  iOS: {build: true, test: true}
  watchOS: {test: true}
  macOS: {}
```

The build action is `build-for-testing`, so this still type-checks test code, as `--build-tests` did. Adding `test: true` also runs the tests on a simulator, which `enable_ios_checks` couldn't do at all.

Some consequences:

* A scheme is now required. For a package without an Xcode project it's the SwiftPM-generated `<Name>-Package`.
* The per-Xcode-version iOS runner no longer exists: whichever macOS entries exist build iOS, so `ios_host_xcode_versions`, `ios_build_command`, and `ios_pre_build_command` no longer exist either. For iOS isolated on its own runner, use `toolchain_matrix.yml` with `execute_matrix.yml` and your own command.

* * *

## Migrating from `apple/swift-nio` workflows

### Quick start

Replace multiple workflow calls:

```yaml
unit-tests:
  uses: apple/swift-nio/.github/workflows/unit_tests.yml@main
benchmarks:
  uses: apple/swift-nio/.github/workflows/benchmarks.yml@main
cxx-interop:
  uses: apple/swift-nio/.github/workflows/cxx_interop.yml@main
release-builds:
  uses: apple/swift-nio/.github/workflows/release_builds.yml@main
macos-tests:
  uses: apple/swift-nio/.github/workflows/macos_tests.yml@main
static-sdk:
  uses: apple/swift-nio/.github/workflows/static_sdk.yml@main
```

With one or two calls:

```yaml
package-tests:
  uses: swiftlang/github-workflows/.github/workflows/package_test.yml@<version>
  with:
    linux_command: |
      Debug-Test: swift test
      Release-Build: swift build -c release

benchmarks:
  uses: swiftlang/github-workflows/.github/workflows/benchmarks.yml@<version>
  with:
    benchmark_package_paths: '["Benchmarks"]'
```

The Cxx interop check, the static SDK build and macOS are on by default, so they need no input. The release-configuration build is a second labeled command, and `release_build.yml` no longer exists.

1. **Per-version overrides.** SwiftNIO used `linux_6_1_arguments_override`, `linux_6_2_arguments_override`, etc. The unified system uses a single YAML/JSON object  and a key for each version that differs.

    SwiftNIO's `pull_request.yml` passed the same arguments to five versions and different ones to `nightly-main`. It becomes one object, with the shared arguments under `default` and the one exception under its own key. `nightly_next` is now `nightly-release`, which `default` covers:

    ```yaml
    package-tests:
      uses: swiftlang/github-workflows/.github/workflows/package_test.yml@<version>
      with:
        linux_version_overrides: |
          default: -Xswiftc -warnings-as-errors --explicit-target-dependency-import-check error
          nightly-main: --explicit-target-dependency-import-check error
    ```
2. **Version enables → version lists.** Instead of `linux_5_9_enabled: false`, leave 5.9 out of `linux_swift_versions`. Or rely on minimum version detection. A package that supports more releases than the default window of `current-2` to `current` writes its versions out, for example `["6.1", "6.2", "6.3", "6.4", "nightly-release", "nightly-main"]`, and its overrides then key on those versions. A YAML anchor states the list once for the calls in a file.
3. **macOS tests use Swift versions.** Instead of `swift_6_1_enabled: true` / `xcode_16_3_enabled: false`, pass:

   ```
   macos_swift_versions: '["6.1", "6.2", "6.3"]'
   ```

   Runners have symlinks that resolve Swift versions to Xcode installations.
4. **Runner pool is an input.** Instead of baking the pool into `macos_tests.yml`, pass `macos_runner_pool: general` (or `nightly` for main-branch CI). It's empty by default.
5. **xcodebuild platform targets.** Instead of `ios_xcode_test_enabled: true` on `macos_tests.yml`, pass:

   ```
   xcode_scheme: my-package-Package
   xcode_targets: |
     iOS: {test: true}
   ```

   `macOS`, `Catalyst`, `watchOS`, `tvOS`, and `visionOS` go in the same map, and the destinations match the ones `macos_tests.yml` uses. The build action is `build-for-testing` rather than `build`.
6. **Benchmarks are a separate workflow.** Now called from `swiftlang/github-workflows` instead of `apple/swift-nio`. macOS is off by default, so pass `enable_macos: true` for the macOS benchmarks.
7. **Integration tests pair `toolchain_matrix.yml` with your command.** See *An example of custom integration tests* below for the whole job pair.
8. **Container config moves under `swift_build.container`.** 

### Build and test as separate steps

SwiftNIO's Darwin job runs `swift build --build-tests` and then `swift test`, with separate argument overrides for each. One matrix entry runs one command, so the two become one command:

```yaml
  macos_command: |
    swift build --build-tests
    swift test
```

To split them out on parallel runners rather than running in serial, make them two labeled commands instead:

```yaml
  macos_command: |
    build: swift build --build-tests
    test: swift test
```

### Default Swift versions

By default the matrix produces jobs for and named `["current-2", "current-1", "current", "nightly-release", "nightly-main"]`, these are then mapped using a definition in the `swiftlang/github-workflows` repository, so **each tag pins them**. To adopt a new Swift version you need to adopt a new tag of the upstream workflows so each repository controls the timing. To opt out of this relative naming, you must specify the versions you want explicitly.

### Version-keyed directories (SwiftNIO and SwiftNIO HTTP/2)

`SWIFT_VERSION` carries the version label, and anything that stores data per version carries it in its name. SwiftNIO calls the release-branch nightly `nightly-next`. Here it's `nightly-release`, so rename every file or directory named for it once, during migration. 

`SWIFT_VERSION` carries the version a label resolves to, so with the default lists the job on `current-1` reads the files named `6.3` when `current` is 6.4. A repository that keeps thresholds for more releases than the default window holds, as SwiftNIO does, writes those versions out.

### Example migration of SwiftNIO

**Before:** separate calls to SwiftNIO's own workflows, one for each row of the SwiftNIO workflow mapping table.

**After:**

```yaml
package-tests:
  uses: swiftlang/github-workflows/.github/workflows/package_test.yml@<version>
  with:
    # The four currently-supported versions explicitly-named.
    linux_swift_versions: &linux_swift_versions '["6.1", "6.2", "6.3", "6.4", "nightly-release", "nightly-main"]'

    linux_version_overrides: |
      default: -Xswiftc -warnings-as-errors --explicit-target-dependency-import-check error
      nightly-main: --explicit-target-dependency-import-check error
    linux_command: |
      Debug-Test: swift test
      Release-Build: swift build -c release

    macos_runner_pool: general

    wasm_sdk_command: "swift build --target NIOCore"

    # The Android SDK builds both architectures and runs no emulator.
    android_sdk_build_triples: '["aarch64-unknown-linux-android28", "x86_64-unknown-linux-android28"]'
    android_emulator_test_triples: '[]'

    # Not run by this package.
    enable_windows: false
    enable_macos_swiftly: false
    enable_embedded_wasm_sdk_build: false
    enable_freebsd: false

benchmarks:
  uses: swiftlang/github-workflows/.github/workflows/benchmarks.yml@<version>
  with:
    benchmark_package_paths: '["Benchmarks"]'
    linux_swift_versions: *linux_swift_versions
```

* * *

## Calling `execute_matrix.yml` directly

For full control over the matrix, bypass `package_test.yml` and call `execute_matrix.yml` with a hand-crafted or script-generated YAML matrix. The entry schema is under [The matrix definition](architecture.md#the-matrix-definition).

### An example of custom integration tests

Use `toolchain_matrix.yml` for the toolchains and `execute_matrix.yml` for the command. Neither needs the scripts checked out: both take them from the release you pin.

```yaml
jobs:
  toolchains:
    uses: swiftlang/github-workflows/.github/workflows/toolchain_matrix.yml@<version>
    with:
      linux_swift_versions: '["6.3", "nightly-release"]'
      linux_env_vars: '{"MY_VAR": "value"}'

  tests:
    needs: toolchains
    uses: swiftlang/github-workflows/.github/workflows/execute_matrix.yml@<version>
    with:
      name: "My custom tests"
      matrix_yaml_string: ${{ needs.toolchains.outputs.matrix_yaml }}
      setup_command: |
        if command -v sudo >/dev/null 2>&1; then
          sudo apt-get update -y -q && sudo apt-get install -y -q lsof
        else
          apt-get update -y -q && apt-get install -y -q lsof
        fi
      command: "./scripts/my_tests.sh"
```

An entry that carries its own `command` keeps it, so you can mix generated and hand-written entries.

### A matrix that's not a version × OS product

`package_test.yml` generates a rectangular matrix: every version in the list, for every OS in the list. Three shapes need the lower layers instead (`toolchain_matrix.yml` and `execute_matrix.yml`), because the toolchain matrix is plain YAML and you can reshape it with `yq` before it runs.

**A matrix with a hole in it.** Amazon Linux 2023 images exist only for Swift 6.3 and later, so the full product would ask for images that don't exist:

```yaml
jobs:
  toolchains:
    uses: swiftlang/github-workflows/.github/workflows/toolchain_matrix.yml@<version>
    with:
      linux_os: '["noble", "amazonlinux2023"]'

  filter:
    needs: toolchains
    runs-on: ubuntu-24.04
    outputs:
      matrix_yaml: ${{ steps.filter.outputs.matrix_yaml }}
    steps:
      - id: filter
        env:
          MATRIX: ${{ needs.toolchains.outputs.matrix_yaml }}
        run: |
          # Keep every entry except the pre-6.3 ones on amazonlinux2023.
          matrix=$(echo "$MATRIX" | yq '.config |= map(
            select(((.swift_build.container.image // "") | test("amazonlinux2023") | not)
                   or (.swift_build.swift_version | test("^6\\.[3-9]|^nightly"))))')
          {
            echo "matrix_yaml<<EOF"
            echo "$matrix"
            echo "EOF"
          } >> "$GITHUB_OUTPUT"

  tests:
    needs: filter
    uses: swiftlang/github-workflows/.github/workflows/execute_matrix.yml@<version>
    with:
      name: "Tests"
      matrix_yaml_string: ${{ needs.filter.outputs.matrix_yaml }}
      command: "swift test"
```

The other two shapes are the same `filter` job with a different expression.

**An image the tag scheme can't express**, such as one from a private registry. The `select` keeps it off macOS entries, which have no `swift_build` to graft it onto, and off Windows, whose images aren't the same ones:

```yaml
          matrix=$(echo "$MATRIX" | yq '.config |= map(
            select(.platform == "Linux").swift_build.container.image =
              "registry.example.com/swift:6.3-custom")')
```

**Native and containerized in one run.** `linux_use_docker` is all or nothing, so add the container to the entries that want it and leave the rest native. Every entry starts out native, including `nightly-release`, so the `select` picks out whichever ones the container is for:

```yaml
          matrix=$(echo "$MATRIX" | yq '.config |= map(
            select(.platform == "Linux" and .swift_build.swift_version == "6.3")
              .swift_build.container.image = "swift:6.3-noble")')
```

Or write the matrix yourself and pass it straight to `execute_matrix.yml`.

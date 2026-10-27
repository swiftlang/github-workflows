# Unified Workflows Migration Guide

[The architecture document](architecture.md) says how the layers fit together. The inputs this guide names, and their defaults, are declared in [`package_test.yml`](package_test.yml).

## Migrating from `swiftlang/github-workflows` (`swift_package_test.yml`)

### Quick start

Replace:

```
uses: swiftlang/github-workflows/.github/workflows/swift_package_test.yml@0.0.11
```

With:

```
uses: swiftlang/github-workflows/.github/workflows/package_test.yml@<version>
```

`<version>` is a tag of `swiftlang/github-workflows`; take the newest from its [releases](https://github.com/swiftlang/github-workflows/releases). Every `@<version>` below stands for the same thing, and the `0.0.11` above is only an example of what is being replaced.

Most inputs have the same names, and the sections below list the ones that do not.

A release pins the workflow YAML, including the Swift versions the defaults name, but not the scripts those workflows run. The scripts are checked out from the default branch of `swiftlang/github-workflows`, so a change to one reaches a repository that has not updated its tag.

The standard checks are now on by default, which the old workflow did not do. A repository that listed only the checks it wanted runs the rest after migrating, so read *What's different* before the first run.

### Commands are no longer shell-unescaped once on the way in

The old workflow interpolated a build command into a `run:` block, so the shell parsed it before the script saw it. A command referring to a variable it wanted expanded *later* had to escape the dollar:

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

A command that still escapes the dollar reaches `eval` as a literal `$triple` and fails with a `No Swift SDK found matching query` error naming it.

Relatedly, `install-and-build-with-sdk.sh` appends its own `--swift-sdk <triple>` to the command unless the command already names `--swift-sdk`, as the loop above does. In that case it appends nothing and the command's own triples stand.

### Setup commands run privileged or not

A Linux entry runs on the runner as an unprivileged user, or in a container as root where `sudo` is not installed. Both are reached in one matrix: native is the default, and a container appears only where one is asked for through `linux_use_docker`, a `linux_os` list, or `linux_dockerfile`. A setup command that installs packages therefore has to work either way. On `package_test.yml` the input is `linux_setup_command`; `execute_matrix.yml` calls the same thing `setup_command`.

```yaml
linux_setup_command: |
  if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update -y -q && sudo apt-get install -y -q lsof
  else
    apt-get update -y -q && apt-get install -y -q lsof
  fi
```

The old workflows always used a container, so a setup command written for them uses `apt-get` unprefixed and fails on the native path; one written for a GitHub-hosted runner uses `sudo` and fails in the container.

### What's different

1. **No skipped jobs.** Disabled platforms produce zero jobs instead of grayed-out `skipped` entries.
2. **No `exclude_*` arrays.** The old system used `linux_exclude_swift_versions` etc. to remove entries from a default matrix. The new system uses **explicit version lists**: pass the versions you want. The defaults are `["current-2", "current-1", "current", "nightly-release", "nightly-main"]` for both Linux and Windows, `["current-2", "current-1", "current"]` for macOS, and `["current", "nightly-release", "nightly-main"]` for the SDK builds, where `current` is the release the workflow version was cut for (see [Swift version labels](architecture.md#swift-version-labels)). A job is named for the label, so `Linux Swift current-1` keeps its name when a new release moves the versions under it. Write versions out (`["6.2", "6.3"]`) to name them literally. An exclude list that only dropped 5.9 and 5.10 has nothing left to do. For anything else old, minimum version auto-detection from `Package.swift` handles it.
3. **Windows is enabled by default and runs natively.** `enable_windows` defaults to `true`, and `windows_use_docker` defaults to `false` where `enable_windows_docker` defaulted to `true`. A repository that relied on the container gets native Windows jobs, which cannot build a Swift release before 6.1; pass `windows_use_docker: true` to keep containers.
4. **macOS uses Swift versions by default.** Instead of `macos_xcode_versions: '["16.3", "16.4", "26.0"]'`, the default is `macos_swift_versions: '["current-2", "current-1", "current"]'`. The runners have symlinks (`Xcode_swift_6.3.app`) that resolve the correct Xcode. You can still pass `macos_xcode_versions` if you prefer Xcode version numbers.
5. **`nightly-release` replaces `nightly-6.3`.** Use `nightly-release` in version lists. It resolves to the current/upcoming release branch nightly. When a new release branch is cut, no workflow file changes are needed. Testing a branch this repository has not moved to yet means naming it literally, as `nightly-6.5.x`.
6. **Per-version overrides are a YAML (or JSON) object.** Instead of `linux_6_1_arguments_override`, `linux_6_2_arguments_override`, etc., give the arguments every version takes under `default`, and a key for each version that differs. The keys use the same spelling as the version list: relative labels for the default list, versions if you wrote them out.

   ```
   linux_version_overrides: |
     default: -Xswiftc -warnings-as-errors --explicit-target-dependency-import-check error
     nightly-main: --explicit-target-dependency-import-check error
   ```

   Here every Linux version takes the first line and `nightly-main` takes only the second. A version's own key replaces `default` for the fields it names. Arguments with no key at all are the same as `default`, so `linux_version_overrides: --explicit-target-dependency-import-check error` gives that argument to every version. A `command:` belongs to a version and is an error under `default`.

   `linux_version_overrides` is for the Linux tests alone. The SDK builds read `linux_static_sdk_version_overrides`, `wasm_sdk_version_overrides`, `embedded_wasm_sdk_version_overrides` and `android_sdk_version_overrides` in the same form, and the Cxx interop check reads none. All of them still get `swift_flags` and `swift_nightly_flags`.
7. **SDK builds no longer follow the Linux distribution.** The static-linux, wasm and embedded-wasm SDK builds ran in a container tagged for each distribution in the Linux OS list. All four SDK builds now run on the GitHub-hosted Ubuntu runner whatever that list says, so a package pinned to `amazonlinux2` gets its tests on amazonlinux2 and its SDK builds on Ubuntu.
8. **The standard checks are on by default.** `enable_macos`, `enable_macos_swiftly`, `enable_linux_static_sdk_build`, `enable_wasm_sdk_build`, `enable_embedded_wasm_sdk_build`, `enable_android_sdk_build`, `enable_android_emulator_tests` and `enable_cxx_interop` all default to `true`. Set the ones a package does not run to `false`, for example `enable_wasm_sdk_build: false`. FreeBSD stays opt-in. `enable_android_emulator_tests` needs `enable_android_sdk_build`, so turning off the build means turning off the emulator tests too. A call with no inputs now produces about 30 jobs, including macOS on the self-hosted pools.
9. **The Cxx interop check runs on every Linux version.** `cxx_interop_swift_versions` narrows it, and it is filtered by the minimum Swift version like the Linux tests.
10. **Timeouts are one input.** `job_timeout` bounds each job and defaults to 90 minutes. `linux_build_timeout`, `linux_static_sdk_build_timeout`, `wasm_sdk_build_timeout`, `android_sdk_build_timeout` and the macOS and iOS `*_build_timeout` inputs are removed. `windows_job_timeout` and `freebsd_job_timeout` raise the limit for those two platforms, where installing a toolchain takes longer; `0` uses `job_timeout`. A hand-written matrix can set `timeout_minutes` on an entry.
11. **A package below the repository root takes `package_path`.** Each job runs its setup command from the root, so the setup can still use paths written relative to the repository, and then enters the directory for the command. Minimum Swift version detection reads that directory's `Package.swift`. This replaces the `cd` that setup commands carried, and it is checked: a path with quotes, `$`, backticks or backslashes fails the run, and so does a path with whitespace for a Windows container.
12. **A Windows container runs its commands under `cmd`.** `Invoke-Program` and the rest of PowerShell do not exist there, so a command written for a native Windows job, such as `Invoke-Program swift build`, fails in a container. Write `swift build`.

### Input mapping table

| Old input | New input | Notes |
|---|---|---|
| `macos_xcode_versions` | `macos_xcode_versions` | Same |
| `macos_exclude_xcode_versions` | (removed) | † |
| `macos_versions` | `macos_os` | Renamed. One runner label, or a list of them |
| `macos_archs` | `macos_arch` | One architecture per call rather than a list |
| `macos_swiftly_toolchains` | `macos_swiftly_toolchains` | Rename each object's `swift_version` key to `swiftly_toolchain`; `os_version` and `arch` remain optional. An object still carrying `swift_version` names no toolchain, and the generator rejects it |
| `ios_host_xcode_versions` | (removed) | Retired with `enable_ios_checks`; see the Apple platforms section |
| `ios_host_exclude_xcode_versions` | (removed) | † |
| `ios_host_versions` | (removed) | Retired with `enable_ios_checks`; see the Apple platforms section |
| `ios_host_archs` | (removed) | Retired with `enable_ios_checks`; see the Apple platforms section |
| `linux_swift_versions` | `linux_swift_versions` | Same |
| `linux_exclude_swift_versions` | (removed) | † |
| `linux_os_versions` | `linux_os` | Renamed. One distribution, or a list of them; the default moved from `jammy` to `noble` |
| `linux_host_archs` | `linux_host_archs` | Same |
| `linux_static_sdk_versions` | `linux_static_sdk_versions` | Same |
| `linux_static_sdk_exclude_swift_versions` | (removed) | † |
| `wasm_sdk_versions` | `wasm_sdk_versions` | Same |
| `wasm_exclude_swift_versions` | (removed) | † |
| `android_sdk_versions` | `android_sdk_versions` | Same |
| `android_exclude_swift_versions` | (removed) | † |
| `windows_swift_versions` | `windows_swift_versions` | Same |
| `windows_exclude_swift_versions` | (removed) | † |
| `windows_os_versions` | `windows_os` | Renamed. One runner label, or a list of them |
| `freebsd_swift_versions` | `freebsd_swift_versions` | Same default (`["nightly-main"]`), but any other value now fails the run rather than generating a job |
| `freebsd_exclude_swift_versions` | (removed) | † |
| `freebsd_os_versions` | `freebsd_os_versions` | Same, and a release other than 14 fails the run |
| `freebsd_host_archs` | (removed) | FreeBSD runs on x86_64 only |
| `swift_flags` | `swift_flags` | Same |
| `swift_nightly_flags` | `swift_nightly_flags` | Same |
| `linux_pre_build_command` | `linux_setup_command` | Renamed |
| `linux_static_sdk_pre_build_command` | `linux_static_sdk_setup_command` | Renamed |
| `wasm_sdk_pre_build_command` | `wasm_sdk_setup_command` | Renamed |
| `android_sdk_pre_build_command` | `android_sdk_setup_command` | Renamed |
| `macos_pre_build_command` | `macos_setup_command` | Renamed |
| `macos_build_command` | `macos_command` | Renamed. Also takes a labeled map ◇ |
| `macos_swiftly_build_command` | `macos_swiftly_command` | Renamed. Also takes a labeled map ◇ |
| `macos_build_timeout` | (removed) | Use `job_timeout` |
| `ios_pre_build_command` | (removed) | Retired with `enable_ios_checks`; see the Apple platforms section |
| `ios_build_command` | (removed) | Retired with `enable_ios_checks`; see the Apple platforms section |
| `ios_build_timeout` | (removed) | Use `job_timeout` |
| `linux_build_command` | `linux_command` | Renamed. Also takes a labeled map ◇ |
| `linux_static_sdk_build_command` | `linux_static_sdk_command` | Renamed. Also takes a labeled map ◇ |
| `wasm_sdk_build_command` | `wasm_sdk_command` | Renamed. Also takes a labeled map ◇ |
| `embedded_wasm_sdk_build_command` | `embedded_wasm_sdk_command` | Renamed. Also takes a labeled map ◇ |
| `android_sdk_build_command` | `android_sdk_command` | Renamed. Also takes a labeled map ◇ |
| `android_sdk_triples` | `android_sdk_triples` | Same |
| `android_ndk_versions` | `android_ndk_versions` | Same, defaulting to `r30` alone |
| `windows_pre_build_command` | `windows_setup_command` | Renamed |
| `windows_build_command` | `windows_command` | Renamed. Also takes a labeled map ◇ |
| `windows_build_timeout` | `windows_job_timeout` | Carried on each Windows entry as `timeout_minutes`. `0` uses `job_timeout` |
| `linux_build_timeout` | (removed) | Use `job_timeout` |
| `linux_static_sdk_build_timeout` | (removed) | Use `job_timeout` |
| `wasm_sdk_build_timeout` | (removed) | Use `job_timeout` |
| `android_sdk_build_timeout` | (removed) | Use `job_timeout` |
| `freebsd_pre_build_command` | `freebsd_setup_command` | Renamed |
| `freebsd_build_command` | `freebsd_command` | Renamed. Also takes a labeled map ◇ |
| `macos_env_vars` | `macos_env_vars` | Same |
| `ios_host_env_vars` | (removed) | Retired with `enable_ios_checks`; see the Apple platforms section |
| `linux_env_vars` | `linux_env_vars` | Same |
| `windows_env_vars` | `windows_env_vars` | Same |
| `freebsd_env_vars` | `freebsd_env_vars` | Same |
| `enable_linux_checks` | `enable_linux` | ‡ |
| `enable_linux_static_sdk_build` | `enable_linux_static_sdk_build` | Same name. **Now defaults to true** |
| `enable_wasm_sdk_build` | `enable_wasm_sdk_build` | Same name. **Now defaults to true** |
| `enable_embedded_wasm_sdk_build` | `enable_embedded_wasm_sdk_build` | Same name. **Now defaults to true** |
| `enable_android_sdk_build` | `enable_android_sdk_build` | Same name. **Now defaults to true** |
| `enable_android_sdk_checks` | `enable_android_emulator_tests` | Renamed for what it does: it runs the emulator tests. **Now defaults to true** |
| `enable_macos_checks` | `enable_macos` | ‡ **Now defaults to true** |
| `enable_macos_swiftly_checks` | `enable_macos_swiftly` | ‡ **Now defaults to true** |
| `enable_ios_checks` | `xcode_targets` | Name the platform in `xcode_targets`, with `xcode_scheme` for the scheme; see the Apple platforms section |
| `enable_windows_checks` | `enable_windows` | ‡ |
| `enable_windows_docker` | `windows_use_docker` | Pairs with `linux_use_docker`. **The default changed from true to false**; pass `windows_use_docker: true` to keep containers, which a Swift release before 6.1 needs |
| `enable_freebsd_checks` | `enable_freebsd` | ‡ |
| `needs_token` | `needs_token` | Same |
| (none) | `package_path` | New: a package below the repository root |
| (none) | `swift_current_release`, `swift_nightly_release` | New: what `current` and `nightly-release` name; see *What's different* |
| `enable_cross_pr_testing` | `enable_cross_pr_testing` | Same |

† Excludes are gone. List the versions you want, or use `toolchain_matrix.yml` for a matrix that is not a plain product.

‡ `package_test.yml` drops the `_checks` suffix from its platform enables. `cmake_build.yml` keeps `enable_linux_checks`, `enable_macos_checks` and `enable_windows_checks`, and its own `*_build_command` and `*_pre_build_command` inputs are unrenamed.

◇ A command input still takes one command, so a call that passes a string needs no change. It now also takes a map of label to command, which produces one job per toolchain *and* command, so a debug and a release pass come from one call rather than two:

```yaml
linux_command: |
  Debug-Test: swift test
  Release-Build: swift build -c release
```

That gives `Debug-Test Linux Swift 6.3` and `Release-Build Linux Swift 6.3`. The label leads the job name, and only when more than one command is configured, so a single labeled command leaves existing names alone. A label is one word of letters, digits, `_`, `.` and `-`, starting with a letter or digit; a label with a space makes the whole value read as one shell command. A label may narrow itself to part of the version list:

```yaml
linux_command: |
  Debug-Test: swift test
  Release-Build:
    command: swift build -c release
    versions: ["6.3"]
```

Per-version overrides key on the spelling the version list uses, not the label, and apply to every command for that version. An override that *replaces* the command needs a single command configured, since with several there is nothing unambiguous to replace; give the label its own `versions` instead. `macos_swiftly_command` takes labels but no `versions`, its toolchains coming from `macos_swiftly_toolchains`.

### Example: swift-format

**Before:**

```
tests:
  uses: swiftlang/github-workflows/.github/workflows/swift_package_test.yml@0.0.11
  with:
    enable_cross_pr_testing: true
    linux_exclude_swift_versions: "[{\"swift_version\": \"5.9\"}, {\"swift_version\": \"5.10\"}]"
    windows_exclude_swift_versions: "[{\"swift_version\": \"5.9\"}]"
```

**After:**

```
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
    enable_android_emulator_tests: false
    enable_cxx_interop: false
```

The exclude arrays are gone: the default version lists begin at `current-2`, so a package that supports older releases names them, as in `["6.0", "6.1", "current-2", "current-1", "current", "nightly-release", "nightly-main"]`. Windows is on by default and runs natively rather than in a container, which the 6.1-and-later versions are fine with and anything older is not. The `enable_*: false` lines are new: the old workflow ran none of those checks unless asked, and the unified one runs all of them unless told not to.

### Apple platforms other than macOS

`enable_ios_checks` is removed. It ran `swift build --build-tests --sdk … --triple arm64-apple-ios` on a macOS runner of its own: it compiled the package and its tests for iOS but never ran anything, which its name did not convey.

The same check now rides on the macOS entries, so it costs no extra runner:

```
# macOS is on by default
xcode_scheme: my-package-Package
xcode_targets: "[iOS]"
```

`xcode_targets` names the platforms to drive through `xcodebuild`. The platforms are `macOS`, `Catalyst`, `iOS`, `watchOS`, `tvOS` and `visionOS`, spelled exactly so; a lowercase `ios` fails the run rather than being guessed at. A bare list asks for each named platform with every setting at its default, which is to build and not test. The map form sets them per target:

```
xcode_targets: |
  iOS: {build: true, test: true}
  watchOS: {test: true}
  macOS: {}
```

`build` defaults to true and `test` to false, and asking to test implies building, so `watchOS` above builds and tests just as `iOS` does. Both false is an error rather than a target that does nothing. Besides `build` and `test`, a target takes `scheme`, `build_destination` and `test_destination`; the destinations default to the newest device of each kind, so pin them if the run should not move with Xcode. `xcode_scheme` supplies the scheme for every target that does not name its own, and a target reached by neither fails the run.

The build action is `build-for-testing`, so this still type-checks test code, as `--build-tests` did. Adding `test: true` also runs the tests on a simulator, which `enable_ios_checks` could not do at all.

Three consequences:

* A scheme is now required. For a package without an Xcode project it is the SwiftPM-generated `<Name>-Package`.
* The per-Xcode-version iOS runner is gone: iOS is built by whichever macOS entries exist, so `ios_host_xcode_versions`, `ios_build_command` and `ios_pre_build_command` are removed too. For iOS isolated on its own runner, use `toolchain_matrix.yml` with `execute_matrix.yml` and your own command.
* `ios_host_env_vars` is removed, and environment variables are no longer per platform. `macos_env_vars` is exported once for the job and applies to the main command and to every platform target in it. The platforms now share a job, so giving iOS a different value from macOS is not expressible. Neither `macos_tests.yml`, which has a single `env_vars` input across all its platform steps, nor `package_test.yml`'s macOS job ever did. Fold those variables into `macos_env_vars`, and delete the old key: a reusable workflow validates `with:` against the inputs it declares, so an undeclared one fails the run rather than being ignored.

`swift_package_test.yml` is unaffected and keeps `enable_ios_checks`.

* * *

## Migrating from `apple/swift-nio` workflows

### Quick start

Replace multiple workflow calls:

```
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

```
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

The Cxx interop check, the static SDK build and macOS are on by default, so they need no input. The release-configuration build is a second labeled command, and `release_build.yml` is gone.

1. **Per-version overrides.** NIO used `linux_6_1_arguments_override`, `linux_6_2_arguments_override`, etc. The unified system uses a single YAML/JSON object, in the shape shown under *What's different* above: `default` for the arguments every version takes and a key for each version that differs. A string value adds arguments; an object with `command` and/or `arguments` replaces the command, which is what `swift_matrix.yml`'s `*_command_override` inputs did. The overrides reach the Linux tests only, as NIO's `unit_tests.yml` inputs did; they no longer apply to the SDK builds or the Cxx interop check.
2. **Version enables → version lists.** Instead of `linux_5_9_enabled: false`, leave 5.9 out of `linux_swift_versions`. Or rely on minimum version detection. A package that supports more releases than the default window of `current-2` to `current` writes its versions out, for example `["6.1", "6.2", "6.3", "6.4", "nightly-release", "nightly-main"]`, and its overrides then key on those versions. A YAML anchor states the list once for the calls in a file.
3. **macOS tests use Swift versions.** Instead of `swift_6_1_enabled: true` / `xcode_16_3_enabled: false`, pass:

   ```
   macos_swift_versions: '["6.1", "6.2", "6.3"]'
   ```

   Runners have symlinks that resolve Swift versions to Xcode installations.
4. **Runner pool is an input.** Instead of being baked into `macos_tests.yml`, pass `macos_runner_pool: general` (or `nightly` for main-branch CI).
5. **xcodebuild platform targets.** Instead of `ios_xcode_test_enabled: true` on `macos_tests.yml`, pass:

   ```
   xcode_scheme: my-package-Package
   xcode_targets: |
     iOS: {test: true}
   ```

   `macOS`, `Catalyst`, `watchOS`, `tvOS` and `visionOS` go in the same map, and the destinations match the ones `macos_tests.yml` uses. One difference: the build action is `build-for-testing` rather than `build`, so a platform asking only to build (NIO's pull-request configuration) now type-checks test code as well as the library.
6. **Benchmarks are a separate workflow.** Same as before, but now called from `swiftlang/github-workflows` instead of `apple/swift-nio`.
7. **Integration tests pair `toolchain_matrix.yml` with your command.** See *Example: custom integration tests* below for the whole job pair.
8. **Container knobs move under `swift_build.container`.** A `swift_test_matrix.yml` entry's `image`, `dockerfile`, `docker_capabilities` and `docker_security_opts` become `swift_build.container.image`, `.dockerfile`, `.capabilities` and `.security_options`; on `package_test.yml` the last three are `linux_dockerfile`, `linux_docker_capabilities` and `linux_docker_security_options`. Carry across only the ones a job still needs; each is granted to whatever the pull request under test brought with it.

### Build and test as separate steps

NIO's Darwin job runs `swift build --build-tests` and then `swift test`, with separate argument overrides for each. One matrix entry runs one command, so the two become one command:

```yaml
  macos_command: |
    swift build --build-tests
    swift test
```

Per-version differences that applied to only one of the two steps have to be expressed as a per-version command override:

```yaml
  macos_version_overrides: |
    6.3:
      command: |
        swift build --build-tests -Xswiftc -warnings-as-errors
        swift test
```

Where the two steps want reporting separately rather than merely running in order, make them two labeled commands instead, which gives a job and a result apiece:

```yaml
  macos_command: |
    build: swift build --build-tests
    test: swift test
```

### NIO workflow mapping

| **Old NIO workflow** | **New equivalent** |
|---|---|
| `unit_tests.yml` | `package_test.yml` |
| `macos_tests.yml` | `package_test.yml`, with `macos_swift_versions`, `macos_runner_pool` and `xcode_targets` |
| `release_builds.yml` | A `Release-Build` labeled command in `linux_command`, as above. `release_build.yml` no longer exists |
| `cxx_interop.yml` | `package_test.yml`, which runs the check by default on every Linux version |
| `static_sdk.yml` | `package_test.yml`, which runs the build by default |
| `wasm_swift_sdk.yml` | `package_test.yml`, which runs the build by default |
| `android_swift_sdk.yml` | `package_test.yml`, which runs the build by default |
| `benchmarks.yml` | `benchmarks.yml` |
| `macos_benchmarks.yml` | `benchmarks.yml` with `enable_macos: true`; several packages go in `benchmark_package_paths` |
| `swift_test_matrix.yml` | `execute_matrix.yml` |
| `swift_matrix.yml` | `toolchain_matrix.yml` + `execute_matrix.yml`. Its per-version `*_command_override` inputs become an object-valued per-version override |
| `swift_load_test_matrix.yml` | `execute_matrix.yml`, reading the file in the caller and passing it as `matrix_yaml_string` |
| `cmake_tests.yml` | `cmake_build.yml` covers the configure and build. The `CMakeLists.txt` freshness check uses a NIO-local script and has no equivalent here, so repositories needing it keep calling NIO's workflow |
| `swift_6_language_mode.yml` | No equivalent. It sets the manifest's tools version and builds with `-warnings-as-errors`, which is a single job rather than a matrix; keep calling NIO's workflow or inline it |

### Version-keyed directories

`SWIFT_VERSION` carries the version label, and anything storing data per version is named after it. NIO calls the release-branch nightly `nightly-next`; here it is `nightly-release`, so every file or directory named for it is renamed once during migration. A search for the old name by content finds none of them, because the name is in the path:

```
git ls-files | grep nightly-next
git mv Benchmarks/Thresholds/nightly-next Benchmarks/Thresholds/nightly-release
git mv IntegrationTests/tests_01_allocation_counters/Thresholds/nightly-next.json \
       IntegrationTests/tests_01_allocation_counters/Thresholds/nightly-release.json
```

The paths above are the ones in `swift-nio` and `swift-nio-http2`; the first command lists the ones in your repository. A missed one fails the `nightly-release` job when it cannot open its thresholds file. This is a one-time rename, not one per branch cut: the label does not change when a new release branch is opened, only the token it resolves to.

`SWIFT_VERSION` carries the version a label resolves to, so with the default lists the job on `current-1` reads the files named `6.3` when `current` is 6.4. A repository that keeps thresholds for more releases than the default window holds, as `swift-nio` does, writes those versions out.

### Job names

Matrix job names come from the entry's `name`, which reads as e.g. `Linux Swift 6.3` rather than NIO's `Linux (6.3)`, and a labeled command leads the name: `Release-Build Linux Swift 6.3`. Job names are the required status checks, so a repository that requires them has to update branch protection when it migrates. NIO's `dev/thresholds-from-benchmark-output.sh` and `dev/update-integration-test-thresholds.sh` parse job names out of `gh pr checks`, so both need updating when NIO migrates.

### Example: swift-nio

**Before:** 12 separate jobs calling 8 NIO-local workflows.

**After:**

```
package-tests:
  uses: swiftlang/github-workflows/.github/workflows/package_test.yml@<version>
  with:
    # Four releases are supported, one more than the default window, so the lists name versions.
    linux_swift_versions: &linux_swift_versions '["6.1", "6.2", "6.3", "6.4", "nightly-release", "nightly-main"]'

    linux_version_overrides: |
      default: -Xswiftc -warnings-as-errors --explicit-target-dependency-import-check error
      nightly-main: --explicit-target-dependency-import-check error
    linux_command: |
      Debug-Test: swift test
      Release-Build: swift build -c release

    macos_runner_pool: general

    wasm_sdk_command: "swift build --target NIOCore"

    # Not run by this package.
    enable_windows: false
    enable_macos_swiftly: false
    enable_embedded_wasm_sdk_build: false
    enable_android_emulator_tests: false

benchmarks:
  uses: swiftlang/github-workflows/.github/workflows/benchmarks.yml@<version>
  with:
    benchmark_package_paths: '["Benchmarks"]'
    linux_swift_versions: *linux_swift_versions
```

* * *

## Customization: calling `execute_matrix.yml` directly

For full control over the matrix, bypass `package_test.yml` and call `execute_matrix.yml` with a hand-crafted or script-generated YAML matrix. The entry schema is under [The matrix definition](architecture.md#the-matrix-definition).

### Example: custom integration tests

Use `toolchain_matrix.yml` for the toolchains and `execute_matrix.yml` for the command. You check nothing out and shell out to nothing:

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

An entry that carries its own `command` keeps it, so a matrix mixing generated and hand-written entries behaves as written.

### Beyond a version × OS product

`package_test.yml` generates a rectangular matrix: every version in the list, for every OS in the list. Three shapes need the lower layers instead (`toolchain_matrix.yml` and `execute_matrix.yml`, described under [High level design](architecture.md#high-level-design)), because the toolchain matrix is plain YAML and can be reshaped with `yq` before it runs.

**A matrix with a hole in it.** Amazon Linux 2023 images exist only for Swift 6.3 and later, so the full product would ask for images that do not exist:

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
          # Drop pre-6.3 entries on amazonlinux2023.
          matrix=$(echo "$MATRIX" | yq '.config |= map(
            select((.swift_build.container.image // "") | test("amazonlinux2023") | not
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

**An image the tag scheme cannot express**, such as one from a private registry. The `select` keeps it off macOS entries, which have no `swift_build` to graft it onto, and off Windows, whose images are not the same ones:

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

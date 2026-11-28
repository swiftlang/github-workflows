# Install Swift

Install a Swift toolchain, independently of the build system. Only Windows runners are supported.

Inputs:
 - swift-version: Version of Swift to install (e.g. 6.2 or nightly-main). It must name one of the
   `.github/workflows/scripts/windows/swift/install-swift-<version>.ps1` scripts.

The toolchain is added to `PATH`, and `SDKROOT` is set, for the following steps of the job.


## Usage

```yaml
...

steps:

  ...

  - name: Install Swift
    uses: swiftlang/github-workflows/.github/actions/install-swift@<version>
    with:
      swift-version: "6.2"

  - name: Build
    run: swift build

  ...
```

# Install CMake

Install an arbitrary version of CMake.

Inputs:
 - cmake-version: Version of CMake to install (e.g. 3.30.2)
 - hash: sha256 of the downloaded artifact (.zip or .tar.gz)
 - install_dir: (optional) location where to install CMake

Outputs:
 - cmake-dir: Directory containing the CMake binaries
 - cmake: Path to the installed CMake binary
 - ctest: Path to the installed CTest binary


## Usage

```yaml
...

steps:

  ...

  - name: Install CMake
    id: install-cmake
    uses: swiftlang/github-workflows/.github/actions/install-cmake@<version>
    with:
      cmake-version: 4.0.3
      hash: 585ae9e013107bc8e7c7c9ce872cbdcbdff569e675b07ef57aacfb88c886faac

  - name: Run Build
    shell: bash
    env:
      CMAKE: ${{ steps.install-cmake.outputs.cmake }}
    run: |
      "$CMAKE" -G Ninja -B build -S <sources> -DCMAKE_BUILD_TYPE=Release

  - name: Run Tests
    shell: bash
    env:
      CTEST: ${{ steps.install-cmake.outputs.ctest }}
    run: |
      "$CTEST" --output-on-failure --test-timeout 150 --test-dir build -j

  ...
```

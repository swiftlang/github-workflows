##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2026 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##
# Runs a matrix entry's command on Windows, either natively or inside a Docker
# container when CONTAINER_IMAGE is set.
#
# Environment variables:
#   CONTAINER_IMAGE   - When set, the command runs in this image instead of on the
#                       runner.
#   SCRIPTS_ROOT      - The scripts directory, translated into container paths for
#                       the inner command.
#   MATRIX_TOOLCHAIN  - The concrete toolchain identifier the installer is named
#                       after, which differs from the version label for a nightly.
#   CROSS_PR_TESTING, CROSS_PR_REPO, CROSS_PR_NUMBER
#                     - When testing is enabled, the pull request whose linked PRs
#                       are checked out first.
# Parameters:
#   -SwiftVersion: Swift version to use (e.g. "6.2", "nightly-main")
#   -SetupCommand: Setup command (can be empty)
#   -Command: Main command to run
#   -CommandArguments: JSON array or string of command arguments
#   -EnvJson: JSON string of environment variables (can be empty)
#   -NeedsToken: Boolean ("true"/"false") - if "true", passes GITHUB_TOKEN to environment

param(
    [Parameter(Mandatory=$true)]
    [string]$SwiftVersion,

    [Parameter(Mandatory=$false)]
    [string]$SetupCommand = "",

    [Parameter(Mandatory=$true)]
    [string]$Command,

    [Parameter(Mandatory=$false)]
    [string]$CommandArguments = "",

    [Parameter(Mandatory=$false)]
    [string]$EnvJson = "",

    [Parameter(Mandatory=$false)]
    [string]$NeedsToken = "false"
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Docker execution path
# ---------------------------------------------------------------------------
if (-not [string]::IsNullOrEmpty($env:CONTAINER_IMAGE)) {
    Write-Host "Running in Docker container: $env:CONTAINER_IMAGE"

    # Wait for the Docker daemon, starting the service first - polling alone
    # hangs for the full timeout when the service is not running.
    $maxAttempts = 30
    $attempt = 0
    do {
        $attempt++
        if ((Get-Service docker).Status -ne "Running") {
            Start-Service docker
        }
        docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { break }
        if ($attempt -ge $maxAttempts) {
            Write-Error "Docker daemon did not become ready after $maxAttempts attempts"
            exit 1
        }
        Start-Sleep -Seconds 6
    } while ($true)

    docker pull $env:CONTAINER_IMAGE
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to pull Docker image: $env:CONTAINER_IMAGE"
        exit 1
    }

    # Build command to run inside container. Joined with && rather than cmd's &,
    # which sequences unconditionally and reports only the last command's status
    # - a failing setup command would otherwise build at the wrong path and pass.
    #
    # A command written as a YAML block scalar arrives with newlines in it, and cmd
    # takes a single command line, so its lines are joined the same way: they run in
    # order and stop at the first failure, as the Linux container path's `bash -ec`
    # does.
    function Join-CommandLines([string]$Text) {
        $lines = @($Text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
        return ($lines -join " && ")
    }

    $innerCommand = ""
    # Check out linked PRs first, inside the container: the script is compiled
    # with the toolchain under test, which is the container's.
    if ($env:CROSS_PR_TESTING -eq "true" -and -not [string]::IsNullOrEmpty($env:CROSS_PR_REPO)) {
        $innerCommand = "swiftc %SCRIPTS_ROOT%\cross-pr-checkout.swift -o %TEMP%\cross-pr-checkout.exe && " +
                        "%TEMP%\cross-pr-checkout.exe %CROSS_PR_REPO% %CROSS_PR_NUMBER% && "
    }
    if (-not [string]::IsNullOrEmpty($SetupCommand)) {
        $innerCommand += (Join-CommandLines $SetupCommand) + " && "
    }
    $innerCommand += "swift --version && " + (Join-CommandLines $Command)

    if (-not [string]::IsNullOrEmpty($CommandArguments) -and $CommandArguments -ne 'null' -and $CommandArguments -ne '[]') {
        if ($CommandArguments.Trim().StartsWith('[')) {
            # Quote each argument rather than joining on a space: the command is run
            # through cmd, so one containing whitespace would otherwise arrive as
            # several - which the schema's array type promises it will not.
            $args_array = $CommandArguments | ConvertFrom-Json
            $innerCommand += " " + (($args_array | ForEach-Object { '"' + $_ + '"' }) -join ' ')
        } else {
            $innerCommand += " $CommandArguments"
        }
    }

    $workspace = "C:\source"
    $docker_args = @(
        "run",
        "-v", "$env:GITHUB_WORKSPACE`:$workspace",
        "-w", $workspace,
        "-e", "CI=$env:CI",
        "-e", "GITHUB_ACTIONS=$env:GITHUB_ACTIONS",
        "-e", "SWIFT_VERSION=$SwiftVersion"
    )

    if (-not [string]::IsNullOrEmpty($EnvJson) -and $EnvJson -ne '{}' -and $EnvJson -ne 'null') {
        $env_obj = $EnvJson | ConvertFrom-Json
        if ($null -ne $env_obj) {
            $env_obj.PSObject.Properties | ForEach-Object {
                $docker_args += "-e"
                $docker_args += "$($_.Name)=$($_.Value)"
            }
        }
    }

    if ($NeedsToken -eq "true" -and -not [string]::IsNullOrEmpty($env:GITHUB_TOKEN)) {
        $docker_args += "-e"
        $docker_args += "GITHUB_TOKEN=$env:GITHUB_TOKEN"
    }

    # The scripts directory is inside the mount but at a different absolute path,
    # so translate it; a command referencing %SCRIPTS_ROOT% must resolve inside
    # the container.
    if ($env:CROSS_PR_TESTING -eq "true" -and -not [string]::IsNullOrEmpty($env:CROSS_PR_REPO)) {
        $scriptsInContainer = $env:SCRIPTS_ROOT
        if (-not [string]::IsNullOrEmpty($env:GITHUB_WORKSPACE)) {
            $scriptsInContainer = $env:SCRIPTS_ROOT.Replace($env:GITHUB_WORKSPACE, $workspace)
        }
        $docker_args += @("-e", "SCRIPTS_ROOT=$scriptsInContainer")
        $docker_args += @("-e", "CROSS_PR_REPO=$env:CROSS_PR_REPO")
        $docker_args += @("-e", "CROSS_PR_NUMBER=$env:CROSS_PR_NUMBER")
    }

    $docker_args += @($env:CONTAINER_IMAGE, "cmd", "/s", "/c", $innerCommand)

    Write-Host "Executing: docker $($docker_args -join ' ')"
    & docker @docker_args
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Native execution path
# ---------------------------------------------------------------------------

# This script lives in scripts/matrix. The Swift and Visual Studio installers are
# shared with the legacy workflow and live in scripts/windows, so they are reached
# relative to this script rather than by probing the workspace.
$MatrixRoot = $PSScriptRoot
$WindowsRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "windows"

Write-Host "Matrix scripts: $MatrixRoot"
Write-Host "Windows scripts: $WindowsRoot"

# Import helper functions from install-swift.ps1
. "$WindowsRoot\swift\install-swift.ps1"

# Python comes from the runner image; no caller installs one. Swift 6.1 and
# earlier want 3.9, later toolchains 3.10, and the hosted Windows images ship a
# version new enough for both.
Write-Host "Verifying Python installation..."
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Error "Python is not on PATH; the Windows runner image is expected to provide it."
    exit 1
}
python --version

Write-Host "Installing Visual Studio Build Tools..."
if (-not (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools")) {
    . "$WindowsRoot\install-vsb.ps1"
} else {
    Write-Host "Visual Studio Build Tools already installed, skipping..."
}

# Install Swift. The install scripts are named after the concrete toolchain
# identifier rather than the version label, so "nightly-release" resolves to
# install-swift-nightly-6.4.x.ps1.
$Toolchain = if ([string]::IsNullOrEmpty($env:MATRIX_TOOLCHAIN)) { $SwiftVersion } else { $env:MATRIX_TOOLCHAIN }
Write-Host "Installing Swift $Toolchain..."
$swiftInstallScript = "$WindowsRoot\swift\install-swift-$Toolchain.ps1"
if (Test-Path $swiftInstallScript) {
    . $swiftInstallScript
} else {
    Write-Error "No installation script found for Swift $Toolchain at $swiftInstallScript"
    exit 1
}

Write-Host "Verifying Swift installation..."
swift --version
if ($LASTEXITCODE -ne 0) {
    Write-Error "Swift installation verification failed"
    exit 1
}

Write-Host "Verifying Clang installation..."
clang --version
if ($LASTEXITCODE -ne 0) {
    Write-Error "Clang installation verification failed"
    exit 1
}

# Cross-PR checkout, when enabled. Any failure here fails the job: carrying on
# would test the base branch instead of the linked PRs and report success.
if ($env:CROSS_PR_TESTING -eq "true" -and -not [string]::IsNullOrEmpty($env:CROSS_PR_REPO)) {
    Write-Host "Checking out linked PRs..."
    $crossPrScript = "$env:SCRIPTS_ROOT\cross-pr-checkout.swift"
    if (-not (Test-Path $crossPrScript)) {
        Write-Error "cross-pr-checkout.swift not found at $crossPrScript"
        exit 1
    }
    & swiftc -sdk $env:SDKROOT $crossPrScript -o $env:TEMP\cross-pr-checkout.exe
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to compile cross-pr-checkout.swift"
        exit 1
    }
    & $env:TEMP\cross-pr-checkout.exe $env:CROSS_PR_REPO $env:CROSS_PR_NUMBER
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Cross-PR checkout failed"
        exit 1
    }
}

if (-not [string]::IsNullOrEmpty($EnvJson) -and $EnvJson -ne '{}' -and $EnvJson -ne 'null') {
    Write-Host "Setting custom environment variables..."
    $env_obj = $EnvJson | ConvertFrom-Json
    if ($null -ne $env_obj) {
        $env_obj.PSObject.Properties | ForEach-Object {
            if (-not [string]::IsNullOrEmpty($_.Name) -and -not [string]::IsNullOrEmpty($_.Value)) {
                Write-Host "  $($_.Name)=$($_.Value)"
                Set-Item -Path "env:$($_.Name)" -Value $_.Value
            }
        }
    }
}

# command_arguments may be a JSON array, a plain string, or absent.
$command_args_string = ""
if (-not [string]::IsNullOrEmpty($CommandArguments) -and $CommandArguments -ne 'null' -and $CommandArguments -ne '[]') {
    if ($CommandArguments.Trim().StartsWith('[')) {
        $args_array = $CommandArguments | ConvertFrom-Json
        # Single-quoted, with any single quote doubled: the command is run through
        # Invoke-Expression, which parses the result as PowerShell, and in double
        # quotes an argument holding $ or a backtick would be expanded rather than
        # passed on. The quotes also keep an argument containing whitespace as one
        # argument, which the schema's array type promises it is.
        $command_args_string = ($args_array | ForEach-Object { "'" + ([string]$_).Replace("'", "''") + "'" }) -join ' '
    } else {
        $command_args_string = $CommandArguments
    }
}

$fullCommand = $Command
if (-not [string]::IsNullOrEmpty($command_args_string)) {
    $fullCommand = "$Command $command_args_string"
}

# Invoke-Program propagates a child process's exit code. Dot-sourced rather than
# defined here so that it can be tested on its own, and sourced before the setup
# command runs so that both it and the main command can use it.
. "$MatrixRoot\invoke-program.ps1"

if (-not [string]::IsNullOrEmpty($SetupCommand)) {
    Write-Host "Running setup command: $SetupCommand"
    Invoke-Expression $SetupCommand
    if ($LASTEXITCODE -ne 0) {
        # Write-Host, not Write-Error: an error record makes pwsh print a stack
        # trace for the invocation that failed, which buries the command's own
        # output under a frame pointing at this script.
        Write-Host "::error::Setup command failed with exit code ${LASTEXITCODE}: $SetupCommand"
        exit $LASTEXITCODE
    }
}

Write-Host "Running command: $fullCommand"
Invoke-Expression $fullCommand
if ($LASTEXITCODE -ne 0) {
    Write-Host "::error::Command failed with exit code ${LASTEXITCODE}: $fullCommand"
    exit $LASTEXITCODE
}

Write-Host "Command completed successfully"

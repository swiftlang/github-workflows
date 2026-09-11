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

# Tests for Invoke-Program's exit-code propagation.
#
# A CI step that reports success for a command that failed is the worst kind of
# bug this repository can ship: every adopter believes a green check. Each case
# runs in a child process, because the helper propagates by calling `exit`.
#
# This script leaves $ErrorActionPreference at Continue deliberately. Under Stop,
# PowerShell 7.3 and later can raise when a native command exits non-zero, which
# would abort the test run before it could read the exit code it is asserting on.

$helper = (Resolve-Path (Join-Path $PSScriptRoot "../.github/workflows/scripts/matrix/invoke-program.ps1")).Path
$failures = 0

# Runs a snippet in a child pwsh with the helper dot-sourced, and returns its exit
# code.
function Get-ExitCode {
    param(
        [string]$Snippet,
        [string]$ChildErrorActionPreference = "Stop"
    )

    $script = @"
`$ErrorActionPreference = '$ChildErrorActionPreference'
. '$helper'
$Snippet
"@

    # pwsh -File insists on a .ps1 extension.
    $file = Join-Path ([System.IO.Path]::GetTempPath()) ("invoke-program-test-" + [System.Guid]::NewGuid().ToString() + ".ps1")
    Set-Content -LiteralPath $file -Value $script

    # Guard against a native non-zero exit being turned into an exception.
    $previous = $null
    if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
        $previous = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
    }
    try {
        & pwsh -NoLogo -NoProfile -File $file *> $null
        return $LASTEXITCODE
    } finally {
        if ($null -ne $previous) {
            $PSNativeCommandUseErrorActionPreference = $previous
        }
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
}

function Assert-ExitCode([string]$What, [int]$Expected, [int]$Actual) {
    if ($Expected -ne $Actual) {
        Write-Host "  FAIL $What : expected exit $Expected, got $Actual"
        $script:failures++
    } else {
        Write-Host "  ok   $What"
    }
}

# A command that exits non-zero must fail the script with the same code.
Assert-ExitCode "non-zero exit code propagates" 3 (Get-ExitCode -Snippet 'Invoke-Program cmd /c "exit 3"')

# A command that succeeds must not fail the script.
Assert-ExitCode "zero exit code passes through" 0 (Get-ExitCode -Snippet 'Invoke-Program cmd /c "exit 0"')

# A callable that fails without setting an exit code - which is what a program
# that never launches looks like - must still fail the script. `exit $null`
# exits 0, so only the $? fallback can catch it.
Assert-ExitCode "failure with no exit code fails" 1 (Get-ExitCode -Snippet 'Invoke-Program Get-Item "/definitely/does/not/exist"' -ChildErrorActionPreference "Continue")

# A stale exit code from an earlier command must not be attributed to this one.
Assert-ExitCode "stale exit code is not reused" 0 (Get-ExitCode -Snippet '$global:LASTEXITCODE = 9; Invoke-Program cmd /c "exit 0"')

if ($failures -gt 0) {
    Write-Host ""
    Write-Host "$failures failed"
    exit 1
}
Write-Host ""
Write-Host "all passed"

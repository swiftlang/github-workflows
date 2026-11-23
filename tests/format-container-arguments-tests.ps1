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

# Tests for Format-ContainerCommandArguments.
#
# A command run in a container is a `cmd /s /c` string that docker.exe escapes on
# its way in. A quoted argument arrives with literal quote characters in it, so
# `swift test "-Xswiftc"` fails with `unexpected arguments: '"-Xswiftc"'`. These
# cases pin what the formatter writes and that what it writes reaches a program
# unchanged.
#
# The round trip starts cmd.exe from .NET with the command as one argument, which
# escapes embedded quotes with backslashes the way docker does. PowerShell's own
# call to cmd.exe would not: it passes cmd.exe's arguments through unescaped.

$helper = (Resolve-Path (Join-Path $PSScriptRoot "../.github/workflows/scripts/matrix/format-container-arguments.ps1")).Path
. $helper

$failures = 0

function Assert-Equal([string]$What, [string]$Expected, [string]$Actual) {
    if ($Expected -ne $Actual) {
        Write-Host "  FAIL $What"
        Write-Host "       expected: $Expected"
        Write-Host "       actual:   $Actual"
        $script:failures++
    } else {
        Write-Host "  ok   $What"
    }
}

function Assert-Throws([string]$What, [scriptblock]$Action) {
    $threw = $false
    try {
        & $Action
    } catch {
        $threw = $true
    }
    if (-not $threw) {
        Write-Host "  FAIL $What : expected an error, got none"
        $script:failures++
    } else {
        Write-Host "  ok   $What"
    }
}

# Runs `$InnerCommand` as a container would: cmd.exe /s /c with the command as a
# single escaped argument. Returns what the command wrote to standard output.
function Invoke-LikeContainer([string]$InnerCommand) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new("cmd.exe")
    foreach ($argument in @("/s", "/c", $InnerCommand)) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $standardError = $process.StandardError.ReadToEndAsync()
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        Write-Host "       cmd exited $($process.ExitCode): $($standardError.Result)"
    }
    return $standardOutput.Trim()
}

# The flags from the adopter whose job failed.
$flags = @(
    "-Xswiftc", "-warnings-as-errors",
    "--explicit-target-dependency-import-check", "error",
    "-Xswiftc", "-require-explicit-sendable"
)

Assert-Equal "plain arguments are written bare" `
    "-Xswiftc -warnings-as-errors --explicit-target-dependency-import-check error -Xswiftc -require-explicit-sendable" `
    (Format-ContainerCommandArguments $flags)

Assert-Equal "a single argument is written bare" "release" (Format-ContainerCommandArguments @("release"))

Assert-Equal "no arguments write nothing" "" (Format-ContainerCommandArguments @())

Assert-Equal "paths and assignments are plain" `
    "-DFOO=bar --package-path C:\source\Sub/dir" `
    (Format-ContainerCommandArguments @("-DFOO=bar", "--package-path", "C:\source\Sub/dir"))

# Characters that look special but that cmd leaves alone, as in a test filter.
Assert-Equal "filter patterns are plain" `
    ".*Tests Foo/bar() `$HOME 'quoted' a*b?c [x]{y}#~!" `
    (Format-ContainerCommandArguments @(".*Tests", "Foo/bar()", "`$HOME", "'quoted'", "a*b?c", "[x]{y}#~!"))

# An argument that needs quoting cannot be passed on, so it must be refused:
# otherwise the command runs with an argument the caller did not write.
Assert-Throws "whitespace is refused" { Format-ContainerCommandArguments @("two words") }
Assert-Throws "a tab is refused" { Format-ContainerCommandArguments @("a`tb") }
Assert-Throws "a trailing newline is refused" { Format-ContainerCommandArguments @("release`n") }
Assert-Throws "an embedded newline is refused" { Format-ContainerCommandArguments @("a`nb") }
Assert-Throws "an ampersand is refused" { Format-ContainerCommandArguments @("a&b") }
Assert-Throws "a pipe is refused" { Format-ContainerCommandArguments @("a|b") }
Assert-Throws "a redirection is refused" { Format-ContainerCommandArguments @("a>b") }
Assert-Throws "an input redirection is refused" { Format-ContainerCommandArguments @("a<b") }
Assert-Throws "a caret is refused" { Format-ContainerCommandArguments @("a^b") }
Assert-Throws "variable expansion is refused" { Format-ContainerCommandArguments @("%PATH%") }
Assert-Throws "a double quote is refused" { Format-ContainerCommandArguments @('a"b') }
Assert-Throws "a non-ASCII character is refused" { Format-ContainerCommandArguments @("T$([char]0x00EB)st") }
Assert-Throws "an empty argument is refused" { Format-ContainerCommandArguments @("") }
Assert-Throws "a null argument is refused" { Format-ContainerCommandArguments @($null) }

if ($IsWindows) {
    # The probe prints its arguments joined with `|`, so the test reads exactly
    # what the program received. Its path is written into the command unquoted, so
    # it must hold no whitespace.
    $probe = Join-Path ([System.IO.Path]::GetTempPath()) ("argument-probe-" + [System.Guid]::NewGuid().ToString() + ".ps1")
    if ($probe -match '\s') {
        Write-Host "  FAIL the temporary directory path holds whitespace: $probe"
        $failures++
    } else {
        Set-Content -LiteralPath $probe -Value '[Console]::Out.Write([string]::Join("|", $args))'
        try {
            $probeCommand = "pwsh -NoLogo -NoProfile -File $probe"

            Assert-Equal "a program receives the formatted arguments unchanged" `
                ($flags -join "|") `
                (Invoke-LikeContainer "$probeCommand $(Format-ContainerCommandArguments $flags)")

            # Control: quoting each argument must corrupt it on this path; otherwise
            # the refusals above guard against nothing, and this case says so.
            $quoted = ($flags | ForEach-Object { '"' + $_ + '"' }) -join " "
            Assert-Equal "quoted arguments arrive with their quotes (the failure being avoided)" `
                (($flags | ForEach-Object { '"' + $_ + '"' }) -join "|") `
                (Invoke-LikeContainer "$probeCommand $quoted")
        } finally {
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "  skip the round trip through cmd.exe: not Windows"
}

if ($failures -gt 0) {
    Write-Host ""
    Write-Host "$failures failed"
    exit 1
}
Write-Host ""
Write-Host "all passed"

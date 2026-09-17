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

# Runs a program and exits the script with its exit code if it is non-zero.
#
# PowerShell does not propagate a child process's exit code on its own, and the
# obvious `exit $LASTEXITCODE` is not enough: when a command fails to launch at
# all - a broken toolchain, a missing executable - no exit code is set, so
# $LASTEXITCODE stays $null, `exit $null` exits 0, and the failure is reported as
# success. So reset it before the call and fall back to $? when nothing set it.
#
# Available to setup_command and command values in a matrix entry.
function Invoke-Program($Executable) {
    $global:LASTEXITCODE = $null
    & $Executable @args
    $ok = $?
    if ($null -eq $LASTEXITCODE) {
        if (-not $ok) {
            exit 1
        }
    } elseif ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2024 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

function Install-Swift {
    param (
        [string]$Url,
        [string]$Sha256
    )
    Set-Variable ErrorActionPreference Stop
    Set-Variable ProgressPreference SilentlyContinue
    Write-Host -NoNewLine ('Downloading {0} ... ' -f $url)
    try {
        # Use curl with retry logic (10 retries with exponential backoff starting at 1 second)
        # --retry-all-errors ensures we retry on transfer failures (e.g., exit code 18)
        # -C - enables resume for partial downloads
        $exitCode = (Start-Process -FilePath "curl" -ArgumentList @(
            "--retry", "10",
            "--retry-delay", "1",
            "--retry-all-errors",
            "--retry-max-time", "300",
            "--location",
            "-C", "-",
            "--output", "installer.exe",
            $url
        ) -Wait -PassThru -NoNewWindow).ExitCode

        if ($exitCode -ne 0) {
            throw "curl failed with exit code $exitCode"
        }
        Write-Host 'SUCCESS'
    }
    catch {
        Write-Host "FAILED: $($_.Exception.Message)"
        exit 1
    }
    Write-Host -NoNewLine ('Verifying SHA256 ({0}) ... ' -f $Sha256)
    $Hash = Get-FileHash installer.exe -Algorithm sha256
    if ($Hash.Hash -eq $Sha256 -or $Sha256 -eq "") {
        Write-Host 'SUCCESS'
    } else {
        Write-Host ('FAILED ({0})' -f $Hash.Hash)
        exit 1
    }
    Write-Host -NoNewLine 'Installing Swift ... '
    $Process = Start-Process installer.exe -Wait -PassThru -NoNewWindow -ArgumentList @(
        '/quiet',
        '/norestart'
    )
    if ($Process.ExitCode -eq 0) {
        Write-Host 'SUCCESS'
    } else {
        Write-Host ('FAILED ({0})' -f $Process.ExitCode)
        exit 1
    }
    Remove-Item -Force installer.exe
}
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
    $MaxRetries = 10
    $BaseDelay = 1
    $Attempt = 0
    $Success = $false

    while (-not $Success -and $Attempt -lt $MaxRetries) {
        $Attempt++
        try {
            Invoke-WebRequest -Uri $url -OutFile installer.exe
            $Success = $true
            Write-Host 'SUCCESS'
        }
        catch {
            if ($Attempt -eq $MaxRetries) {
                Write-Host "FAILED after $MaxRetries attempts: $($_.Exception.Message)"
                exit 1
            }

            # Calculate exponential backoff delay (2^attempt * base delay)
            $Delay = $BaseDelay * [Math]::Pow(2, $Attempt - 1)
            Write-Host "Attempt $Attempt failed, retrying in $Delay seconds..."
            Start-Sleep -Seconds $Delay
        }
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
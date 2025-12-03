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

# Retry configuration
$MaxRetries = 5
$RetryDelay = 5

function Invoke-WebRequestWithRetry {
    param (
        [string]$Uri,
        [string]$OutFile,
        [int]$TimeoutSec = 300
    )
    
    $attempt = 1
    
    while ($attempt -le $MaxRetries) {
        try {
            if ($attempt -gt 1) {
                Write-Host "Retry attempt $attempt of $MaxRetries after ${RetryDelay}s delay..."
                Start-Sleep -Seconds $RetryDelay
            }
            
            # Use -Resume to support partial downloads if the connection drops
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -TimeoutSec $TimeoutSec -UseBasicParsing
            
            Write-Host "Download completed successfully"
            return $true
        }
        catch {
            Write-Host "Download failed on attempt $attempt`: $($_.Exception.Message)"
            
            # Clean up partial download if it exists
            if (Test-Path $OutFile) {
                Remove-Item -Force $OutFile -ErrorAction SilentlyContinue
            }
            
            if ($attempt -eq $MaxRetries) {
                Write-Host "Download failed after $MaxRetries attempts"
                throw
            }
        }
        
        $attempt++
    }
    
    return $false
}

function Install-Swift {
    param (
        [string]$Url,
        [string]$Sha256
    )
    Set-Variable ErrorActionPreference Stop
    Set-Variable ProgressPreference SilentlyContinue
    
    Write-Host "Downloading $Url ... "
    
    try {
        Invoke-WebRequestWithRetry -Uri $Url -OutFile installer.exe
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
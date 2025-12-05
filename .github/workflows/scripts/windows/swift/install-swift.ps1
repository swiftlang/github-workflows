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

            Write-Host "Attempt $attempt`: Downloading from $Uri"

            # Clean up any existing partial download
            if (Test-Path $OutFile) {
                Remove-Item -Force $OutFile -ErrorAction SilentlyContinue
            }

            # Get expected file size from HTTP headers
            $headRequest = Invoke-WebRequest -Uri $Uri -Method Head -UseBasicParsing -TimeoutSec 30
            $expectedSize = $null
            if ($headRequest.Headers.ContainsKey('Content-Length')) {
                $expectedSize = [long]$headRequest.Headers['Content-Length'][0]
                Write-Host "Expected file size: $($expectedSize / 1MB) MB"
            }

            # Download with progress tracking disabled for better performance
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($Uri, $OutFile)
            $webClient.Dispose()

            # Verify file exists and has content
            if (-not (Test-Path $OutFile)) {
                throw "Download completed but file not found at $OutFile"
            }

            $actualSize = (Get-Item $OutFile).Length
            Write-Host "Downloaded file size: $($actualSize / 1MB) MB"

            # Verify file size matches expected size
            if ($expectedSize -and $actualSize -ne $expectedSize) {
                throw "File size mismatch. Expected: $expectedSize bytes, Got: $actualSize bytes"
            }

            # Verify file is not corrupted by checking if it's a valid PE executable
            $fileBytes = [System.IO.File]::ReadAllBytes($OutFile)
            if ($fileBytes.Length -lt 2 -or $fileBytes[0] -ne 0x4D -or $fileBytes[1] -ne 0x5A) {
                throw "Downloaded file is not a valid executable (missing MZ header)"
            }

            Write-Host "Download completed and verified successfully"
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

function Remove-FileWithRetry {
    param (
        [string]$Path
    )

    $attempt = 1

    while ($attempt -le $MaxRetries) {
        try {
            if (Test-Path $Path) {
                Remove-Item -Force $Path -ErrorAction Stop
                Write-Host "Successfully removed $Path"
                return $true
            } else {
                return $true
            }
        }
        catch {
            if ($attempt -eq $MaxRetries) {
                Write-Host "Warning: Failed to remove $Path after $MaxRetries attempts: $($_.Exception.Message)"
                Write-Host "The file may be locked by another process. It will be cleaned up later."
                return $false
            }

            Write-Host "Attempt $attempt to remove $Path failed, retrying in ${RetryDelay}s..."
            Start-Sleep -Seconds $RetryDelay
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
        Remove-FileWithRetry -Path installer.exe
        exit 1
    }
    
    Write-Host -NoNewLine ('Verifying SHA256 ({0}) ... ' -f $Sha256)
    $Hash = Get-FileHash installer.exe -Algorithm sha256
    if ($Hash.Hash -eq $Sha256 -or $Sha256 -eq "") {
        Write-Host 'SUCCESS'
    } else {
        Write-Host ('FAILED ({0})' -f $Hash.Hash)
        Remove-FileWithRetry -Path installer.exe
        exit 1
    }
    Write-Host -NoNewLine 'Installing Swift ... '
    try {
        $Process = Start-Process installer.exe -Wait -PassThru -NoNewWindow -ArgumentList @(
            '/quiet',
            '/norestart'
        )
        if ($Process.ExitCode -eq 0) {
            Write-Host 'SUCCESS'
        } else {
            Write-Host ('FAILED ({0})' -f $Process.ExitCode)
            Remove-FileWithRetry -Path installer.exe
            exit 1
        }
    }
    catch {
        Write-Host "FAILED: $($_.Exception.Message)"
        Remove-FileWithRetry -Path installer.exe
        exit 1
    }
    Remove-FileWithRetry -Path installer.exe
    
    Write-Host -NoNewLine 'Adding Swift to PATH ... '
    # Older toolchains modify the Machine PATH to include \Library\Developer\Toolchains
    foreach ($Item in [Environment]::GetEnvironmentVariables('Machine')['Path'].Split(';')) {
        if ($Item.Contains('Swift') -or $Item.Contains('Library\Developer\Toolchains')) {
            GitHubActions-AddPath -Item $Item
        }
    }
    # Newer toolchains modify the User PATH to include a path to a Swift directory
    foreach ($Item in [Environment]::GetEnvironmentVariables('User')['Path'].Split(';')) {
        if ($Item.Contains('Swift')) {
            GitHubActions-AddPath -Item $Item
        }
    }
    # Find and export the SDKROOT environment variable
    $MachineSDKROOT = [Environment]::GetEnvironmentVariables('Machine')['SDKROOT']
    $UserSDKROOT = [Environment]::GetEnvironmentVariables('User')['SDKROOT']
    if ($MachineSDKROOT) {
        GitHubActions-ExportVariable -Name "SDKROOT" -Value $MachineSDKROOT
    } elseif ($UserSDKROOT) {
        GitHubActions-ExportVariable -Name "SDKROOT" -Value $UserSDKROOT
    }
    Write-Host 'SUCCESS'
}

function GitHubActions-AddPath {
    param (
        [string]$Item
    )
    $FilePath = $env:GITHUB_PATH
    if ($FilePath) {
        Add-Content -Path "$FilePath" -Value "$Item`r`n"
    }
    $env:Path = $Item + ";" + $env:Path
}

function GitHubActions-ExportVariable {
    param (
        [string]$Name,
        [string]$Value
    )
    $FilePath = $env:GITHUB_ENV
    if ($FilePath) {
        Add-Content -Path "$FilePath" -Value "$Name=$Value`r`n"
    }
    Set-Content env:\$Name $Value
}

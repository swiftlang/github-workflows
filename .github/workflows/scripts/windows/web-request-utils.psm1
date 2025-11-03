# WebRequestUtils.psm1
# Shared utilities for web requests with retry logic

<#
.SYNOPSIS
Invokes a web request with retry logic and exponential backoff.

.DESCRIPTION
Attempts to download a file from a URL with automatic retry on failure.
Uses exponential backoff to handle transient network failures.

.PARAMETER Uri
The URL to download from.

.PARAMETER OutFile
The destination file path for the download.

.PARAMETER MaxRetries
Maximum number of retry attempts (default: 10).

.PARAMETER BaseDelay
Base delay in seconds for exponential backoff (default: 1).

.EXAMPLE
Invoke-WebRequestWithRetry -Uri "https://example.com/file.exe" -OutFile "file.exe"

.EXAMPLE
Invoke-WebRequestWithRetry -Uri "https://example.com/file.exe" -OutFile "file.exe" -MaxRetries 5 -BaseDelay 2
#>
function Invoke-WebRequestWithRetry {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Uri,

        [Parameter(Mandatory=$true)]
        [string]$OutFile,

        [int]$MaxRetries = 10,

        [int]$BaseDelay = 1
    )

    $Attempt = 0
    $Success = $false

    while (-not $Success -and $Attempt -lt $MaxRetries) {
        $Attempt++
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile
            $Success = $true
            Write-Host 'SUCCESS'
        }
        catch {
            if ($Attempt -eq $MaxRetries) {
                Write-Host "FAILED after $MaxRetries attempts: $($_.Exception.Message)"
                throw
            }

            # Calculate exponential backoff delay (2^attempt * base delay)
            $Delay = $BaseDelay * [Math]::Pow(2, $Attempt - 1)
            Write-Host "Attempt $Attempt failed, retrying in $Delay seconds..."
            Start-Sleep -Seconds $Delay
        }
    }
}

Export-ModuleMember -Function Invoke-WebRequestWithRetry

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

Import-Module $PSScriptRoot\web-request-utils.psm1

$VSB='https://download.visualstudio.microsoft.com/download/pr/5536698c-711c-4834-876f-2817d31a2ef2/c792bdb0fd46155de19955269cac85d52c4c63c23db2cf43d96b9390146f9390/vs_BuildTools.exe'
$VSB_SHA256='C792BDB0FD46155DE19955269CAC85D52C4C63C23DB2CF43D96B9390146F9390'
Set-Variable ErrorActionPreference Stop
Set-Variable ProgressPreference SilentlyContinue
Write-Host -NoNewLine ('Downloading {0} ... ' -f ${VSB})
try {
    Invoke-WebRequestWithRetry -Uri $VSB -OutFile $env:TEMP\vs_buildtools.exe
}
catch {
    exit 1
}
Write-Host -NoNewLine ('Verifying SHA256 ({0}) ... ' -f $VSB_SHA256)
$Hash = Get-FileHash $env:TEMP\vs_buildtools.exe -Algorithm sha256
if ($Hash.Hash -eq $VSB_SHA256) {
    Write-Host 'SUCCESS'
} else {
    Write-Host  ('FAILED ({0})' -f $Hash.Hash)
    exit 1
}
Write-Host -NoNewLine 'Installing Visual Studio Build Tools ... '
$Process =
    Start-Process $env:TEMP\vs_buildtools.exe -Wait -PassThru -NoNewWindow -ArgumentList @(
        '--quiet',
        '--wait',
        '--norestart',
        '--nocache',
        '--add', 'Microsoft.VisualStudio.Component.Windows11SDK.22000',
        '--add', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
    )
if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 3010) {
    Write-Host 'SUCCESS'
} else {
    Write-Host  ('FAILED ({0})' -f $Process.ExitCode)
    exit 1
}
Remove-Item -Force $env:TEMP\vs_buildtools.exe
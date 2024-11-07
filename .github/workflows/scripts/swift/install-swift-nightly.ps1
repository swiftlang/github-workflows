. $PSScriptRoot\install-swift.ps1

$SWIFT_RELEASE_METADATA='http://download.swift.org/development/windows10/latest-build.json'
$Release = curl.exe -sL ${SWIFT_RELEASE_METADATA}
$SWIFT_URL = "https://download.swift.org/development/windows10/$($($Release | ConvertFrom-JSON).dir)/$($($Release | ConvertFrom-JSON).download)"

Install-Swift -Url $SWIFT_URL -Sha256 ""
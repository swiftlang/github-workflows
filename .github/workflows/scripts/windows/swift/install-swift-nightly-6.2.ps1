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
. $PSScriptRoot\install-swift.ps1

if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq "Arm64") {
    # FIXME: http://download.swift.org/swift-6.2-branch/windows10-arm64/latest-build.json is currently missing on the server
    #$swiftOSVersion = 'windows10-arm64'
    $swiftOSVersion = 'windows10'
} else {
    $swiftOSVersion = 'windows10'
}

$SWIFT_RELEASE_METADATA="https://download.swift.org/swift-6.2-branch/$swiftOSVersion/latest-build.json"
$Release = curl.exe -sL ${SWIFT_RELEASE_METADATA}
$SWIFT_URL = "https://download.swift.org/swift-6.2-branch/$swiftOSVersion/$($($Release | ConvertFrom-JSON).dir)/$($($Release | ConvertFrom-JSON).download)"

Install-Swift -Url $SWIFT_URL -Sha256 ""
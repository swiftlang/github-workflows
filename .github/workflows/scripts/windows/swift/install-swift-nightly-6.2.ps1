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

$SWIFT_RELEASE_METADATA='http://download.swift.org/swift-6.2-branch/windows10/latest-build.json'
$Release = curl.exe -sL ${SWIFT_RELEASE_METADATA}
$SWIFT_URL = "https://download.swift.org/swift-6.2-branch/windows10/$($($Release | ConvertFrom-JSON).dir)/$($($Release | ConvertFrom-JSON).download)"

Install-Swift -Url $SWIFT_URL -Sha256 ""
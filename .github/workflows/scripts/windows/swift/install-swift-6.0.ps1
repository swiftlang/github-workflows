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

$SWIFT='https://download.swift.org/swift-6.0.2-release/windows10/swift-6.0.2-RELEASE/swift-6.0.2-RELEASE-windows10.exe'
$SWIFT_SHA256='516FE8E64713BD92F03C01E5198011B74A27F8C1C88627607A2F421718636126'

Install-Swift -Url $SWIFT -Sha256 $SWIFT_SHA256
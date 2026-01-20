##===----------------------------------------------------------------------===//
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2026 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===//

add_library(Target1
  "Target1.swift"
)
target_include_directories(Target1 PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR})

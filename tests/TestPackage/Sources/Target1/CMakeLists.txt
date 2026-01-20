add_library(Target1
  "Target1.swift"
)
target_include_directories(Target1 PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR})

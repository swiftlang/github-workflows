add_library(Target2
  "Target2.swift"
)
target_include_directories(Target2 PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(Target2 PUBLIC
  Target1)

cmake_minimum_required(VERSION 4.0)
project(Sample C Swift)

# Swift links against the release DLL C runtime on Windows. Build C with the same runtime so the
# linked executable does not mix it with the debug one.
set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)

add_executable(sample main.c)

# A C library that uses the C runtime and is imported and linked by Swift, so the C compiler must
# produce code Swift can link against.
add_library(CSample STATIC CSample/CSample.c)
target_include_directories(CSample PUBLIC CSample/include)
add_executable(SwiftSample main.swift)
target_link_libraries(SwiftSample PRIVATE CSample)

# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(albedo_dart_library VERSION 0.0.1 LANGUAGES C)

set(ALBEDO_DART_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/albedo_dart.h")

if (WIN32)
  # Use prebuilt Windows libraries shipped with the plugin.
  add_library(albedo_dart SHARED IMPORTED GLOBAL)
  set_target_properties(albedo_dart PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../windows/albedo.dll"
    IMPORTED_IMPLIB "${CMAKE_CURRENT_SOURCE_DIR}/../windows/albedo.lib"
    PUBLIC_HEADER "${ALBEDO_DART_HEADER}"
    OUTPUT_NAME "albedo"
  )
else()
  # Fallback target for non-Windows platforms to satisfy plugin build steps.
  add_library(albedo_dart INTERFACE)
  set_target_properties(albedo_dart PROPERTIES
    PUBLIC_HEADER "${ALBEDO_DART_HEADER}"
  )
endif()

target_include_directories(albedo_dart INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(albedo_dart INTERFACE DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(albedo_dart INTERFACE "-Wl,-z,max-page-size=16384")
endif()

# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(albedo_dart_library VERSION 0.0.1 LANGUAGES C)

add_library(albedo_dart SHARED
  "albedo_dart.c"
)

set_target_properties(albedo_dart PROPERTIES
  PUBLIC_HEADER albedo_dart.h
  OUTPUT_NAME "albedo_dart"
)

target_compile_definitions(albedo_dart PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(albedo_dart PRIVATE "-Wl,-z,max-page-size=16384")
endif()

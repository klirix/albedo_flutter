#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint albedo_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'albedo_flutter'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # Sources live under the Swift Package Manager layout. albedo_dart.h is a
  # symlink to ../../../src/albedo_dart.h (the canonical C API header), so the
  # forwarder C file pulls in the real declarations without duplicating them.
  s.source           = { :path => '.' }
  s.source_files = 'albedo_flutter/Sources/albedo_flutter/**/*'
  s.public_header_files = 'albedo_flutter/Sources/albedo_flutter/**/*.h'
  s.static_framework = true
  s.vendored_frameworks = 'Frameworks/albedo.xcframework'

  s.platform = :osx, '10.13'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end

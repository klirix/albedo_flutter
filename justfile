[working-directory: 'albedo']
build-android:
    #!/usr/bin/env sh
    set -e
    : "${ZIG:=zig}"
    : "${ANDROID_HOME:?Set ANDROID_HOME to your SDK root, e.g. ~/Library/Android/sdk}"
    "$ZIG" build -Dtarget=aarch64-linux-android -DandroidSDK="$ANDROID_HOME" --release=fast --prefix-lib-dir jniLibs/arm64-v8a
    "$ZIG" build -Dtarget=arm-linux-android -DandroidSDK="$ANDROID_HOME" --release=fast --prefix-lib-dir jniLibs/armeabi-v7a
    "$ZIG" build -Dtarget=x86_64-linux-android -DandroidSDK="$ANDROID_HOME" --release=fast --prefix-lib-dir jniLibs/x86_64
    cp -r zig-out/jniLibs ../android/src/main

[working-directory: 'albedo']
repack-ar path:
    #!/usr/bin/env sh
    set -e
    abspath="$(cd "$(dirname "{{path}}")" && pwd)/$(basename "{{path}}")"
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && ar x "$abspath")
    chmod 644 "$tmpdir"/*.o
    libtool -static -o "$abspath" "$tmpdir"/*.o
    rm -rf "$tmpdir"

[working-directory: 'albedo']
build-ios:
    zig build -Dstatic -Dtarget=aarch64-ios-simulator --release=fast --prefix-lib-dir lib/arm-sim 
    zig build -Dstatic -Dtarget=aarch64-ios --release=fast --prefix-lib-dir lib/arm
    zig build -Dstatic -Dtarget=x86_64-ios-simulator --release=fast --prefix-lib-dir lib/x86
    just repack-ar zig-out/lib/arm-sim/libalbedo.a
    just repack-ar zig-out/lib/arm/libalbedo.a
    just repack-ar zig-out/lib/x86/libalbedo.a
    lipo zig-out/lib/arm-sim/libalbedo.a zig-out/lib/x86/libalbedo.a -output zig-out/lib/arm-sim/libalbedo.a -create
    xcodebuild -create-xcframework -library zig-out/lib/arm/libalbedo.a -library zig-out/lib/arm-sim/libalbedo.a -output albedo.xcframework
    rm -rf zig-out/lib/x86
    rm -rf zig-out/lib/arm
    rm -rf zig-out/lib/arm-sim
    rm -rf ../ios/Frameworks/albedo.xcframework
    mv albedo.xcframework ../ios/Frameworks/

[working-directory: 'albedo']
build-macos:
    zig build -Dtarget=x86_64-macos --release=fast --prefix-lib-dir lib/x86 
    zig build -Dtarget=aarch64-macos --release=fast --prefix-lib-dir lib/arm
    lipo -create -output zig-out/lib/libalbedo.dylib zig-out/lib/arm/libalbedo.dylib zig-out/lib/x86/libalbedo.dylib
    rm -rf zig-out/lib/x86
    rm -rf zig-out/lib/arm
    mv zig-out/lib/libalbedo.dylib ../macos/Classes/

[working-directory: 'albedo']
build-linux:
    zig build -Dtarget=x86_64-linux --release=fast --prefix-lib-dir lib/x86 
    mv zig-out/lib/x86/libalbedo.so ../linux

[working-directory: 'albedo']
build-windows:
    zig build -Dtarget=x86_64-windows -Dstatic=false
    mv zig-out/bin/albedo.* ../windows/
    mv zig-out/lib/albedo.lib ../windows/

build: build-android build-ios build-macos

test:
    ALBEDO_DYLIB_PATH=$(pwd)/macos/Classes/libalbedo.dylib dart test test/
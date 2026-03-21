[working-directory: 'albedo']
build-android:
    zig build -Dtarget=aarch64-linux-android --release=fast --prefix-lib-dir jniLibs/arm64-v8a
    zig build -Dtarget=arm-linux-android --release=fast --prefix-lib-dir jniLibs/armeabi-v7a
    zig build -Dtarget=x86_64-linux-android --release=fast --prefix-lib-dir jniLibs/x86_64
    cp -r zig-out/jniLibs ../android/src/main

[working-directory: 'albedo']
build-ios:
    zig build -Dstatic -Dtarget=aarch64-ios-simulator --release=fast --prefix-lib-dir lib/arm-sim 
    zig build -Dstatic -Dtarget=aarch64-ios --release=fast --prefix-lib-dir lib/arm
    zig build -Dstatic -Dtarget=x86_64-ios-simulator --release=fast --prefix-lib-dir lib/x86
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
# Memory Pressure Generator

The primary intendent use case is to trigger LMK crashes in Android apps for development purposes.

## Build

Example for Mac M1:

`/Users/alehkot/Library/Android/sdk/ndk/26.2.11394342/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android30-clang memory_pressure_generator.c -o memory_pressure_generator`

## Push to Emulator

`adb push memory_pressure_generator /data/local/tmp/`

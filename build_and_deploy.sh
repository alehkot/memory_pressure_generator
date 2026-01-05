#!/bin/bash

# Build and Deploy Memory Pressure Generator to Android Emulator
# Usage: ./build_and_deploy.sh [ndk_path]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Memory Pressure Generator - Build & Deploy Script         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

# Determine NDK path
if [ -n "$1" ]; then
    NDK_PATH="$1"
elif [ -n "$ANDROID_NDK_HOME" ]; then
    NDK_PATH="$ANDROID_NDK_HOME"
elif [ -d "$HOME/Library/Android/sdk/ndk" ]; then
    # Mac default location
    NDK_PATH=$(find "$HOME/Library/Android/sdk/ndk" -maxdepth 1 -type d | sort -V | tail -n 1)
elif [ -d "$HOME/Android/Sdk/ndk" ]; then
    # Linux default location
    NDK_PATH=$(find "$HOME/Android/Sdk/ndk" -maxdepth 1 -type d | sort -V | tail -n 1)
else
    echo -e "${RED}Error: Could not find Android NDK${NC}"
    echo "Please provide NDK path as argument or set ANDROID_NDK_HOME"
    echo "Usage: $0 [ndk_path]"
    exit 1
fi

echo -e "${YELLOW}Using NDK:${NC} $NDK_PATH"

# Determine compiler
if [ -f "$NDK_PATH/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android30-clang" ]; then
    COMPILER="$NDK_PATH/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android30-clang"
elif [ -f "$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang" ]; then
    COMPILER="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang"
else
    echo -e "${RED}Error: Could not find aarch64-linux-android30-clang${NC}"
    exit 1
fi

echo -e "${YELLOW}Using Compiler:${NC} $COMPILER"
echo

# Build enhanced version
echo -e "${GREEN}Building enhanced memory pressure generator...${NC}"
$COMPILER memory_pressure_generator_enhanced.c -o memory_pressure_generator_enhanced
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Build successful: memory_pressure_generator_enhanced${NC}"
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi

# Build original version
echo -e "${GREEN}Building original memory pressure generator...${NC}"
$COMPILER memory_pressure_generator.c -o memory_pressure_generator
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Build successful: memory_pressure_generator${NC}"
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi

echo

# Check if device/emulator is connected
echo -e "${YELLOW}Checking for connected devices...${NC}"
ADB_DEVICES=$(adb devices | grep -v "List" | grep "device$" | wc -l)
if [ "$ADB_DEVICES" -eq 0 ]; then
    echo -e "${RED}Error: No device or emulator connected${NC}"
    echo "Please start an emulator or connect a device and try again"
    exit 1
fi

echo -e "${GREEN}Found $ADB_DEVICES device(s)${NC}"
echo

# Push to device
echo -e "${GREEN}Deploying to device/emulator...${NC}"
adb push memory_pressure_generator_enhanced /data/local/tmp/
adb push memory_pressure_generator /data/local/tmp/

# Make executable
adb shell chmod 755 /data/local/tmp/memory_pressure_generator_enhanced
adb shell chmod 755 /data/local/tmp/memory_pressure_generator

echo -e "${GREEN}✓ Deployment complete!${NC}"
echo
echo -e "${YELLOW}To run the enhanced version:${NC}"
echo "  adb shell"
echo "  cd /data/local/tmp"
echo "  ./memory_pressure_generator_enhanced 1500 20 100 --use-mlock"
echo
echo -e "${YELLOW}To run with monitoring:${NC}"
echo "  adb shell /data/local/tmp/memory_pressure_generator_enhanced 1500 20 100 --use-mlock"
echo
echo -e "${YELLOW}In another terminal, monitor LMK activity:${NC}"
echo "  adb logcat | grep -i lmk"
echo

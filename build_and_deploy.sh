#!/bin/bash

# Build and Deploy Memory Pressure Generator to Android Emulator
# Usage: ./build_and_deploy.sh [ndk_path] [architecture]
# Architecture: auto (default), arm64, x86_64, or all

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Memory Pressure Generator - Build & Deploy Script         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

# Parse arguments
NDK_PATH_ARG="$1"
ARCH_ARG="${2:-auto}"

# Determine NDK path
if [ -n "$NDK_PATH_ARG" ] && [ "$NDK_PATH_ARG" != "auto" ] && [ "$NDK_PATH_ARG" != "arm64" ] && [ "$NDK_PATH_ARG" != "x86_64" ] && [ "$NDK_PATH_ARG" != "all" ]; then
    NDK_PATH="$NDK_PATH_ARG"
elif [ -n "$ANDROID_NDK_HOME" ]; then
    NDK_PATH="$ANDROID_NDK_HOME"
elif [ -d "$HOME/Library/Android/sdk/ndk" ]; then
    # Mac default location
    NDK_PATH=$(find "$HOME/Library/Android/sdk/ndk" -maxdepth 1 -type d -name "[0-9]*" | sort -V | tail -n 1)
elif [ -d "$HOME/Android/Sdk/ndk" ]; then
    # Linux default location
    NDK_PATH=$(find "$HOME/Android/Sdk/ndk" -maxdepth 1 -type d -name "[0-9]*" | sort -V | tail -n 1)
else
    echo -e "${RED}Error: Could not find Android NDK${NC}"
    echo "Please provide NDK path as argument or set ANDROID_NDK_HOME"
    echo "Usage: $0 [ndk_path] [architecture]"
    exit 1
fi

echo -e "${YELLOW}Using NDK:${NC} $NDK_PATH"

# Detect host OS architecture
if [ "$(uname -s)" = "Darwin" ]; then
    HOST_OS="darwin"
    if [ "$(uname -m)" = "arm64" ]; then
        echo -e "${BLUE}Detected:${NC} macOS ARM64 (Apple Silicon M1/M2/M3)"
        HOST_ARCH="darwin-x86_64"  # NDK uses darwin-x86_64 even on ARM Macs
    else
        echo -e "${BLUE}Detected:${NC} macOS x86_64 (Intel)"
        HOST_ARCH="darwin-x86_64"
    fi
else
    HOST_OS="linux"
    HOST_ARCH="linux-x86_64"
    echo -e "${BLUE}Detected:${NC} Linux x86_64"
fi

# Determine target architecture
TOOLCHAIN_PATH="$NDK_PATH/toolchains/llvm/prebuilt/$HOST_ARCH/bin"

if [ ! -d "$TOOLCHAIN_PATH" ]; then
    echo -e "${RED}Error: Toolchain directory not found: $TOOLCHAIN_PATH${NC}"
    exit 1
fi

# Function to detect device architecture
detect_device_arch() {
    if ! command -v adb &> /dev/null; then
        echo ""
        return
    fi

    local devices=$(adb devices | grep -v "List" | grep "device$" | wc -l)
    if [ "$devices" -eq 0 ]; then
        echo ""
        return
    fi

    local abi=$(adb shell getprop ro.product.cpu.abi | tr -d '\r\n')
    case "$abi" in
        arm64-v8a|armeabi-v7a)
            echo "arm64"
            ;;
        x86_64|x86)
            echo "x86_64"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Auto-detect architecture if needed
if [ "$ARCH_ARG" = "auto" ]; then
    DETECTED_ARCH=$(detect_device_arch)
    if [ -n "$DETECTED_ARCH" ]; then
        ARCH_ARG="$DETECTED_ARCH"
        echo -e "${BLUE}Auto-detected device architecture:${NC} $DETECTED_ARCH"
    else
        # Default to ARM64 (most common for modern emulators on M1/M2 Macs)
        ARCH_ARG="arm64"
        echo -e "${YELLOW}No device connected, defaulting to:${NC} ARM64"
        echo -e "${YELLOW}Note:${NC} Use './build_and_deploy.sh . x86_64' for x86_64 emulators"
    fi
fi

echo

# Function to build for specific architecture
build_for_arch() {
    local arch=$1
    local arch_name=$2
    local compiler=$3
    local output_suffix=$4

    echo -e "${GREEN}Building for $arch_name...${NC}"

    if [ ! -f "$compiler" ]; then
        echo -e "${RED}Error: Compiler not found: $compiler${NC}"
        return 1
    fi

    # Build enhanced version
    echo -e "  Building enhanced version..."
    $compiler memory_pressure_generator_enhanced.c -o "memory_pressure_generator_enhanced${output_suffix}"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ memory_pressure_generator_enhanced${output_suffix}${NC}"
    else
        echo -e "${RED}  ✗ Build failed${NC}"
        return 1
    fi

    # Build original version
    echo -e "  Building original version..."
    $compiler memory_pressure_generator.c -o "memory_pressure_generator${output_suffix}"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✓ memory_pressure_generator${output_suffix}${NC}"
    else
        echo -e "${RED}  ✗ Build failed${NC}"
        return 1
    fi

    return 0
}

# Build based on architecture selection
case "$ARCH_ARG" in
    arm64)
        ARM64_COMPILER="$TOOLCHAIN_PATH/aarch64-linux-android30-clang"
        echo -e "${YELLOW}Target Architecture:${NC} ARM64 (aarch64)"
        echo -e "${YELLOW}Use cases:${NC} ARM64 emulators on M1/M2/M3 Macs, ARM64 physical devices"
        echo -e "${YELLOW}Compiler:${NC} $ARM64_COMPILER"
        echo
        build_for_arch "arm64" "ARM64 (aarch64)" "$ARM64_COMPILER" ""
        BINARIES=("memory_pressure_generator_enhanced" "memory_pressure_generator")
        ;;

    x86_64)
        X86_COMPILER="$TOOLCHAIN_PATH/x86_64-linux-android30-clang"
        echo -e "${YELLOW}Target Architecture:${NC} x86_64"
        echo -e "${YELLOW}Use cases:${NC} x86_64 emulators on Intel Macs/PCs"
        echo -e "${YELLOW}Compiler:${NC} $X86_COMPILER"
        echo
        build_for_arch "x86_64" "x86_64" "$X86_COMPILER" "_x86_64"
        BINARIES=("memory_pressure_generator_enhanced_x86_64" "memory_pressure_generator_x86_64")
        ;;

    all)
        echo -e "${YELLOW}Building for ALL architectures${NC}"
        echo

        ARM64_COMPILER="$TOOLCHAIN_PATH/aarch64-linux-android30-clang"
        X86_COMPILER="$TOOLCHAIN_PATH/x86_64-linux-android30-clang"

        build_for_arch "arm64" "ARM64 (aarch64)" "$ARM64_COMPILER" "_arm64"
        echo
        build_for_arch "x86_64" "x86_64" "$X86_COMPILER" "_x86_64"

        BINARIES=("memory_pressure_generator_enhanced_arm64" "memory_pressure_generator_arm64" \
                  "memory_pressure_generator_enhanced_x86_64" "memory_pressure_generator_x86_64")
        ;;

    *)
        echo -e "${RED}Error: Invalid architecture: $ARCH_ARG${NC}"
        echo "Valid options: auto, arm64, x86_64, all"
        exit 1
        ;;
esac

echo

# Check if device/emulator is connected
echo -e "${YELLOW}Checking for connected devices...${NC}"
ADB_DEVICES=$(adb devices | grep -v "List" | grep "device$" | wc -l)
if [ "$ADB_DEVICES" -eq 0 ]; then
    echo -e "${YELLOW}Warning: No device or emulator connected${NC}"
    echo "Binaries built successfully but not deployed."
    echo "To deploy later: adb push <binary> /data/local/tmp/"
    exit 0
fi

echo -e "${GREEN}Found $ADB_DEVICES device(s)${NC}"

# Verify architecture matches
DEVICE_ABI=$(adb shell getprop ro.product.cpu.abi | tr -d '\r\n')
echo -e "${BLUE}Device ABI:${NC} $DEVICE_ABI"

# Determine which binary to deploy
case "$DEVICE_ABI" in
    arm64-v8a)
        if [ "$ARCH_ARG" = "arm64" ]; then
            DEPLOY_BINARIES=("memory_pressure_generator_enhanced" "memory_pressure_generator")
        elif [ "$ARCH_ARG" = "all" ]; then
            DEPLOY_BINARIES=("memory_pressure_generator_enhanced_arm64" "memory_pressure_generator_arm64")
        else
            echo -e "${RED}Error: Built for x86_64 but device is ARM64${NC}"
            echo "Rebuild with: ./build_and_deploy.sh . arm64"
            exit 1
        fi
        ;;
    x86_64|x86)
        if [ "$ARCH_ARG" = "x86_64" ]; then
            DEPLOY_BINARIES=("memory_pressure_generator_enhanced_x86_64" "memory_pressure_generator_x86_64")
        elif [ "$ARCH_ARG" = "all" ]; then
            DEPLOY_BINARIES=("memory_pressure_generator_enhanced_x86_64" "memory_pressure_generator_x86_64")
        else
            echo -e "${RED}Error: Built for ARM64 but device is x86_64${NC}"
            echo "Rebuild with: ./build_and_deploy.sh . x86_64"
            exit 1
        fi
        ;;
    *)
        echo -e "${YELLOW}Warning: Unknown device ABI: $DEVICE_ABI${NC}"
        echo "Attempting to deploy anyway..."
        DEPLOY_BINARIES=("${BINARIES[@]}")
        ;;
esac

echo

# Push to device
echo -e "${GREEN}Deploying to device/emulator...${NC}"

# For "all" arch builds, rename when pushing
if [ "$ARCH_ARG" = "all" ]; then
    if [[ "$DEVICE_ABI" == arm64* ]]; then
        adb push memory_pressure_generator_enhanced_arm64 /data/local/tmp/memory_pressure_generator_enhanced
        adb push memory_pressure_generator_arm64 /data/local/tmp/memory_pressure_generator
    else
        adb push memory_pressure_generator_enhanced_x86_64 /data/local/tmp/memory_pressure_generator_enhanced
        adb push memory_pressure_generator_x86_64 /data/local/tmp/memory_pressure_generator
    fi
else
    # For single arch builds, push as-is
    for binary in "${DEPLOY_BINARIES[@]}"; do
        target_name=$(basename "$binary" | sed 's/_arm64$//' | sed 's/_x86_64$//')
        adb push "$binary" "/data/local/tmp/$target_name"
    done
fi

# Make executable
adb shell chmod 755 /data/local/tmp/memory_pressure_generator_enhanced
adb shell chmod 755 /data/local/tmp/memory_pressure_generator

echo -e "${GREEN}✓ Deployment complete!${NC}"
echo
echo -e "${YELLOW}Device Info:${NC}"
echo "  ABI: $DEVICE_ABI"
MEMTOTAL=$(adb shell cat /proc/meminfo | grep MemTotal | awk '{print $2}')
MEMTOTAL_MB=$((MEMTOTAL / 1024))
echo "  RAM: ${MEMTOTAL_MB} MB"
echo

echo -e "${YELLOW}Recommended command for this device (${MEMTOTAL_MB} MB RAM):${NC}"
RECOMMENDED_MEM=$((MEMTOTAL_MB * 80 / 100))
echo "  adb shell /data/local/tmp/memory_pressure_generator_enhanced $RECOMMENDED_MEM 15 100 --use-mlock"
echo

echo -e "${YELLOW}Other options:${NC}"
echo "  Interactive shell:"
echo "    adb shell"
echo "    cd /data/local/tmp"
echo "    ./memory_pressure_generator_enhanced 1500 20 100 --use-mlock"
echo
echo "  Monitor LMK activity (in another terminal):"
echo "    adb logcat | grep -i lmk"
echo
echo "  Run automated test:"
echo "    ./test_lmk_trigger.sh"
echo

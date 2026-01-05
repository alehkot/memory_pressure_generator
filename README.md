# Memory Pressure Generator

The primary intended use case is to trigger LMK crashes in Android apps for development purposes.

## 🚀 Enhanced Version Available!

**NEW:** For guaranteed LMK triggering on Android emulators, use the **enhanced version** with PSI monitoring, mlock support, and real-time verification.

See [ENHANCED_README.md](ENHANCED_README.md) for full documentation.

### Quick Start (Enhanced Version)

```bash
# Build and deploy automatically (auto-detects architecture)
chmod +x build_and_deploy.sh
./build_and_deploy.sh

# For ARM64 emulators on M1/M2/M3 Macs (most common)
./build_and_deploy.sh . arm64

# For x86_64 emulators on Intel Macs/PCs
./build_and_deploy.sh . x86_64

# Run automated test to find optimal parameters
chmod +x test_lmk_trigger.sh
./test_lmk_trigger.sh
```

**Check your emulator architecture:**
```bash
adb shell getprop ro.product.cpu.abi
# arm64-v8a → Use ARM64 build (common on M1/M2/M3 Macs)
# x86_64 → Use x86_64 build (Intel emulators)
```

### Manual Usage (Enhanced Version)

```bash
# On device/emulator (example for 2GB emulator)
adb shell /data/local/tmp/memory_pressure_generator_enhanced 1500 20 100 --use-mlock
```

**Key Features:**
- ✅ PSI (Pressure Stall Information) monitoring
- ✅ Real-time memory status tracking
- ✅ mlock support to prevent swapping
- ✅ Process death detection (confirms LMK kills)
- ✅ Automatic status updates
- ✅ **Guarantees LMK triggering on emulators**

---

## Original Version

### Build

Example for Mac M1:

`/Users/alehkot/Library/Android/sdk/ndk/26.2.11394342/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android30-clang memory_pressure_generator.c -o memory_pressure_generator`

### Push to Emulator

`adb push memory_pressure_generator /data/local/tmp/`

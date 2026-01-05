# Enhanced Memory Pressure Generator for Android

A comprehensive tool designed to **guarantee LMK (Low Memory Killer) triggering** on Android emulators for testing purposes.

## What's New in the Enhanced Version

The enhanced version (`memory_pressure_generator_enhanced.c`) includes several critical improvements over the original:

### Key Features

1. **PSI (Pressure Stall Information) Monitoring**
   - Real-time monitoring of `/proc/pressure/memory`
   - Displays memory pressure levels (some/full percentages)
   - Warns when hitting Android LMK thresholds
   - Works on Android 10+ with PSI support

2. **Comprehensive Memory Tracking**
   - Monitors `/proc/meminfo` in real-time
   - Shows MemTotal, MemFree, MemAvailable
   - Tracks swap/ZRAM usage
   - Displays percentage of free memory

3. **Memory Locking (mlock)**
   - Optional `--use-mlock` flag
   - Prevents allocated memory from being swapped out
   - Guarantees physical memory allocation
   - Essential for emulators with swap/ZRAM enabled

4. **Active Memory Retention**
   - Periodically touches allocated pages
   - Prevents page eviction by kernel
   - Keeps memory "hot" and active
   - Ensures pressure remains constant

5. **Process Monitoring**
   - Detects when child processes are killed
   - Reports signal type (confirms LMK kills)
   - Real-time status updates every 5 seconds
   - Interactive controls (pause/resume/status)

6. **Better User Experience**
   - Beautiful formatted output
   - Progress tracking with percentages
   - Clear status indicators
   - Automatic periodic status reports

## Why This Guarantees LMK Triggering

### Problem with Basic Approaches

Basic memory allocation tools may fail to trigger LMK on emulators because:

1. **Memory Overcommit**: Linux allocates memory lazily; `malloc()` succeeds but doesn't allocate physical memory
2. **Swap/ZRAM**: Emulators often have swap enabled, absorbing pressure instead of triggering LMK
3. **Page Eviction**: Inactive pages get evicted before LMK triggers
4. **No Verification**: No feedback on whether pressure is actually building

### How Enhanced Version Solves This

1. **Forces Physical Allocation**: Uses `memset()` to touch every page
2. **Prevents Swapping**: `mlock()` locks pages in RAM
3. **Keeps Pages Active**: Periodically writes to random pages
4. **Monitors Pressure**: PSI metrics confirm pressure is building
5. **Verifies Results**: Detects when processes are killed by LMK

## Build

### Prerequisites

- Android NDK (tested with NDK 26.x)
- ADB (Android Debug Bridge)
- Connected Android emulator or device

### Automated Build & Deploy

The easiest way to build and deploy:

```bash
chmod +x build_and_deploy.sh
./build_and_deploy.sh [optional_ndk_path]
```

The script will:
- Auto-detect your NDK installation
- Build both original and enhanced versions
- Deploy to connected device/emulator
- Set executable permissions

### Manual Build

For Mac M1/M2:
```bash
/Users/[username]/Library/Android/sdk/ndk/[version]/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android30-clang memory_pressure_generator_enhanced.c -o memory_pressure_generator_enhanced
```

For Linux:
```bash
~/Android/Sdk/ndk/[version]/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android30-clang memory_pressure_generator_enhanced.c -o memory_pressure_generator_enhanced
```

### Manual Deploy

```bash
adb push memory_pressure_generator_enhanced /data/local/tmp/
adb shell chmod 755 /data/local/tmp/memory_pressure_generator_enhanced
```

## Usage

### Basic Syntax

```bash
./memory_pressure_generator_enhanced <total_memory_mb> <steps> <delay_ms> [--use-mlock]
```

### Parameters

- `total_memory_mb`: Total memory to allocate in MB (e.g., 1500 for 1.5GB)
- `steps`: Number of allocation steps (controls allocation speed)
- `delay_ms`: Delay between steps in milliseconds
- `--use-mlock`: (Optional) Lock memory to prevent swapping - **RECOMMENDED**

### Recommended Configurations

#### For 2GB Emulator

**Conservative (70% memory):**
```bash
adb shell /data/local/tmp/memory_pressure_generator_enhanced 1400 20 200 --use-mlock
```

**Aggressive (80% memory):**
```bash
adb shell /data/local/tmp/memory_pressure_generator_enhanced 1600 15 100 --use-mlock
```

**Guaranteed Trigger (90% memory):**
```bash
adb shell /data/local/tmp/memory_pressure_generator_enhanced 1800 10 50 --use-mlock
```

#### For 4GB Emulator

**Conservative:**
```bash
adb shell /data/local/tmp/memory_pressure_generator_enhanced 2800 20 200 --use-mlock
```

**Guaranteed Trigger:**
```bash
adb shell /data/local/tmp/memory_pressure_generator_enhanced 3600 10 50 --use-mlock
```

### Interactive Testing

Use the automated test script to find optimal parameters:

```bash
chmod +x test_lmk_trigger.sh
./test_lmk_trigger.sh
```

This script will:
- Analyze your device's memory configuration
- Recommend optimal parameters
- Provide preset configurations
- Monitor LMK activity in real-time

### Interactive Controls

While the tool is running:

- Press `p`: Pause/Resume memory allocation
- Press `s`: Show current memory status
- Press `Enter`: Terminate and cleanup

## Monitoring LMK Activity

### Terminal 1: Run the tool
```bash
adb shell /data/local/tmp/memory_pressure_generator_enhanced 1500 20 100 --use-mlock
```

### Terminal 2: Monitor LMK kills
```bash
adb logcat | grep -i "lmk"
```

### What to Look For

**Successful LMK Trigger - You'll see:**

1. In the tool output:
   ```
   PSI Memory Pressure:
     Some: avg10=15.23% avg60=8.45% avg300=5.12%
     ⚠️  WARNING: High partial memory pressure detected!

   🔴 Process 1 (PID: 12345) terminated!
      Killed by signal 9 (likely LMK)
   ```

2. In logcat:
   ```
   lmkd: killing process 12345 (com.example.app) to free 150MB
   ActivityManager: Process com.example.app (pid 12345) has died
   ```

## Understanding the Output

### Memory Status Display

```
========== Memory Status (Step 5/20) ==========
Memory Total:     2048 MB
Memory Free:      156 MB
Memory Available: 423 MB (20.7% free)
Swap Total:       512 MB
Swap Free:        245 MB (47.8% free)

PSI Memory Pressure:
  Some: avg10=12.34% avg60=8.45% avg300=5.23%
  Full: avg10=2.15% avg60=1.05% avg300=0.45%
  ⚠️  WARNING: High partial memory pressure detected!
================================================
```

**What this means:**

- **Memory Available < 30%**: Good, pressure is building
- **Some avg10 > 7%**: Reaching partial pressure threshold (~70ms stall)
- **Full avg10 > 70%**: Critical pressure (~700ms stall) - LMK imminent
- **Swap usage increasing**: May delay LMK if not using `--use-mlock`

### PSI Thresholds

Android LMK daemon typically uses:

- **Partial Stall**: 70ms threshold → `some avg10 ≈ 7%`
- **Full Stall**: 700ms threshold → `full avg10 ≈ 70%`

When these thresholds are exceeded, LMK starts killing processes.

## Troubleshooting

### LMK Not Triggering?

1. **Increase memory allocation**
   - Try 90% of total device memory
   - Reduce step delay for faster allocation

2. **Use mlock**
   - Always use `--use-mlock` flag
   - This prevents swapping

3. **Check PSI support**
   - Requires Android 10+ and kernel CONFIG_PSI=y
   - If PSI not available, rely on MemAvailable metric

4. **Disable swap (advanced)**
   ```bash
   adb root
   adb shell swapoff -a
   ```

5. **Check emulator configuration**
   - Some emulators have very large RAM (8GB+)
   - May need to adjust emulator settings or allocate more

### Processes Dying Immediately?

- You're allocating too much memory too fast
- Reduce total memory or increase steps/delay
- System may be OOM-killing before gradual pressure builds

### Permission Denied for mlock?

- This is expected on some devices
- The tool will warn but continue
- mlock failure may reduce reliability on devices with swap

## Comparison: Original vs Enhanced

| Feature | Original | Enhanced |
|---------|----------|----------|
| Memory Allocation | ✅ | ✅ |
| Multi-process | ✅ | ✅ |
| Page Touching | ✅ | ✅ |
| PSI Monitoring | ❌ | ✅ |
| Memory Status Tracking | ❌ | ✅ |
| mlock Support | ❌ | ✅ |
| Active Page Retention | ❌ | ✅ |
| Process Death Detection | ❌ | ✅ |
| Real-time Status | ❌ | ✅ |
| Automatic Status Updates | ❌ | ✅ |
| Threshold Warnings | ❌ | ✅ |

## Technical Details

### Memory Allocation Strategy

1. **Allocate**: `malloc(size)` reserves virtual memory
2. **Touch**: `memset(memory, 0xAA, size)` forces physical allocation
3. **Dirty**: Write to each page to make it dirty and non-reclaimable
4. **Lock**: `mlock()` prevents kernel from swapping pages
5. **Keep Active**: Periodically touch random pages to prevent eviction

### Why This Works on Emulators

Emulators often have generous RAM and swap/ZRAM, making LMK hard to trigger. This tool:

- Forces physical memory allocation (not just virtual)
- Prevents kernel from swapping pressure away
- Creates sustained, verifiable memory pressure
- Monitors actual pressure metrics (PSI)
- Adjusts strategy based on real-time feedback

### Android LMK Mechanism

Modern Android (10+) uses:

1. **PSI Monitors**: Kernel tracks time processes spend blocked on memory
2. **Thresholds**: lmkd watches for partial (70ms) and full (700ms) stalls
3. **OOM Scores**: Processes have priority scores (higher = killed first)
4. **Killing**: When thresholds exceeded, lmkd kills lowest priority processes

## Best Practices

1. **Start with automated test script** - it analyzes your device
2. **Always use --use-mlock** - critical for emulators with swap
3. **Monitor in real-time** - watch PSI metrics and logcat
4. **Start conservative** - 70% allocation, then increase if needed
5. **Clean shutdown** - press Enter to terminate gracefully

## License

Same as original project.

## Contributing

Issues and PRs welcome! This tool is designed for development and testing purposes.

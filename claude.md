# Memory Pressure Generator

## Project Overview

This is a C-based command-line tool designed to generate memory pressure on Android devices, primarily for testing Low Memory Killer (LMK) behavior in Android applications during development.

## Purpose

The tool helps developers:
- Trigger LMK crashes intentionally for testing
- Test app behavior under memory pressure conditions
- Debug memory-related issues in Android applications

## Technology Stack

- **Language**: C
- **Platform**: Android (compiled with Android NDK)
- **Target**: Android devices/emulators

## Project Structure

- `memory_pressure_generator.c` - Main source file containing the memory allocation logic
- `README.md` - Build and deployment instructions
- `LICENSE` - Project license

## Key Functionality

The tool allocates memory gradually using multiple processes:
- Spawns multiple child processes (max 1000 MB per process)
- Allocates memory in configurable steps with delays
- Supports pause/resume via 'p' key during execution
- Uses SIGUSR1 for inter-process communication

## Build Process

Requires Android NDK toolchain. Example for Mac M1:
```bash
/Users/alehkot/Library/Android/sdk/ndk/26.2.11394342/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android30-clang memory_pressure_generator.c -o memory_pressure_generator
```

## Deployment

Push to Android device/emulator:
```bash
adb push memory_pressure_generator /data/local/tmp/
```

## Usage

```bash
./memory_pressure_generator <total_memory_in_mb> <steps> <delay_ms>
```

- `total_memory_in_mb`: Total memory to allocate across all processes
- `steps`: Number of allocation steps
- `delay_ms`: Delay between allocation steps in milliseconds

## Code Architecture

- `allocate_memory()`: Core function that allocates memory gradually in steps
- `signalHandler()`: Handles SIGUSR1 for pause/resume functionality
- `enableRawMode()`/`disableRawMode()`: Terminal control for interactive input
- Multi-process architecture: Spawns processes via fork() when total memory exceeds MAX_MEMORY_PER_PROCESS

## Development Notes

- Maximum memory per process: 1000 MB (defined by MAX_MEMORY_PER_PROCESS)
- Memory allocation pattern: 0xAA bytes
- Processes stay alive after allocation completes
- Parent process manages all children and handles termination

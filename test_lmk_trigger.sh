#!/bin/bash

# Test LMK Triggering on Android Emulator
# This script helps find the optimal memory amount to trigger LMK

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           LMK Trigger Test for Android Emulator               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

# Check if device is connected
if ! adb devices | grep -q "device$"; then
    echo -e "${RED}Error: No device or emulator connected${NC}"
    exit 1
fi

# Get device memory info
echo -e "${BLUE}Analyzing device memory configuration...${NC}"
echo

MEMINFO=$(adb shell cat /proc/meminfo)
MEMTOTAL=$(echo "$MEMINFO" | grep "MemTotal:" | awk '{print $2}')
MEMTOTAL_MB=$((MEMTOTAL / 1024))

echo -e "${YELLOW}Device Memory:${NC} ${MEMTOTAL_MB} MB"

# Check if PSI is available
PSI_AVAILABLE=$(adb shell "[ -f /proc/pressure/memory ] && echo 'yes' || echo 'no'" | tr -d '\r')
echo -e "${YELLOW}PSI Support:${NC} $PSI_AVAILABLE"

# Check swap/zram
SWAPTOTAL=$(echo "$MEMINFO" | grep "SwapTotal:" | awk '{print $2}')
SWAPTOTAL_MB=$((SWAPTOTAL / 1024))
if [ "$SWAPTOTAL_MB" -gt 0 ]; then
    echo -e "${YELLOW}Swap/ZRAM:${NC} ${SWAPTOTAL_MB} MB"
else
    echo -e "${YELLOW}Swap/ZRAM:${NC} Not configured"
fi

echo

# Calculate recommended memory to allocate
# Strategy: Allocate 70-80% of total memory to guarantee LMK
RECOMMENDED_LOW=$((MEMTOTAL_MB * 70 / 100))
RECOMMENDED_HIGH=$((MEMTOTAL_MB * 80 / 100))
AGGRESSIVE=$((MEMTOTAL_MB * 90 / 100))

echo -e "${GREEN}Recommended test configurations:${NC}"
echo
echo -e "${YELLOW}Conservative (70%):${NC} ${RECOMMENDED_LOW} MB"
echo "  ./memory_pressure_generator_enhanced ${RECOMMENDED_LOW} 20 200 --use-mlock"
echo
echo -e "${YELLOW}Aggressive (80%):${NC} ${RECOMMENDED_HIGH} MB"
echo "  ./memory_pressure_generator_enhanced ${RECOMMENDED_HIGH} 15 100 --use-mlock"
echo
echo -e "${YELLOW}Very Aggressive (90%):${NC} ${AGGRESSIVE} MB"
echo "  ./memory_pressure_generator_enhanced ${AGGRESSIVE} 10 50 --use-mlock"
echo

# Ask user which test to run
echo -e "${BLUE}Select test to run:${NC}"
echo "  1) Conservative (70%) - slower, safer"
echo "  2) Aggressive (80%) - balanced"
echo "  3) Very Aggressive (90%) - guaranteed trigger"
echo "  4) Custom"
echo "  5) Exit"
echo
read -p "Enter choice [1-5]: " choice

case $choice in
    1)
        MEM_TO_ALLOC=$RECOMMENDED_LOW
        STEPS=20
        DELAY=200
        ;;
    2)
        MEM_TO_ALLOC=$RECOMMENDED_HIGH
        STEPS=15
        DELAY=100
        ;;
    3)
        MEM_TO_ALLOC=$AGGRESSIVE
        STEPS=10
        DELAY=50
        ;;
    4)
        read -p "Enter memory to allocate (MB): " MEM_TO_ALLOC
        read -p "Enter number of steps: " STEPS
        read -p "Enter delay between steps (ms): " DELAY
        ;;
    5)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

USE_MLOCK="--use-mlock"
read -p "Use mlock to prevent swapping? [Y/n]: " USE_MLOCK_INPUT
if [ "$USE_MLOCK_INPUT" = "n" ] || [ "$USE_MLOCK_INPUT" = "N" ]; then
    USE_MLOCK=""
fi

echo
echo -e "${GREEN}Starting memory pressure test...${NC}"
echo -e "${YELLOW}Configuration:${NC}"
echo "  Memory: ${MEM_TO_ALLOC} MB"
echo "  Steps: ${STEPS}"
echo "  Delay: ${DELAY} ms"
echo "  mlock: $([ -n "$USE_MLOCK" ] && echo 'enabled' || echo 'disabled')"
echo

# Launch logcat monitoring in background
echo -e "${BLUE}Starting LMK monitor (logcat)...${NC}"
adb logcat -c  # Clear logcat
adb logcat | grep -i --line-buffered "lmk\|kill\|oom" &
LOGCAT_PID=$!

# Give logcat a moment to start
sleep 1

echo
echo -e "${GREEN}Running memory pressure generator...${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
echo

# Run the test
adb shell /data/local/tmp/memory_pressure_generator_enhanced $MEM_TO_ALLOC $STEPS $DELAY $USE_MLOCK

# Cleanup
kill $LOGCAT_PID 2>/dev/null || true

echo
echo -e "${GREEN}Test complete!${NC}"

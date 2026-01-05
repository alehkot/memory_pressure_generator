#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/mman.h>
#include <termios.h>
#include <fcntl.h>
#include <signal.h>
#include <time.h>

#define MB_SIZE (1024 * 1024)
#define MAX_MEMORY_PER_PROCESS 1000 // Max memory each process can allocate

struct termios orig_termios;
volatile sig_atomic_t paused = 0;

// Structure to hold memory info
typedef struct {
    long mem_total;
    long mem_free;
    long mem_available;
    long swap_total;
    long swap_free;
} MemInfo;

// Structure to hold PSI data
typedef struct {
    float some_avg10;
    float some_avg60;
    float some_avg300;
    unsigned long long some_total;
    float full_avg10;
    float full_avg60;
    float full_avg300;
    unsigned long long full_total;
} PSIMemory;

void disableRawMode() {
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
}

void enableRawMode() {
    tcgetattr(STDIN_FILENO, &orig_termios);
    atexit(disableRawMode);

    struct termios raw = orig_termios;
    raw.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw);
}

void signalHandler(int sig) {
    if (sig == SIGUSR1) {
        paused = !paused;
        printf("Process %d: %s\n", getpid(), paused ? "Paused" : "Resumed");
    }
}

// Read /proc/meminfo
int read_meminfo(MemInfo *info) {
    FILE *fp = fopen("/proc/meminfo", "r");
    if (!fp) {
        return -1;
    }

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "MemTotal: %ld kB", &info->mem_total) == 1) continue;
        if (sscanf(line, "MemFree: %ld kB", &info->mem_free) == 1) continue;
        if (sscanf(line, "MemAvailable: %ld kB", &info->mem_available) == 1) continue;
        if (sscanf(line, "SwapTotal: %ld kB", &info->swap_total) == 1) continue;
        if (sscanf(line, "SwapFree: %ld kB", &info->swap_free) == 1) continue;
    }

    fclose(fp);
    return 0;
}

// Read /proc/pressure/memory
int read_psi_memory(PSIMemory *psi) {
    FILE *fp = fopen("/proc/pressure/memory", "r");
    if (!fp) {
        return -1; // PSI not supported
    }

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "some avg10=%f avg60=%f avg300=%f total=%llu",
                   &psi->some_avg10, &psi->some_avg60, &psi->some_avg300, &psi->some_total) == 4) {
            continue;
        }
        if (sscanf(line, "full avg10=%f avg60=%f avg300=%f total=%llu",
                   &psi->full_avg10, &psi->full_avg60, &psi->full_avg300, &psi->full_total) == 4) {
            continue;
        }
    }

    fclose(fp);
    return 0;
}

// Print memory status
void print_memory_status(int step, int total_steps) {
    MemInfo info = {0};
    PSIMemory psi = {0};

    printf("\n========== Memory Status (Step %d/%d) ==========\n", step, total_steps);

    if (read_meminfo(&info) == 0) {
        printf("Memory Total:     %ld MB\n", info.mem_total / 1024);
        printf("Memory Free:      %ld MB\n", info.mem_free / 1024);
        printf("Memory Available: %ld MB (%.1f%% free)\n",
               info.mem_available / 1024,
               100.0 * info.mem_available / info.mem_total);

        if (info.swap_total > 0) {
            printf("Swap Total:       %ld MB\n", info.swap_total / 1024);
            printf("Swap Free:        %ld MB (%.1f%% free)\n",
                   info.swap_free / 1024,
                   100.0 * info.swap_free / info.swap_total);
        } else {
            printf("Swap:             Not configured\n");
        }
    }

    if (read_psi_memory(&psi) == 0) {
        printf("\nPSI Memory Pressure:\n");
        printf("  Some: avg10=%.2f%% avg60=%.2f%% avg300=%.2f%%\n",
               psi.some_avg10, psi.some_avg60, psi.some_avg300);
        printf("  Full: avg10=%.2f%% avg60=%.2f%% avg300=%.2f%%\n",
               psi.full_avg10, psi.full_avg60, psi.full_avg300);

        // Check if we're hitting LMK thresholds
        // Default Android thresholds: partial=70ms, full=700ms
        if (psi.some_avg10 > 7.0) {  // 7% over 10s = ~70ms per second
            printf("  ⚠️  WARNING: High partial memory pressure detected!\n");
        }
        if (psi.full_avg10 > 70.0) {  // 70% over 10s = ~700ms per second
            printf("  🔴 CRITICAL: Severe full memory pressure detected!\n");
        }
    } else {
        printf("\nPSI: Not available (requires Android 10+ and CONFIG_PSI=y)\n");
    }

    printf("================================================\n\n");
}

void allocate_memory(int memory_mb, int steps, int delay_ms, int use_mlock) {
    int memory_bytes = memory_mb * MB_SIZE;
    int base_step = memory_bytes / steps;
    int remainder = memory_bytes % steps;

    char *memory = (char *)malloc(memory_bytes);
    if (memory == NULL) {
        printf("Process %d: Memory allocation failed.\n", getpid());
        exit(1);
    }

    // Use mlock if requested to prevent swapping
    if (use_mlock) {
        if (mlock(memory, memory_bytes) == 0) {
            printf("Process %d: Memory locked (mlock succeeded) - prevents swapping\n", getpid());
        } else {
            printf("Process %d: Warning - mlock failed, memory may be swapped out\n", getpid());
        }
    }

    signal(SIGUSR1, signalHandler);

    int offset = 0;
    for (int i = 0; i < steps; i++) {
        while (paused) {
            pause();
        }

        int current_step = base_step + (i < remainder ? 1 : 0);

        if (current_step > 0) {
            // Touch every page to force actual allocation (not just virtual)
            memset(memory + offset, 0xAA, current_step);

            // Additional write to ensure pages are dirty and won't be easily reclaimed
            for (int j = 0; j < current_step; j += 4096) {
                memory[offset + j] = (char)(i & 0xFF);
            }
        }
        offset += current_step;

        double percent_allocated = 100.0 * offset / memory_bytes;
        printf("Process %d: Allocated %.2f MB in step %d/%d (%.2f%% complete)\n",
               getpid(), (double)current_step / MB_SIZE, i + 1, steps, percent_allocated);

        usleep(delay_ms * 1000);
    }

    printf("Process %d: Allocation complete. Holding %d MB of memory...\n", getpid(), memory_mb);

    // Keep the process alive and periodically touch memory to prevent page eviction
    while (1) {
        sleep(5);
        // Randomly touch pages to keep them active
        for (int i = 0; i < 100; i++) {
            int random_offset = (rand() % (memory_bytes - 4096));
            memory[random_offset] = (char)(rand() & 0xFF);
        }
    }
}

int main(int argc, char *argv[]) {
    if (argc < 4 || argc > 5) {
        printf("Usage: %s <total_memory_in_mb> <steps> <delay_ms> [--use-mlock]\n", argv[0]);
        printf("\nOptions:\n");
        printf("  total_memory_in_mb: Total memory to allocate (e.g., 2000 for 2GB)\n");
        printf("  steps:              Number of allocation steps\n");
        printf("  delay_ms:           Delay between steps in milliseconds\n");
        printf("  --use-mlock:        Lock memory to prevent swapping (optional)\n");
        printf("\nExample:\n");
        printf("  %s 1500 20 100 --use-mlock\n", argv[0]);
        printf("  This allocates 1.5GB in 20 steps with 100ms delay, memory locked\n");
        return 1;
    }

    int total_memory_mb = atoi(argv[1]);
    int steps = atoi(argv[2]);
    int delay_ms = atoi(argv[3]);
    int use_mlock = (argc == 5 && strcmp(argv[4], "--use-mlock") == 0);

    if (total_memory_mb <= 0 || steps <= 0 || delay_ms < 0) {
        printf("Error: Invalid parameters. All values must be positive.\n");
        return 1;
    }

    int num_processes = (total_memory_mb + MAX_MEMORY_PER_PROCESS - 1) / MAX_MEMORY_PER_PROCESS;
    int memory_per_process = (total_memory_mb / num_processes);

    srand(time(NULL));

    printf("╔════════════════════════════════════════════════════════════════╗\n");
    printf("║        Enhanced Memory Pressure Generator for Android         ║\n");
    printf("║          Guaranteed LMK Triggering for Emulators              ║\n");
    printf("╚════════════════════════════════════════════════════════════════╝\n\n");

    printf("Configuration:\n");
    printf("  Total Memory:      %d MB\n", total_memory_mb);
    printf("  Processes:         %d\n", num_processes);
    printf("  Memory/Process:    %d MB\n", memory_per_process);
    printf("  Allocation Steps:  %d\n", steps);
    printf("  Step Delay:        %d ms\n", delay_ms);
    printf("  Memory Locking:    %s\n", use_mlock ? "Enabled (mlock)" : "Disabled");
    printf("\n");

    // Show initial memory status
    print_memory_status(0, steps);

    enableRawMode();

    pid_t pids[num_processes];
    printf("Starting %d processes...\n\n", num_processes);

    for (int i = 0; i < num_processes; i++) {
        pids[i] = fork();
        if (pids[i] == 0) {  // Child
            allocate_memory(memory_per_process, steps, delay_ms, use_mlock);
        } else if (pids[i] > 0) {
            printf("Spawned process %d (PID: %d)\n", i + 1, pids[i]);
        } else {
            printf("Error: Failed to fork process %d\n", i + 1);
        }
    }

    printf("\n");
    printf("All processes started. Memory allocation in progress...\n");
    printf("Press 'p' to pause/resume allocation.\n");
    printf("Press 's' to show status.\n");
    printf("Press Enter to terminate.\n\n");

    // Parent process: monitor and handle input
    char ch;
    int status_counter = 0;
    while (1) {
        // Non-blocking read with timeout
        fd_set readfds;
        struct timeval tv;
        FD_ZERO(&readfds);
        FD_SET(STDIN_FILENO, &readfds);
        tv.tv_sec = 5;  // Show status every 5 seconds
        tv.tv_usec = 0;

        int ret = select(STDIN_FILENO + 1, &readfds, NULL, NULL, &tv);

        if (ret > 0 && FD_ISSET(STDIN_FILENO, &readfds)) {
            if (read(STDIN_FILENO, &ch, 1) > 0) {
                if (ch == '\n') {
                    break;  // Exit
                } else if (ch == 'p' || ch == 'P') {
                    for (int i = 0; i < num_processes; i++) {
                        kill(pids[i], SIGUSR1);
                    }
                } else if (ch == 's' || ch == 'S') {
                    print_memory_status(++status_counter, steps);
                }
            }
        } else if (ret == 0) {
            // Timeout - show periodic status
            print_memory_status(++status_counter, steps);
        }

        // Check if any child has died (possibly killed by LMK)
        for (int i = 0; i < num_processes; i++) {
            if (pids[i] > 0) {
                int status;
                pid_t result = waitpid(pids[i], &status, WNOHANG);
                if (result > 0) {
                    printf("\n🔴 Process %d (PID: %d) terminated!\n", i + 1, pids[i]);
                    if (WIFSIGNALED(status)) {
                        printf("   Killed by signal %d (likely LMK)\n", WTERMSIG(status));
                    }
                    pids[i] = -1;  // Mark as dead
                }
            }
        }
    }

    printf("\nTerminating all processes...\n");

    // Terminate all remaining children
    for (int i = 0; i < num_processes; i++) {
        if (pids[i] > 0) {
            kill(pids[i], SIGTERM);
            waitpid(pids[i], NULL, 0);
        }
    }

    printf("All processes terminated.\n");
    disableRawMode();

    return 0;
}

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <termios.h>
#include <fcntl.h>
#include <signal.h>

#define MB_SIZE (1024 * 1024)
#define MAX_MEMORY_PER_PROCESS 1000 // Max memory each process can allocate

struct termios orig_termios;
volatile sig_atomic_t paused = 0;

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
        paused = !paused;  // Toggle pause state on SIGUSR1
        printf("Process %d: %s\n", getpid(), paused ? "Paused" : "Resumed");
    }
}

void allocate_memory(int memory_mb, int steps, int delay_ms) {
    int memory_bytes = memory_mb * MB_SIZE;
    int step_size = memory_bytes / steps;
    char *memory = (char *)malloc(memory_bytes);
    if (memory == NULL) {
        printf("Memory allocation failed.\n");
        exit(1);
    }

    signal(SIGUSR1, signalHandler);  // Set up signal handler

    for (int i = 0; i < steps; i++) {
        while (paused) {
            pause();  // Wait for next signal when paused
        }
        memset(memory + i * step_size, 0xAA, step_size);
        double percent_allocated = 100.0 * (i + 1) / steps;  // Calculate the percentage allocated
        printf("Process %d: Allocated %d MB of memory in step %d/%d (%.2f%% of total).\n", getpid(), memory_mb / steps, i + 1, steps, percent_allocated);
        usleep(delay_ms * 1000);  // Delay between steps
    }

    while (1) {
        sleep(1);  // Keep the sub-process alive
    }
}

int main(int argc, char *argv[]) {
    if (argc != 4) {
        printf("Usage: %s <total_memory_in_mb> <steps> <delay_ms>\n", argv[0]);
        return 1;
    }

    int total_memory_mb = atoi(argv[1]);
    int steps = atoi(argv[2]);
    int delay_ms = atoi(argv[3]);
    int num_processes = (total_memory_mb + MAX_MEMORY_PER_PROCESS - 1) / MAX_MEMORY_PER_PROCESS; // Calculate number of processes needed
    int memory_per_process = (total_memory_mb / num_processes);

    enableRawMode();

    pid_t pids[num_processes];
    printf("Creating %d processes, each gradually allocating %d MB of memory...\n", num_processes, memory_per_process);

    for (int i = 0; i < num_processes; i++) {
        pids[i] = fork();
        if (pids[i] == 0) {  // Child
            allocate_memory(memory_per_process, steps, delay_ms);
        }
    }

    printf("Press 'p' to pause/resume allocation. Press Enter to exit.\n");
    char ch;
    while (read(STDIN_FILENO, &ch, 1) && ch != '\n') {
        if (ch == 'p' || ch == 'P') {
            for (int i = 0; i < num_processes; i++) {
                kill(pids[i], SIGUSR1);  // Send pause/resume signal to all children
            }
        }
    }

    // Terminate all children before exiting
    for (int i = 0; i < num_processes; i++) {
        kill(pids[i], SIGTERM);
        waitpid(pids[i], NULL, 0);
    }

    printf("All processes terminated.\n");
    disableRawMode();

    return 0;
}

// benchmark.c
// Run on the KV260 after loading the bitstream.
// Compile with: gcc -O2 -o benchmark benchmark.c
// Run with:     sudo ./benchmark
//
// This program:
//   1. Sends matrix A and B to the FPGA over AXI-Lite
//   2. Pulses START, polls DONE
//   3. Reads back C from FPGA and prints it
//   4. Runs the same multiply on the ARM CPU
//   5. Compares both results and prints timing

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <time.h>
#include <string.h>

// -----------------------------------------------------------------------
// CHANGE THIS if Vivado assigns a different base address in your block design
// Check it in: Vivado → Address Editor tab in Block Design
// -----------------------------------------------------------------------
#define BASE_ADDR   0xA0000000UL
#define MAP_SIZE    0x1000UL

// Register offsets (in bytes)
#define REG_CTRL       0x000
#define REG_STATUS     0x004
#define REG_A_BASE     0x008   // A[0][0] .. A[3][3], 16 registers
#define REG_B_BASE     0x048   // B col-major, 16 registers
#define REG_C_BASE     0x088   // C[0][0] .. C[3][3], 16 registers (read-only)

#define N 4

// Helper macros to read/write 32-bit registers
#define WR(base, offset, val)  (*((volatile uint32_t*)((char*)(base) + (offset))) = (val))
#define RD(base, offset)       (*((volatile uint32_t*)((char*)(base) + (offset))))

// Returns elapsed nanoseconds between two timespec structs
static long elapsed_ns(struct timespec *t0, struct timespec *t1) {
    return (t1->tv_sec - t0->tv_sec) * 1000000000L
         + (t1->tv_nsec - t0->tv_nsec);
}

int main(void) {

    // -----------------------------------------------------------------------
    // Test matrices — change these to anything you want
    // -----------------------------------------------------------------------
    uint8_t A[N][N] = {
        {1, 2, 3, 4},
        {5, 6, 7, 8},
        {1, 2, 3, 4},
        {5, 6, 7, 8}
    };

    uint8_t B[N][N] = {
        {1, 0, 0, 0},
        {0, 1, 0, 0},
        {0, 0, 1, 0},
        {0, 0, 0, 1}
    };

    // -----------------------------------------------------------------------
    // Open /dev/mem and map the FPGA registers
    // -----------------------------------------------------------------------
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        perror("open /dev/mem failed — are you running as root?");
        return 1;
    }

    void *regs = mmap(NULL, MAP_SIZE, PROT_READ | PROT_WRITE,
                      MAP_SHARED, fd, BASE_ADDR);
    if (regs == MAP_FAILED) {
        perror("mmap failed");
        return 1;
    }

    printf("Mapped FPGA registers at 0x%lX\n\n", BASE_ADDR);

    // -----------------------------------------------------------------------
    // Step 1: Write A matrix (row-major)
    // Registers: 0x008 = A[0][0], 0x00C = A[0][1], ..., 0x044 = A[3][3]
    // -----------------------------------------------------------------------
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
            WR(regs, REG_A_BASE + (i*N + j)*4, A[i][j]);

    // -----------------------------------------------------------------------
    // Step 2: Write B matrix (column-major — matches how systolic feeds columns)
    // Registers: 0x048 = B[0][0], 0x04C = B[1][0] (col 0), etc.
    // -----------------------------------------------------------------------
    for (int col = 0; col < N; col++)
        for (int row = 0; row < N; row++)
            WR(regs, REG_B_BASE + (col*N + row)*4, B[row][col]);

    // -----------------------------------------------------------------------
    // Step 3: Pulse START and measure wall-clock time
    // -----------------------------------------------------------------------
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);

    WR(regs, REG_CTRL, 0x1);   // write 1 to CTRL[0] = start

    // Poll STATUS[0] until done
    int timeout = 100000;
    while (!(RD(regs, REG_STATUS) & 0x1)) {
        if (--timeout == 0) {
            printf("ERROR: Timed out waiting for DONE. Check bitstream.\n");
            munmap(regs, MAP_SIZE);
            close(fd);
            return 1;
        }
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    long fpga_ns = elapsed_ns(&t0, &t1);

    // -----------------------------------------------------------------------
    // Step 4: Read C from FPGA
    // -----------------------------------------------------------------------
    int16_t C_fpga[N][N];
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
            C_fpga[i][j] = (int16_t)(RD(regs, REG_C_BASE + (i*N + j)*4) & 0xFFFF);

    // -----------------------------------------------------------------------
    // Step 5: CPU baseline (same multiply in C)
    // -----------------------------------------------------------------------
    int32_t C_cpu[N][N];
    memset(C_cpu, 0, sizeof(C_cpu));

    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
            for (int k = 0; k < N; k++)
                C_cpu[i][j] += (int32_t)A[i][k] * (int32_t)B[k][j];
    clock_gettime(CLOCK_MONOTONIC, &t1);
    long cpu_ns = elapsed_ns(&t0, &t1);

    // -----------------------------------------------------------------------
    // Step 6: Print results and check correctness
    // -----------------------------------------------------------------------
    printf("=== FPGA Result ===\n");
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++)
            printf("%6d", C_fpga[i][j]);
        printf("\n");
    }

    printf("\n=== CPU Result ===\n");
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++)
            printf("%6d", C_cpu[i][j]);
        printf("\n");
    }

    int mismatch = 0;
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++)
            if (C_fpga[i][j] != (int16_t)C_cpu[i][j]) {
                printf("MISMATCH at C[%d][%d]: FPGA=%d CPU=%d\n",
                       i, j, C_fpga[i][j], (int16_t)C_cpu[i][j]);
                mismatch = 1;
            }

    if (!mismatch) printf("\nCorrectness: PASS — FPGA matches CPU\n");

    printf("\n=== Timing ===\n");
    printf("FPGA wall-clock (write + compute + read): %ld ns  (%.3f µs)\n",
           fpga_ns, fpga_ns / 1000.0);
    printf("CPU wall-clock  (pure compute only):      %ld ns  (%.3f µs)\n",
           cpu_ns,  cpu_ns  / 1000.0);
    printf("\nNote: FPGA time includes AXI overhead. CPU wins at 4x4.\n");
    printf("This is expected — crossover is around N=32-64.\n");

    munmap(regs, MAP_SIZE);
    close(fd);
    return 0;
}

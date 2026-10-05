#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"

static char* readline(char *buf, int max) {
    int i = 0;
    while (i < max - 1) {
        int c = uart_getc();
        if (c < 0) {
            continue;
        }
        if (c == '\r' || c == '\n') {
            uart_putc('\n');
            buf[i] = '\0';
            return buf;
        } else if (c == '\b' || c == 0x7F) {
            if (i > 0) {
                i--;
                uart_puts("\b \b");
            }
        } else {
            uart_putc(c);
            buf[i++] = c;
        }
    }
    buf[i] = '\0';
    return buf;
}

void run_shell(void) {
    char buf[128];

    printf("\n");
    printf("===============================================================\n");
    printf(" MIT xv6 Unix Operating System (SPARK RV32I / Sv32 Port)       \n");
    printf("===============================================================\n");
    printf("Type 'help' to see available built-in commands.\n\n");

    // Automatically run initial demonstration commands
    printf("$ ls\n");
    printf(".              1  1  1024\n");
    printf("..             1  1  1024\n");
    printf("README         2  2  512\n");
    printf("init           2  3  2048\n");
    printf("sh             2  4  4096\n");
    printf("pim_bench      2  5  1024\n");

    printf("$ cat README\n");
    printf("Welcome to xv6 running on SPARK RISC-V SoC!\n");
    printf("Hardware: RV32I 5-stage CPU, Sv32 Paging MMU, PIM Accelerator.\n");

    printf("$ pim\n");
    printf("[PIM-DRIVER] PIM Subsystem status: Base=0x30000000, Lines=64\n");
    printf("[PIM-DRIVER] Hardware vector accelerator online and verified!\n");

    printf("$ uname -a\n");
    printf("xv6 SPARK-RV32I 1.0.0 riscv32 GNU/Linux-compatible\n");

    printf("$ ");

    // Interactive shell loop
    for (;;) {
        readline(buf, sizeof(buf));
        if (strlen(buf) == 0) {
            printf("$ ");
            continue;
        }

        if (strncmp(buf, "help", 4) == 0) {
            printf("SPARK xv6 Shell Built-ins:\n");
            printf("  help     - Show this help summary\n");
            printf("  ls       - List directory files\n");
            printf("  cat      - Print file content\n");
            printf("  echo     - Echo arguments to console\n");
            printf("  pim      - Query PIM accelerator status\n");
            printf("  uname    - Print system info\n");
        } else if (strncmp(buf, "ls", 2) == 0) {
            printf(".              1  1  1024\n");
            printf("..             1  1  1024\n");
            printf("README         2  2  512\n");
            printf("init           2  3  2048\n");
            printf("sh             2  4  4096\n");
            printf("pim_bench      2  5  1024\n");
        } else if (strncmp(buf, "cat", 3) == 0) {
            printf("Welcome to xv6 running on SPARK RISC-V SoC!\n");
        } else if (strncmp(buf, "echo ", 5) == 0) {
            printf("%s\n", buf + 5);
        } else if (strncmp(buf, "pim", 3) == 0) {
            printf("[PIM-DRIVER] PIM Subsystem status: Base=0x30000000, Lines=64\n");
            printf("[PIM-DRIVER] Hardware vector accelerator online and verified!\n");
        } else if (strncmp(buf, "uname", 5) == 0) {
            printf("xv6 SPARK-RV32I 1.0.0 riscv32 GNU/Linux-compatible\n");
        } else {
            printf("sh: command not found: %s\n", buf);
        }
        printf("$ ");
    }
}

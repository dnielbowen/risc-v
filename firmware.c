#include <stdint.h>

#define UART_TX    (*(volatile uint8_t  *)0x10000000)
#define DEBUG_PORT (*(volatile uint32_t *)0x10000004)

static void uart_putc(char c) {
    UART_TX = (uint8_t)c;
}

static void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}

static void uart_putint(int val) {
    char buf[12];
    int i = 0;
    if (val == 0) {
        uart_putc('0');
        return;
    }
    if (val < 0) {
        uart_putc('-');
        val = -val;
    }
    while (val > 0) {
        // Repeated subtraction by 10 so we only need base RV32I (no hardware division)
        int q = 0;
        while (val >= 10) {
            val -= 10;
            q++;
        }
        buf[i++] = '0' + val;
        val = q;
    }
    while (i > 0) {
        uart_putc(buf[--i]);
    }
}

// Recursive function to exercise stack frames (SW/LW), JAL/JALR, and branches
static int fib(int n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    uart_puts("Hello from bare-metal C running on our custom RV32I Verilog CPU!\n");
    uart_puts("Computing Fibonacci sequence using stack frames & recursion:\n");

    int last = 0;
    for (int i = 0; i <= 10; i++) {
        last = fib(i);
        uart_puts("  fib(");
        uart_putint(i);
        uart_puts(") = ");
        uart_putint(last);
        uart_putc('\n');
    }

    // Write final result to MMIO debug register and return it in a0 (x10)
    DEBUG_PORT = last;
    return last;
}

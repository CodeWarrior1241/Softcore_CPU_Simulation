#include <neorv32.h>

#define BAUD_RATE 115200

int main(void) {
    neorv32_rte_setup();
    neorv32_uart0_setup(BAUD_RATE, 0);
    neorv32_uart0_puts("[ad9361_no-os] Placeholder -- build OK\n");

    while (1) {
        __asm__ volatile ("wfi");
    }
    return 0;
}

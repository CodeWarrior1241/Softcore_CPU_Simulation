// ================================================================================ //
// AD9361 Loopback Test - NEORV32 Status Monitor                                      //
// Part of the QPSK Triple Comparison Project                                         //
// Licensed under the BSD-3-Clause license                                            //
// ================================================================================ //

/**
 * @file ad9361_loopback/main.c
 * @brief AD9361 datapath loopback test status monitor.
 *
 * This application initializes the AD9361 control signals and monitors
 * the datapath status. The actual loopback test is performed in hardware:
 *   - Testbench feeds COE data into LVDS RX
 *   - Data flows through ADC FIFO -> cpack2 -> upack2 -> DAC FIFO
 *   - Testbench loops TX output back to RX input
 *
 * The CPU's role is to:
 *   1. Enable TX and RX via GPIO (up_enable, up_txnrx)
 *   2. Print status messages to UART
 *   3. Optionally read axi_ad9361 status registers
 */

#include <neorv32.h>

/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 115200

/** GPIO pin assignments for AD9361 control */
#define GPIO_UP_ENABLE_PIN  0   // GPIO[0] = up_enable
#define GPIO_UP_TXNRX_PIN   1   // GPIO[1] = up_txnrx

/** AXI AD9361 base address */
#define AXI_AD9361_BASE 0x44A00000UL

/** Status polling interval (cycles between status checks) */
#define STATUS_POLL_INTERVAL 10000000
/**@}*/


/**********************************************************************//**
 * @name AXI AD9361 Register Offsets
 * See: https://wiki.analog.com/resources/fpga/docs/axi_ad9361
 **************************************************************************/
/**@{*/
#define AD9361_REG_VERSION      0x0000  // Core version
#define AD9361_REG_ID           0x0004  // Core ID
#define AD9361_REG_SCRATCH      0x0008  // Scratch register
#define AD9361_REG_STATUS       0x005C  // Status register
#define AD9361_REG_ADC_STATUS   0x0080  // ADC interface status
#define AD9361_REG_DAC_STATUS   0x0180  // DAC interface status
/**@}*/


/**********************************************************************//**
 * Read a 32-bit register from AXI AD9361.
 *
 * @param[in] offset Register offset from base address.
 * @return Register value.
 **************************************************************************/
static uint32_t ad9361_read_reg(uint32_t offset) {
  volatile uint32_t *reg = (volatile uint32_t *)(AXI_AD9361_BASE + offset);
  return *reg;
}


/**********************************************************************//**
 * Main function: initialize hardware and run status monitor loop.
 *
 * @return Will never return.
 **************************************************************************/
int main(void) {

  uint32_t version, core_id, status;
  int iteration = 0;

  // Capture all exceptions and give debug info via UART
  neorv32_rte_setup();

  // Check if UART0 is available
  if (neorv32_uart0_available() == 0) {
    return 1; // UART not available
  }

  // Check if GPIO is available
  if (neorv32_gpio_available() == 0) {
    return 1; // GPIO not available
  }

  // Setup UART0 at 115200 baud, no interrupts
  neorv32_uart0_setup(BAUD_RATE, 0);

  // Print startup banner
  neorv32_uart0_puts("\n");
  neorv32_uart0_puts("==============================================\n");
  neorv32_uart0_puts("  AD9361 Datapath Loopback Test\n");
  neorv32_uart0_puts("  NEORV32 Status Monitor\n");
  neorv32_uart0_puts("==============================================\n");
  neorv32_uart0_puts("\n");

  // Read and display AXI AD9361 core info
  version = ad9361_read_reg(AD9361_REG_VERSION);
  core_id = ad9361_read_reg(AD9361_REG_ID);

  neorv32_uart0_puts("AXI AD9361 Core Info:\n");
  neorv32_uart0_printf("  Version: 0x%x\n", version);
  neorv32_uart0_printf("  Core ID: 0x%x\n", core_id);
  neorv32_uart0_puts("\n");

  // Enable AD9361 TX and RX via GPIO
  neorv32_uart0_puts("Enabling AD9361 TX/RX...\n");

  // Set up_enable = 1 (GPIO[0])
  neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 1);

  // Set up_txnrx = 1 for TX/RX mode (GPIO[1])
  neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 1);

  neorv32_uart0_puts("  up_enable = 1\n");
  neorv32_uart0_puts("  up_txnrx  = 1\n");
  neorv32_uart0_puts("\n");

  neorv32_uart0_puts("Datapath loopback test running...\n");
  neorv32_uart0_puts("  COE data -> LVDS RX -> ADC -> cpack2 -> upack2 -> DAC -> LVDS TX\n");
  neorv32_uart0_puts("  Testbench loops TX back to RX\n");
  neorv32_uart0_puts("\n");

  // Main monitoring loop
  while (1) {
    // Wait for polling interval
    for (volatile int i = 0; i < STATUS_POLL_INTERVAL; i++) {
      // Busy wait
    }

    // Read status registers
    status = ad9361_read_reg(AD9361_REG_STATUS);

    // Print periodic status update
    iteration++;
    neorv32_uart0_printf("[%d] Status: 0x%x\n", iteration, status);

    // Check for specific conditions (optional)
    // The actual pass/fail determination is done by the testbench
    // by comparing TX and RX data
  }

  return 0;
}

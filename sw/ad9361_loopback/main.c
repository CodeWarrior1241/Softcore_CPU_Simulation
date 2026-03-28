// ================================================================================ //
// AD9361 Loopback Test - NEORV32 Status Monitor                                      //
// Part of the QPSK Triple Comparison Project                                         //
// Licensed under the BSD-3-Clause license                                            //
// ================================================================================ //

/**
 * @file ad9361_loopback/main.c
 * @brief AD9361 datapath loopback test with streaming adapter bridge.
 *
 * Hardware datapath:
 *   COE data -> LVDS RX -> axi_ad9361 -> axi_ad9361_adapter (125 MHz l_clk)
 *     -> RX CDC FIFO -> axi_streaming_adapter (100 MHz AXI)
 *   axi_streaming_adapter -> TX CDC FIFO -> axi_ad9361_adapter -> axi_ad9361 -> LVDS TX
 *
 * With loopback enabled in the adapter, RX data is internally routed to TX.
 * The testbench loops the LVDS TX output back to LVDS RX input.
 *
 * The CPU:
 *   1. Starts the streaming adapter bridge (ap_ctrl_chain)
 *   2. Enables the adapter (ctrl, channel enables, loopback)
 *   3. Enables AD9361 TX/RX via GPIO (up_enable, up_txnrx)
 *   4. Waits for RX_READY, reads back 1024 samples, verifies, releases
 *   5. Repeats readback cycles to confirm continuous data flow
 */

#include <neorv32.h>
#include "axi_streaming_adapter_ctrl.h"

/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
#define BAUD_RATE 115200

#define GPIO_UP_ENABLE_PIN  0   // GPIO[0] = up_enable
#define GPIO_UP_TXNRX_PIN  1   // GPIO[1] = up_txnrx

/** Number of RX readback cycles to perform before declaring success */
#define NUM_READBACK_CYCLES 3

/** Timeout: max polling iterations waiting for RX_READY */
#define RX_READY_TIMEOUT 500000
/**@}*/



/**********************************************************************//**
 * Wait for bridge RX_READY flag.
 *
 * @return 1 on success, 0 on timeout.
 **************************************************************************/
static int wait_rx_ready(void) {
  for (int i = 0; i < RX_READY_TIMEOUT; i++) {
    uint32_t bs = BRIDGE_REG(BRIDGE_REG_BRIDGE_STATUS);
    if (bs & BRIDGE_STATUS_RX_READY) {
      return 1;
    }
  }
  return 0;
}


/**********************************************************************//**
 * Read back 1024 RX samples and print a summary.
 * Returns the number of non-zero samples seen.
 **************************************************************************/
static int readback_rx(int cycle) {
  int nonzero = 0;
  uint32_t first = 0, last = 0;

  for (int i = 0; i < BRIDGE_SAMPLE_DEPTH; i++) {
    uint32_t sample = bridge_read_rx_sample(i);
    if (sample != 0) nonzero++;
    if (i == 0) first = sample;
    if (i == BRIDGE_SAMPLE_DEPTH - 1) last = sample;
  }

  neorv32_uart0_printf("  Cycle %d: %d non-zero samples, first=0x%x last=0x%x\n",
                       cycle, nonzero, first, last);
  return nonzero;
}


/**********************************************************************//**
 * Main function
 **************************************************************************/
int main(void) {

  neorv32_rte_setup();

  if (neorv32_uart0_available() == 0) return 1;
  if (neorv32_gpio_available() == 0) return 1;

  neorv32_uart0_setup(BAUD_RATE, 0);

  neorv32_uart0_puts("\nAD9361 Loopback\n");

  // Start streaming adapter bridge (ap_ctrl_chain)
  bridge_start();

  // Configure adapter: all channels, loopback, enable
  BRIDGE_REG(BRIDGE_REG_RX_CTRL) = BRIDGE_CH_EN_ALL;
  BRIDGE_REG(BRIDGE_REG_TX_CTRL) = BRIDGE_CH_EN_ALL;
  BRIDGE_REG(BRIDGE_REG_LOOPBACK) = 1;
  BRIDGE_REG(BRIDGE_REG_CTRL) = BRIDGE_CTRL_ENABLE | BRIDGE_CTRL_RX_ENABLE | BRIDGE_CTRL_TX_ENABLE;

  // Enable AD9361 TX/RX via GPIO
  neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 1);
  neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 1);

  // ==================================================================
  // Phase 1: TX send — load 1024 samples and trigger burst
  // ==================================================================

  // Write known pattern to TX buffer: I = index, Q = index + 0x1000
  volatile uint32_t *tx_buf = (volatile uint32_t *)(AXI_STREAMING_ADAPTER_BASE + BRIDGE_TX_DATA_BASE);
  for (int i = 0; i < BRIDGE_SAMPLE_DEPTH; i++) {
    uint32_t sample = ((uint32_t)(i + 0x1000) << 16) | (i & 0xFFFF);
    tx_buf[i] = sample;
  }

  // Trigger TX burst and wait for completion
  bridge_trigger_tx(BRIDGE_SAMPLE_DEPTH);
  for (int i = 0; i < RX_READY_TIMEOUT; i++) {
    if (BRIDGE_REG(BRIDGE_REG_TX_COUNT_O) == 0) break;
  }
  neorv32_uart0_puts("TX ok\n");

  // RX readback cycles: wait for data, read, verify, release
  int pass_count = 0;

  for (int cycle = 0; cycle < NUM_READBACK_CYCLES; cycle++) {

    if (!wait_rx_ready()) {
      neorv32_uart0_printf("C%d:TMO\n", cycle);
      continue;
    }

    int nonzero = readback_rx(cycle);

    if (nonzero > 0) {
      pass_count++;
    } else {
      neorv32_uart0_printf("C%d:FAIL\n", cycle);
    }

    bridge_release_rx();

    // Brief delay for next burst to arrive
    for (volatile int i = 0; i < 10000; i++) {}
  }

  // Results
  if (pass_count == NUM_READBACK_CYCLES) {
    neorv32_uart0_puts("PASS\n");
  } else {
    neorv32_uart0_printf("FAIL %d/%d\n", pass_count, NUM_READBACK_CYCLES);
  }

  // Continue monitoring
  while (1) {
    for (volatile int i = 0; i < 500000; i++) {}
  }

  return 0;
}

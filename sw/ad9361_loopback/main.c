// ================================================================================ //
// AD9361 Loopback Test - NEORV32 Datapath Verification                               //
// Part of the QPSK Triple Comparison Project                                         //
// Licensed under the BSD-3-Clause license                                            //
// ================================================================================ //

/**
 * @file ad9361_loopback/main.c
 * @brief AD9361 datapath loopback test — fast simulation variant.
 *
 * All progress signaling via GPIO (zero sim-time cost).  UART used only
 * for a single final "P" (pass) or "F" (fail) character.
 *
 * GPIO output bit assignments:
 *   [0] up_enable    (AD9361 control — directly wired to axi_ad9361)
 *   [1] up_txnrx     (AD9361 control — directly wired to axi_ad9361)
 *   [2] milestone: AD9361 core configured
 *   [3] milestone: TX burst complete
 *   [4] milestone: all RX readback cycles done
 *   [5] result: 1 = PASS, 0 = FAIL
 *   [6] result valid (asserted once test is complete — testbench auto-terminates)
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
#define GPIO_AD9361_DONE   2   // GPIO[2] = AD9361 core configured
#define GPIO_TX_DONE       3   // GPIO[3] = TX burst complete
#define GPIO_RX_DONE       4   // GPIO[4] = RX readback cycles done
#define GPIO_RESULT        5   // GPIO[5] = 1=PASS 0=FAIL
#define GPIO_RESULT_VALID  6   // GPIO[6] = result valid (auto-terminate trigger)

/**********************************************************************//**
 * @name axi_ad9361 register definitions (base 0x44A00000)
 * These configure the ADI axi_ad9361 core's internal datapath.
 * Without these writes, ADC channels remain disabled and adc_valid
 * never asserts.  Register offsets from ADI HDL library.
 **************************************************************************/
#define AXI_AD9361_BASE         0x44A00000UL
#define AD9361_REG(off)         (*(volatile uint32_t *)(AXI_AD9361_BASE + (off)))

/* ADC common */
#define AD9361_REG_ADC_CNTRL    0x0044
#define AD9361_REG_ADC_RESET    0x0040

/* ADC channel control */
#define AD9361_REG_ADC_CH0_I    0x0400
#define AD9361_REG_ADC_CH0_Q    0x0440
#define AD9361_REG_ADC_CH1_I    0x0480
#define AD9361_REG_ADC_CH1_Q    0x04C0

/* DAC common */
#define AD9361_REG_DAC_CNTRL    0x4048
#define AD9361_REG_DAC_RATE     0x404C
#define AD9361_REG_DAC_SYNC     0x4044
#define AD9361_REG_DAC_RESET    0x4040

/* DAC channel control */
#define AD9361_REG_DAC_CH0_I    0x4418
#define AD9361_REG_DAC_CH0_Q    0x4458
#define AD9361_REG_DAC_CH1_I    0x4498
#define AD9361_REG_DAC_CH1_Q    0x44D8

/* DAC data source values */
#define DAC_SRC_DMA             0x00000002

/* ADC channel enable + signed format */
#define ADC_CHAN_ENABLE_SIGNED   0x00000051

/** Number of RX readback cycles to perform before declaring success */
#define NUM_READBACK_CYCLES 3

/** Timeout: max polling iterations waiting for RX_READY */
#define RX_READY_TIMEOUT 500000
/**@}*/


static int wait_rx_ready(void) {
  for (int i = 0; i < RX_READY_TIMEOUT; i++) {
    uint32_t bs = BRIDGE_REG(BRIDGE_REG_BRIDGE_STATUS);
    if (bs & BRIDGE_STATUS_RX_READY) {
      return 1;
    }
  }
  return 0;
}


// Read 1024 RX samples, return count of non-zero samples.
static int readback_rx(void) {
  int nonzero = 0;
  for (int i = 0; i < BRIDGE_SAMPLE_DEPTH; i++) {
    if (bridge_read_rx_sample(i) != 0) nonzero++;
  }
  return nonzero;
}


int main(void) {

  neorv32_rte_setup();

  if (neorv32_uart0_available() == 0) return 1;
  if (neorv32_gpio_available() == 0) return 1;

  neorv32_uart0_setup(BAUD_RATE, 0);

  // ==================================================================
  // Configure axi_ad9361 core registers
  // ==================================================================

  AD9361_REG(AD9361_REG_ADC_CNTRL) = 0x00000000;
  AD9361_REG(AD9361_REG_DAC_CNTRL) = 0x00000000;
  AD9361_REG(AD9361_REG_DAC_RATE)  = 0x00000003;

  AD9361_REG(AD9361_REG_DAC_CH0_I) = DAC_SRC_DMA;
  AD9361_REG(AD9361_REG_DAC_CH0_Q) = DAC_SRC_DMA;
  AD9361_REG(AD9361_REG_DAC_CH1_I) = DAC_SRC_DMA;
  AD9361_REG(AD9361_REG_DAC_CH1_Q) = DAC_SRC_DMA;

  AD9361_REG(AD9361_REG_ADC_CH0_I) = ADC_CHAN_ENABLE_SIGNED;
  AD9361_REG(AD9361_REG_ADC_CH0_Q) = ADC_CHAN_ENABLE_SIGNED;
  AD9361_REG(AD9361_REG_ADC_CH1_I) = ADC_CHAN_ENABLE_SIGNED;
  AD9361_REG(AD9361_REG_ADC_CH1_Q) = ADC_CHAN_ENABLE_SIGNED;

  AD9361_REG(AD9361_REG_DAC_SYNC)  = 0x00000001;
  AD9361_REG(AD9361_REG_ADC_CNTRL) = 0x00000001;

  AD9361_REG(AD9361_REG_ADC_RESET) = 0x00000003;
  AD9361_REG(AD9361_REG_DAC_RESET) = 0x00000003;

  for (volatile int i = 0; i < 2000; i++) {}

  neorv32_gpio_pin_set(GPIO_AD9361_DONE, 1);  // Milestone: core configured

  // ==================================================================
  // Start streaming adapter and configure datapath
  // ==================================================================

  bridge_start();

  BRIDGE_REG(BRIDGE_REG_RX_CTRL) = BRIDGE_CH_EN_ALL;
  BRIDGE_REG(BRIDGE_REG_TX_CTRL) = BRIDGE_CH_EN_ALL;
  BRIDGE_REG(BRIDGE_REG_LOOPBACK) = 1;
  BRIDGE_REG(BRIDGE_REG_CTRL) = BRIDGE_CTRL_ENABLE | BRIDGE_CTRL_RX_ENABLE |
                                  BRIDGE_CTRL_TX_ENABLE;
  // Note: RX_DRAIN is NOT asserted here.  It is pulsed per-cycle in the
  // readback loop below, after clearing the buffer and allowing it to fill.

  // Enable AD9361 TX/RX via GPIO
  neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 1);
  neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 1);

  // ==================================================================
  // TX: load 1024 samples and trigger burst
  // ==================================================================

  volatile uint32_t *tx_buf = (volatile uint32_t *)(AXI_STREAMING_ADAPTER_BASE + BRIDGE_TX_DATA_BASE);
  for (int i = 0; i < BRIDGE_SAMPLE_DEPTH; i++) {
    uint32_t sample = ((uint32_t)(i + 0x1000) << 16) | (i & 0xFFFF);
    tx_buf[i] = sample;
  }

  bridge_trigger_tx(BRIDGE_SAMPLE_DEPTH);
  for (int i = 0; i < RX_READY_TIMEOUT; i++) {
    if (BRIDGE_REG(BRIDGE_REG_TX_COUNT_O) == 0) break;
  }

  neorv32_gpio_pin_set(GPIO_TX_DONE, 1);  // Milestone: TX complete

  // ==================================================================
  // RX: readback cycles — wait, read, verify, release
  // ==================================================================

  int pass_count = 0;

  for (int cycle = 0; cycle < NUM_READBACK_CYCLES; cycle++) {
    // Clear RX buffer and let it fill with ADC samples
    BRIDGE_REG(BRIDGE_REG_CTRL) = BRIDGE_CTRL_ENABLE | BRIDGE_CTRL_RX_ENABLE |
                                    BRIDGE_CTRL_TX_ENABLE | BRIDGE_CTRL_RX_CLEAR;
    // Remove RX_CLEAR, let BRAM fill
    BRIDGE_REG(BRIDGE_REG_CTRL) = BRIDGE_CTRL_ENABLE | BRIDGE_CTRL_RX_ENABLE |
                                    BRIDGE_CTRL_TX_ENABLE;
    // Poll rx_fill until BRAM is full
    for (int i = 0; i < RX_READY_TIMEOUT; i++) {
      if (BRIDGE_REG(BRIDGE_REG_RX_FILL) >= BRIDGE_SAMPLE_DEPTH) break;
    }

    // Pulse RX_DRAIN to trigger burst from full BRAM
    BRIDGE_REG(BRIDGE_REG_CTRL) = BRIDGE_CTRL_ENABLE | BRIDGE_CTRL_RX_ENABLE |
                                    BRIDGE_CTRL_TX_ENABLE | BRIDGE_CTRL_RX_DRAIN;

    if (!wait_rx_ready()) continue;

    // Clear RX_DRAIN before reading
    BRIDGE_REG(BRIDGE_REG_CTRL) = BRIDGE_CTRL_ENABLE | BRIDGE_CTRL_RX_ENABLE |
                                    BRIDGE_CTRL_TX_ENABLE;

    int nonzero = readback_rx();
    if (nonzero > 0) pass_count++;

    bridge_release_rx();
  }

  neorv32_gpio_pin_set(GPIO_RX_DONE, 1);  // Milestone: RX done

  // ==================================================================
  // Signal result via GPIO — testbench auto-terminates on GPIO_RESULT_VALID
  // ==================================================================

  int pass = (pass_count == NUM_READBACK_CYCLES);

  if (pass) {
    neorv32_gpio_pin_set(GPIO_RESULT, 1);
  }
  neorv32_gpio_pin_set(GPIO_RESULT_VALID, 1);  // Trigger testbench $finish

  // Single UART character for transcript readability
  neorv32_uart0_putc(pass ? 'P' : 'F');

  // Halt
  while (1) {}

  return 0;
}

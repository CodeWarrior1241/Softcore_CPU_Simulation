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
 * The ad9361_adapter (v5.0) is a pure datapath — no software configuration.
 * TX: AXI-Stream → BRAM → continuous DAC playback
 * RX: ADC capture → BRAM → auto-drain to AXI-Stream when full (1024)
 *
 * The streaming_adapter (v3.0) is a state-machine bridge:
 *   IDLE → INIT_QPSK_DATA → SEND_AND_RECEIVE_QPSK_DATA → RECEIVE_QPSK_DATA
 * CPU writes tx_data[], pulses enable, bridge bursts TX and captures RX.
 * CPU reads rx_data[], pulses rx_read_done to release buffer for next capture.
 * CPU pulses reset to return to IDLE (for TX pattern reload).
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

/** Timeout: max polling iterations */
#define POLL_TIMEOUT 500000
/**@}*/


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
  // Enable AD9361 TX/RX via GPIO
  // ==================================================================

  neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 1);
  neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 1);

  // ==================================================================
  // TX: load 1024 samples, enable bridge → SEND → RECEIVE
  // ==================================================================

  volatile uint32_t *tx_buf = (volatile uint32_t *)(AXI_STREAMING_ADAPTER_BASE + BRIDGE_TX_DATA_BASE);
  for (int i = 0; i < BRIDGE_SAMPLE_DEPTH; i++) {
    uint32_t sample = ((uint32_t)(i + 0x1000) << 16) | (i & 0xFFFF);
    tx_buf[i] = sample;
  }

  bridge_enable_and_wait();  // Pulses enable, waits for RECEIVE state

  neorv32_gpio_pin_set(GPIO_TX_DONE, 1);  // Milestone: TX complete

  // ==================================================================
  // RX: readback cycles — wait for buffer full, read, verify, release
  //
  // The ad9361_adapter auto-drains its BRAM into rx_stream when full.
  // The streaming adapter captures 1024 samples into rx_data[].
  // CPU reads the snapshot, pulses rx_read_done to release buffer.
  // ==================================================================

  int pass_count = 0;

  for (int cycle = 0; cycle < NUM_READBACK_CYCLES; cycle++) {

    // Wait for RX buffer full (rx_sample_count reaches 1024)
    int rx_ok = 0;
    for (int i = 0; i < POLL_TIMEOUT; i++) {
      if (BRIDGE_REG(BRIDGE_REG_RX_COUNT) >= BRIDGE_SAMPLE_DEPTH) {
        rx_ok = 1;
        break;
      }
    }
    if (!rx_ok) continue;  // Timeout — skip this cycle

    // Cycle 0 is a dummy warm-up cycle.  In loopback mode, the first
    // 1024 RX samples are captured while the TX burst is still
    // propagating through the DAC → LVDS → loopback → ADC pipeline,
    // so they contain pre-loopback silence (zeros).  This is an
    // artifact of the test topology — in real operation the ADC always
    // has live antenna data and no warm-up is needed.  We still read
    // and release the buffer to advance the state machine, but don't
    // count it toward the pass criteria.
    int nonzero = readback_rx();
    if (cycle > 0 && nonzero > 0) pass_count++;

    // Release RX buffer for next capture
    bridge_rx_read_done();
  }

  neorv32_gpio_pin_set(GPIO_RX_DONE, 1);  // Milestone: RX done

  // ==================================================================
  // Signal result via GPIO — testbench auto-terminates on GPIO_RESULT_VALID
  // ==================================================================

  int pass = (pass_count == (NUM_READBACK_CYCLES - 1));

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

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
 *   [8] pwr_dn: fabric power-down lever (1 = down).  Gates the 300 MHz IODELAY
 *       refclk via BUFGCE and holds the axi_ad9361 + TX/RX datapath in reset.
 *   [9] TB-only model lever: 1 = AD9361 in SLEEP, so DATA_CLK (and l_clk) is
 *       stopped.  There is no chip/SPI/ENSM here, so the firmware drives this
 *       bit to tell the testbench to park stim_clk.  Kept separate from pwr_dn
 *       so the wake order matches hardware: l_clk returns ([9]=0) BEFORE pwr_dn
 *       clears ([8]=0), which is what the l_clk-domain reset + XPM synchronizer
 *       require (a reset released into a dead clock domain is unsafe).
 *
 * Bits [0..6] are the original 8-bit map; [8]/[9] live in the upper half of the
 * now-16-bit gpio_o (IO_GPIO_OUT_NUM was widened 8->16 for the power-down bits).
 * [9] needs no BD slice — only the testbench observes it.
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
#define GPIO_PWRDN_PIN     8   // GPIO[8] = pwr_dn: fabric clock-gate + reset-hold
#define GPIO_LCLK_DEAD_PIN 9   // GPIO[9] = TB-only: model AD9361 SLEEP (stops l_clk)

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

/** Directed power-gate cycle busy-loop delays (sim-time only — this firmware
 *  has no no_os timer).  Calibrated against the measured ~207 ns per volatile
 *  loop iteration on this NEORV32 build:
 *    LCLK_DEAD_SETTLE  ~0.4 ms — let l_clk die / return around each pwr_dn edge
 *    PWRDN_HOLD        ~1.7 ms — stay down; with the dead-settle this keeps
 *                                l_clk stopped >1 ms so the TB's death detector
 *                                trips exactly once
 *    PWRUP_SETTLE      ~0.4 ms — fabric reset re-sequence after pwr_dn clears
 *  The whole cycle plus re-config/re-prime/re-readback then finishes well
 *  inside the testbench's 15 ms safety timeout. */
#define LCLK_DEAD_SETTLE_ITERS  2000
#define PWRDN_HOLD_ITERS        8000
#define PWRUP_SETTLE_ITERS      2000
/**@}*/


// Hardware multiplier self-test.  Volatile operands defeat constant folding
// so an rv32im build emits real MUL/MULH/MULHU instructions — on the mpf300
// build this exercises the pipelined fast multiplier (CPU_FAST_MUL_PIPELINE,
// neorv32 PR #1603: an S_PIPE wait state adds one result-latency cycle, so a
// wrong-phase valid_o would return garbage here).  An rv32i build (axau15)
// compiles this to soft-multiply calls and still passes.
static int mul_selftest(void) {
  volatile int32_t  sa = -123456789, sb = 3579;
  volatile uint32_t ua = 0xDEADBEEFu, ub = 0x1000193u;
  int ok = 1;
  ok &= ((int32_t)(sa * sb) == (int32_t)0x1F93DB69);            // MUL (low)
  ok &= ((int32_t)(((int64_t)sa * sb) >> 32) == (int32_t)-103); // MULH
  ok &= ((uint32_t)(ua * ub) == 0x7A83923Du);                   // MUL (low, unsigned)
  ok &= ((uint32_t)(((uint64_t)ua * ub) >> 32) == 0xDEAF1Du);   // MULHU
  return ok;
}

// Read 1024 RX samples, return count of non-zero samples.
static int readback_rx(void) {
  int nonzero = 0;
  for (int i = 0; i < BRIDGE_SAMPLE_DEPTH; i++) {
    if (bridge_read_rx_sample(i) != 0) nonzero++;
  }
  return nonzero;
}

// Configure (or re-configure) the axi_ad9361 core datapath registers.
// Run at boot and again after the power-gate cycle: the gated s_axi_aresetn
// returns these registers to their power-on defaults during power-down.
static void configure_ad9361(void) {
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

  for (volatile int i = 0; i < 2000; i++) {}  // let the config settle
}

// Fill the bridge TX sample buffer with the known ramp pattern.
static void load_tx_buffer(void) {
  volatile uint32_t *tx_buf = (volatile uint32_t *)(AXI_STREAMING_ADAPTER_BASE + BRIDGE_TX_DATA_BASE);
  for (int i = 0; i < BRIDGE_SAMPLE_DEPTH; i++) {
    tx_buf[i] = ((uint32_t)(i + 0x1000) << 16) | (i & 0xFFFF);
  }
}

// Run NUM_READBACK_CYCLES capture cycles; return the number of passing cycles.
// Cycle 0 is a warm-up (the TX burst is still propagating through the
// DAC→LVDS→loopback→ADC pipeline, so the first buffer is pre-loopback silence)
// and never counts toward the pass total — same artifact at boot and at wake.
static int run_readback_cycles(void) {
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

    int nonzero = readback_rx();
    if (cycle > 0 && nonzero > 0) pass_count++;

    // Release RX buffer for next capture
    bridge_rx_read_done();
  }
  return pass_count;
}


int main(void) {

  neorv32_rte_setup();

  if (neorv32_uart0_available() == 0) return 1;
  if (neorv32_gpio_available() == 0) return 1;

  neorv32_uart0_setup(BAUD_RATE, 0);

  // ==================================================================
  // Configure axi_ad9361 core registers
  // ==================================================================

  configure_ad9361();

  neorv32_gpio_pin_set(GPIO_AD9361_DONE, 1);  // Milestone: core configured

  // ==================================================================
  // Enable AD9361 TX/RX via GPIO
  // ==================================================================

  neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 1);
  neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 1);

  // ==================================================================
  // TX: load 1024 samples, enable bridge → SEND → RECEIVE
  // ==================================================================

  load_tx_buffer();

  bridge_enable_and_wait();  // Pulses enable, waits for RECEIVE state

  neorv32_gpio_pin_set(GPIO_TX_DONE, 1);  // Milestone: TX complete

  // ==================================================================
  // RX: readback cycles — wait for buffer full, read, verify, release
  //
  // The ad9361_adapter auto-drains its BRAM into rx_stream when full.
  // The streaming adapter captures 1024 samples into rx_data[].
  // CPU reads the snapshot, pulses rx_read_done to release buffer.
  // ==================================================================

  int pass_count = run_readback_cycles();

  neorv32_gpio_pin_set(GPIO_RX_DONE, 1);  // Milestone: RX done

  // ==================================================================
  // Directed power-gate cycle — the fabric half of the power-down feature
  //
  // This sim has no AD9361 / SPI / ENSM model (the testbench is the chip), so
  // SLEEP is modelled by stopping l_clk.  Two separate levers are driven, in
  // the same order hardware would, so the wake invariant holds:
  //   gpio_o[9] (GPIO_LCLK_DEAD_PIN): TB-only "chip clock stopped" — parks
  //             stim_clk so DATA_CLK / l_clk dies (models ENSM SLEEP / FDD).
  //   gpio_o[8] (GPIO_PWRDN_PIN):     the real fabric lever — gates the 300 MHz
  //             IODELAY refclk (BUFGCE) and holds axi_ad9361 + the TX/RX
  //             datapath in reset.
  //
  // Down: stop l_clk FIRST, then engage pwr_dn (stop the clock before gating
  // the logic it feeds).  Up: bring l_clk back FIRST, while pwr_dn is still 1,
  // so the armed l_clk-domain reset catches the returning clock and the XPM
  // synchronizer sees a live destination clock; THEN clear pwr_dn.  Releasing
  // pwr_dn re-pulses the IP's delay_rst and cold-resets the datapath; the gated
  // reset wiped the axi_ad9361 registers back to defaults, so we re-configure,
  // re-prime the TX burst, and re-capture.  PASS requires valid RX again after
  // the cycle — proving the fabric gating + reset-hold + l_clk stop/restart
  // recovery.
  // ==================================================================

  // --- Power down ---
  neorv32_gpio_pin_set(GPIO_LCLK_DEAD_PIN, 1);  // model SLEEP: TB parks stim_clk -> l_clk dies
  for (volatile int i = 0; i < LCLK_DEAD_SETTLE_ITERS; i++) {}  // let l_clk stop before gating
  neorv32_gpio_pin_set(GPIO_PWRDN_PIN, 1);      // fabric: gate clk_out2 + hold resets
  for (volatile int i = 0; i < PWRDN_HOLD_ITERS; i++) {}        // hold in the low-power state

  // --- Power up ---
  neorv32_gpio_pin_set(GPIO_LCLK_DEAD_PIN, 0);  // model FDD: TB restarts stim_clk -> l_clk returns
  for (volatile int i = 0; i < LCLK_DEAD_SETTLE_ITERS; i++) {}  // let l_clk run (reset asserts) while pwr_dn still 1
  neorv32_gpio_pin_set(GPIO_PWRDN_PIN, 0);      // release fabric AFTER l_clk is back
  for (volatile int i = 0; i < PWRUP_SETTLE_ITERS; i++) {}      // reset re-sequence

  configure_ad9361();                        // registers were reset to defaults while gated
  neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 1);
  neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 1);

  bridge_reset();                            // bridge FSM back to IDLE
  load_tx_buffer();                          // re-prime the TX burst
  bridge_enable_and_wait();

  int post_wake_nonzero = run_readback_cycles();

  // ==================================================================
  // Signal result via GPIO — testbench auto-terminates on GPIO_RESULT_VALID
  // ==================================================================

  int pass = (pass_count == (NUM_READBACK_CYCLES - 1)) && (post_wake_nonzero > 0)
             && mul_selftest();

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

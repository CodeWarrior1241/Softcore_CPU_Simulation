/*
 * AD9361 no-os driver application for NEORV32 + FMCOMMS2/4 on AU15P.
 *
 * Initialises the AD9361 via SPI using the Analog Devices no-os driver,
 * sets FDD mode at 2.4 GHz, and enters a status monitoring loop.
 */

#include <neorv32.h>
#include <stddef.h>
#include "ad9361.h"
#include "ad9361_api.h"
#include "axi_adc_core.h"
#include "axi_dac_core.h"
#include "no_os_delay.h"
#include "parameters.h"
#include "neorv32_no_os_spi.h"
#include "neorv32_no_os_gpio.h"
#include "axi_streaming_adapter_ctrl.h"
#include "qpsk_tx_data.h"

/* ---------- UART command interface ---------- */
#define CMD_BUFFER_SIZE    32
#define NUM_RX_SAMPLES     1024

/* Command strings */
#define CMD_ENABLE_RF       "enable_rf"
#define CMD_DISABLE_RF      "disable_rf"
#define CMD_ENABLE_SNAPSHOT "enable_snapshot"
#define CMD_GET_STATUS      "get_status"
#define CMD_GET_ADC_STATUS  "get_adc_status"
#define CMD_GET_DAC_STATUS  "get_dac_status"
#define CMD_GET_CHIP_STATUS "get_chip_status"
#define CMD_GET_VALID_RATE  "get_valid_rate"
#define CMD_HOLD_BIST       "hold_bist"
#define CMD_STOP_BIST       "stop_bist"
#define CMD_PINCTL_RX       "pinctl_rx"
#define CMD_PINCTL_OFF      "pinctl_off"
#define CMD_LOOPBACK_ON     "loopback_on"
#define CMD_LOOPBACK_OFF    "loopback_off"
#define CMD_CLKSEL_ON       "clksel_on"      /* invert TX FB_CLK (mid-eye A/B test) */
#define CMD_CLKSEL_OFF      "clksel_off"     /* FB_CLK back to edge-aligned default */
#define CMD_SET_TX_ATTEN    "set_tx_atten"   /* + integer mdB  (R4 sweep) */
#define CMD_SET_RX_GAIN     "set_rx_gain"    /* + integer dB   (R4 sweep) */
#define CMD_GET_RSSI        "get_rssi"       /* compact RSSI + gain line */
#define CMD_POWER_DOWN      "power_down"     /* Tier-1 deep low-power: ENSM SLEEP + gating */
#define CMD_POWER_UP        "power_up"       /* wake + re-init datapath */
#define CMD_POWER_DOWN_T0   "power_down_t0"  /* bench twin of power_down (Tier-0); see handler */
#define CMD_POWER_UP_T0     "power_up_t0"    /* bench twin of power_up + verbose capture probe */

/* Response strings */
#define RESP_RF_ENABLED     "rf_enabled\n"
#define RESP_RF_DISABLED    "rf_disabled\n"
#define RESP_SNAPSHOT       "snapshot_enabled\n"

/* ---------- axi_ad9361 register access ---------- */
/* up_clock_mon counts DATA_CLK ticks against the AXI/up_clk domain, which in
 * BOTH builds is the CPU clock domain (axau15: 150 MHz, mpf300: 125 MHz PF_CCC
 * fabric clock). Read it from SYSINFO at runtime so the single shared image
 * reports l_clk correctly on either board (a 150 MHz hardcode made the mpf300
 * report 61.44 MHz * 150/125 = 73.7 MHz). */
#define AXI_CLK_HZ                  ((uint32_t)NEORV32_SYSINFO->CLK)
#define AD9361_REG(off)             (*(volatile uint32_t *)(AXI_AD9361_BASE + (off)))

/* The shared image tells the two platforms apart by the CPU clock. */
#define PLATFORM_IS_XILINX()        (AXI_CLK_HZ > 140000000UL)

/* IDELAYCTRL reference frequency feeding the IDELAYE3 primitives in axi_ad9361
 * -- Xilinx (au15p/axau15) build ONLY. MUST stay in sync with
 * CONFIG.DELAY_REFCLK_FREQUENCY in
 * deps/hdl/projects/fmcomms2/au15p/build_all.tcl (the axi_ad9361 IP cell).
 * Used only by dump_adc_status() to print the LVDS tap-resolution margin.
 * The PolarFire (mpf300) port has no IDELAY primitives (static SDC timing;
 * delay_clk is just the 125 MHz fabric clock), so the tap math is meaningless
 * there and dump_adc_status() skips it. */
#define DELAY_REFCLK_HZ             300000000UL

/* ADC common registers (cf. up_adc_common.v decode at 7'h10..7'h17) */
#define ADC_REG_RSTN                0x0040
#define ADC_REG_CNTRL               0x0044
#define ADC_REG_CLK_FREQ            0x0054
#define ADC_REG_CLK_RATIO           0x0058
#define ADC_REG_STATUS              0x005C

/* ADC per-channel (ch ∈ 0..3 → I0,Q0,I1,Q1; cf. up_adc_channel.v) */
#define ADC_CH_BASE(ch)             (0x0400 + ((ch) * 0x40))
#define ADC_CH_REG_CTRL             0x0000
#define ADC_CH_REG_STATUS           0x0004
#define ADC_CH_REG_DATA             0x0008

/* DAC mirrors ADC layout, 0x4000 offset */
#define DAC_REG_RSTN                0x4040
#define DAC_REG_CNTRL               0x4044
#define DAC_REG_CLK_FREQ            0x4054
#define DAC_REG_CLK_RATIO           0x4058
#define DAC_REG_STATUS              0x405C
/* up_dac_common word 7'h18, bit 0 (dac_clksel): swaps the DDR bit order of
 * the transmitted FB_CLK, i.e. inverts it by 180 deg. On the PolarFire port
 * the fabric-emulated DDR outputs launch FB_CLK edge-aligned with the TX
 * data transitions (dac_clksel=0), so the AD9361 samples at the eye edge;
 * dac_clksel=1 moves the FB_CLK edges half a UI to mid-eye. Runtime A/B
 * knob for the TX-interface timing (see clksel_on/clksel_off commands). */
#define DAC_REG_CLKSEL              0x4060

/* up_clock_mon counts d_clk ticks per 65536 up_clk ticks */
#define CLK_MON_WINDOW              65536UL

static int rf_enabled = 0;
static int power_state = 1;      /* 1 = up, 0 = powered down (Tier 1 low-power) */

/* Boot snapshot of the TX1 quadrature-correction registers (chip SPI:
 * 0x08E/0x08F TX1 out1 phase/gain, 0x096/0x097 TX1 out2 phase/gain). These hold
 * the result of the TX_QUAD hardware cal. Re-running that cal on each wake
 * "succeeds" (ret=0) but drifts to a bad solution (~1 dB I/Q imbalance, EVM 60%
 * by the 2nd cycle), so power_up RESTORES this boot result instead. */
static const uint16_t TX_QUAD_CORR_REG[4] = { 0x08E, 0x08F, 0x096, 0x097 };
static uint8_t  tx_quad_corr_snap[4];
static int      tx_quad_corr_valid = 0;

/*
 * Read a LF/CR-terminated command line from UART (blocking).
 * Returns number of characters read, or -1 on overflow.
 */
static int read_command(char *buffer, int max_len)
{
	int idx = 0;
	char c;

	while (idx < max_len - 1) {
		c = neorv32_uart0_getc();
		if (c == '\n' || c == '\r') {
			buffer[idx] = '\0';
			return idx;
		}
		buffer[idx++] = c;
	}
	buffer[max_len - 1] = '\0';
	return -1;
}

/* Compare command string (case-sensitive, ignores trailing CR/LF). */
static int strcmp_cmd(const char *cmd, const char *ref)
{
	while (*ref) {
		if (*cmd != *ref)
			return 0;
		cmd++;
		ref++;
	}
	return (*cmd == '\0' || *cmd == '\r' || *cmd == '\n');
}

/* If `cmd` starts with `prefix` followed by whitespace + a (signed) integer,
 * parse the integer into *arg and return 1. Else return 0. Used by the R4
 * runtime tuning commands ("set_tx_atten 10000", "set_rx_gain 30"). */
static int parse_cmd_arg(const char *cmd, const char *prefix, long *arg)
{
	while (*prefix) {
		if (*cmd != *prefix)
			return 0;
		cmd++;
		prefix++;
	}
	if (*cmd != ' ' && *cmd != '\t')
		return 0;
	while (*cmd == ' ' || *cmd == '\t')
		cmd++;

	int neg = 0;
	if (*cmd == '-') { neg = 1; cmd++; }
	if (*cmd < '0' || *cmd > '9')
		return 0;

	long v = 0;
	while (*cmd >= '0' && *cmd <= '9') {
		v = v * 10 + (*cmd - '0');
		cmd++;
	}
	*arg = neg ? -v : v;
	return 1;
}

/* Send 1024 RX samples from bridge RX buffer as 4096 raw bytes over UART. */
static void send_rx_snapshot(void)
{
	for (uint32_t i = 0; i < NUM_RX_SAMPLES; i++) {
		uint32_t iq_word = bridge_read_rx_sample(i);
		int16_t i_val = (int16_t)(iq_word & 0xFFFF);
		int16_t q_val = (int16_t)((iq_word >> 16) & 0xFFFF);
		neorv32_uart0_putc((char)(i_val & 0xFF));
		neorv32_uart0_putc((char)((i_val >> 8) & 0xFF));
		neorv32_uart0_putc((char)(q_val & 0xFF));
		neorv32_uart0_putc((char)((q_val >> 8) & 0xFF));
	}
}

static const char *ensm_mode_str[] = {
	[ENSM_MODE_TX]               = "TX",
	[ENSM_MODE_RX]               = "RX",
	[ENSM_MODE_ALERT]            = "ALERT",
	[ENSM_MODE_FDD]              = "FDD",
	[ENSM_MODE_WAIT]             = "WAIT",
	[ENSM_MODE_SLEEP]            = "SLEEP",
	[ENSM_MODE_PINCTRL]          = "PINCTRL",
	[ENSM_MODE_PINCTRL_FDD_INDEP] = "PINCTRL_FDD_INDEP",
};

/* axi_ad9361 IP: 4 ADC channels (I0,Q0,I1,Q1) and 4 DAC channels in 2R2T mode.
 * Required by ad9361_init() now that AXI_ADC_NOT_PRESENT is no longer defined,
 * so the real ad9361_dig_tune() can drive the IP via these descriptors.
 * ad9361_init() itself skips dig_tune (digital_interface_tune_skip_mode=2); an
 * explicit RX dig_tune is run post-init (step 6.7) — it passes on the axau15
 * and yields the working RX capture. The diagnostic dumps below are retained
 * for future LVDS-capture debugging. */
struct axi_adc_init rx_adc_init = {
	.name         = "rx_adc",
	.base         = AXI_AD9361_BASE,        /* shared with axi_ad9361 IP */
	.num_channels = 2,                      /* 1R1T = I + Q */
};

struct axi_dac_init tx_dac_init = {
	.name         = "tx_dac",
	.base         = AXI_AD9361_BASE,        /* DAC regs at +0x4000 internally */
	.num_channels = 2,                      /* 1R1T = I + Q */
	.channels     = NULL,
	.rate         = 1,                      /* (rate-1) for 1R1T LVDS DDR */
};

/* ============================================================
 *  Phase 1 / Phase 2 RX-path diagnostics
 *
 *  Used both as a one-shot boot dump and as runtime UART
 *  commands (get_adc_status / get_dac_status / get_chip_status).
 *  Read l_clk health, axi_ad9361 link/PN status, per-channel
 *  enables, and the AD9361 chip's own RX-enable + ENSM state.
 * ============================================================ */

/* Forward decl: default_init_param is defined later in this TU but
 * dump_adc_status() reads two_rx_two_tx_mode_enable to compute the
 * expected DATA_CLK rate. */
extern AD9361_InitParam default_init_param;

static uint32_t compute_clk_hz(uint32_t freq_count)
{
	/* up_clock_mon: l_clk_hz = (count * AXI_CLK_HZ) / 65536 (64-bit safe). */
	return (uint32_t)(((uint64_t)freq_count * (uint64_t)AXI_CLK_HZ) /
			  (uint64_t)CLK_MON_WINDOW);
}

/* Poll the up_clock_mon l_clk readout until it is within ~2% of the expected
 * DATA_CLK rate. The platform-common "link clock is really back" gate for
 * power_up: on PolarFire l_clk is the PF_CCC PLL output, which FREE-RUNS at a
 * drift frequency while the chip sleeps (reference lost) and must relock to
 * the returned DATA_CLK before any interface traffic -- the same lock also
 * re-establishes the OUT0/OUT1 +90 deg FB_CLK relationship (Post-VCO
 * feedback). On Xilinx l_clk is a buffer, so this just confirms DATA_CLK
 * returned. The monitor window is 65536 AXI clocks (~0.5 ms), so 1 ms poll
 * steps always see a fresh measurement. Returns the wait in ms, or -1 on
 * timeout (~500 ms, far above the CCC's ms-class relock time). */
static int wait_l_clk_rate(void)
{
	int is_2r2t = default_init_param.two_rx_two_tx_mode_enable ? 1 : 0;
	uint32_t expected = default_init_param.rx_path_clock_frequencies[5] *
			    (is_2r2t ? 4u : 2u);
	uint32_t tol = expected / 50u;   /* ~2% */

	for (int ms = 0; ms < 500; ms++) {
		uint32_t hz = compute_clk_hz(AD9361_REG(ADC_REG_CLK_FREQ));
		uint32_t err = (hz > expected) ? (hz - expected) : (expected - hz);
		if (err <= tol)
			return ms;
		no_os_mdelay(1);
	}
	return -1;
}

static void dump_adc_status(void)
{
	uint32_t freq   = AD9361_REG(ADC_REG_CLK_FREQ);
	uint32_t ratio  = AD9361_REG(ADC_REG_CLK_RATIO);
	uint32_t status = AD9361_REG(ADC_REG_STATUS);
	uint32_t rstn   = AD9361_REG(ADC_REG_RSTN);
	uint32_t l_clk  = compute_clk_hz(freq);

	/* AD9361 LVDS DDR DATA_CLK rate = FSAMP * M, where M=2 (1R1T) or M=4 (2R2T).
	 * Compute expected from the active init param + chip rx_path_clks so the
	 * note stays correct if either changes. */
	int is_2r2t = default_init_param.two_rx_two_tx_mode_enable ? 1 : 0;
	uint32_t fsamp = default_init_param.rx_path_clock_frequencies[5];  /* RX_SAMPL_FREQ */
	uint32_t expected_dclk = fsamp * (is_2r2t ? 4u : 2u);

	neorv32_uart0_puts("[adc_status]\n");
	neorv32_uart0_printf("  clk_freq_count=%u ratio_reg=%u l_clk_hz=%u (expect %u for %s LVDS DDR)\n",
			     (unsigned)freq, (unsigned)ratio, (unsigned)l_clk,
			     (unsigned)expected_dclk, is_2r2t ? "2R2T" : "1R1T");

	/* IDELAYE3 tap-resolution margin against the measured LVDS UI.
	 *   fine tap   = 1 / (32 * REFCLK)
	 *   sw step    = 16 * fine tap   (ADI wrapper exposes only upper 5 of 9 bits)
	 *   UI         = 1 / (2 * l_clk) (LVDS DDR: 1 bit per half-cycle of DATA_CLK)
	 *   taps_in_UI = UI / sw_step    (= 16ths how many software steps fit per bit)
	 * Want > 3 for dig_tune to find a stable lock.
	 * Xilinx build only: PolarFire has no IDELAY primitives, so on mpf300
	 * this math describes nothing -- print the static-timing note instead. */
	if (!PLATFORM_IS_XILINX()) {
		neorv32_uart0_puts("  delay: static SDC timing (PolarFire; no IDELAY primitives, tap metrics n/a)\n");
	} else if (l_clk > 0) {
		uint32_t fine_tap_ps = (uint32_t)(1000000000000ULL /
						   ((uint64_t)DELAY_REFCLK_HZ * 32ULL));
		uint32_t sw_step_ps  = fine_tap_ps * 16U;
		uint32_t ui_ps       = (uint32_t)(1000000000000ULL /
						   ((uint64_t)l_clk * 2ULL));
		/* Fixed-point taps_in_UI ×100 to keep one decimal place. */
		uint32_t taps_x100   = (uint32_t)(((uint64_t)ui_ps * 100ULL) /
						   (uint64_t)sw_step_ps);
		/* NEORV32 printf doesn't honor width/zero-pad specifiers (e.g. %02u),
		 * so format the 2-digit fractional part by hand. */
		char frac_buf[3];
		frac_buf[0] = '0' + (char)((taps_x100 % 100U) / 10U);
		frac_buf[1] = '0' + (char)((taps_x100 % 100U) % 10U);
		frac_buf[2] = '\0';
		neorv32_uart0_printf("  idelay refclk_hz=%u fine_tap=%ups sw_step=%ups ui=%ups sw_taps_per_ui=%u.%s (>3 = healthy)\n",
				     (unsigned)DELAY_REFCLK_HZ,
				     (unsigned)fine_tap_ps,
				     (unsigned)sw_step_ps,
				     (unsigned)ui_ps,
				     (unsigned)(taps_x100 / 100U),
				     frac_buf);
	}
	neorv32_uart0_printf("  rstn=0x%x status=0x%x  link_ok=%u or=%u pn_oos=%u pn_err=%u ctrl=%u\n",
			     (unsigned)rstn, (unsigned)status,
			     (unsigned)(status & 0x1),
			     (unsigned)((status >> 1) & 0x1),
			     (unsigned)((status >> 2) & 0x1),
			     (unsigned)((status >> 3) & 0x1),
			     (unsigned)((status >> 4) & 0x1));
	/* On PolarFire the fabric feeds the PF_CCC lock into the status bit
	 * (lvds_if: adc_status = lock && frame-ok), so link_ok doubles as the
	 * l_clk PLL lock indicator: 1 in operation, 0 while the chip sleeps
	 * (DATA_CLK absent -> CCC reference lost). */
	if (!PLATFORM_IS_XILINX())
		neorv32_uart0_printf("  l_clk_pll_locked=%u (PolarFire: link_ok = PF_CCC lock && frame ok)\n",
				     (unsigned)(status & 0x1));

	static const char *ch_names[4] = { "ch0_I", "ch0_Q", "ch1_I", "ch1_Q" };
	for (int ch = 0; ch < 4; ch++) {
		uint32_t base  = ADC_CH_BASE(ch);
		uint32_t ctrl  = AD9361_REG(base + ADC_CH_REG_CTRL);
		uint32_t cstat = AD9361_REG(base + ADC_CH_REG_STATUS);
		uint32_t cdata = AD9361_REG(base + ADC_CH_REG_DATA);
		neorv32_uart0_printf("  %s ctrl=0x%x status=0x%x data=0x%x  or=%u pn_oos=%u pn_err=%u hdr=%u crc=%u\n",
				     ch_names[ch],
				     (unsigned)ctrl, (unsigned)cstat, (unsigned)cdata,
				     (unsigned)(cstat & 0x1),
				     (unsigned)((cstat >> 1) & 0x1),
				     (unsigned)((cstat >> 2) & 0x1),
				     (unsigned)((cstat >> 4) & 0x1),
				     (unsigned)((cstat >> 5) & 0x1));
	}
}

static void dump_dac_status(void)
{
	uint32_t freq   = AD9361_REG(DAC_REG_CLK_FREQ);
	uint32_t ratio  = AD9361_REG(DAC_REG_CLK_RATIO);
	uint32_t status = AD9361_REG(DAC_REG_STATUS);
	uint32_t rstn   = AD9361_REG(DAC_REG_RSTN);
	uint32_t l_clk  = compute_clk_hz(freq);

	neorv32_uart0_puts("[dac_status]\n");
	neorv32_uart0_printf("  clk_freq_count=%u ratio_reg=%u l_clk_hz=%u\n",
			     (unsigned)freq, (unsigned)ratio, (unsigned)l_clk);
	neorv32_uart0_printf("  rstn=0x%x status=0x%x\n",
			     (unsigned)rstn, (unsigned)status);
}

static const char *ad9361_state_name(uint8_t state)
{
	switch (state & 0xF) {
	case 0x0: return "SLEEP_WAIT";
	case 0x1: return "SLEEP";
	case 0x5: return "ALERT";
	case 0x6: return "TX";
	case 0x7: return "TX_FLUSH";
	case 0x8: return "RX";
	case 0x9: return "RX_FLUSH";
	case 0xA: return "FDD";
	case 0xB: return "FDD_FLUSH";
	default:  return "?";
	}
}

static void dump_chip_status(struct ad9361_rf_phy *phy)
{
	if (!phy || !phy->spi) {
		neorv32_uart0_puts("[chip_status] phy/spi null — skipping\n");
		return;
	}

	static const struct { uint32_t reg; const char *name; } regs[] = {
		{ 0x002, "tx_enable_filter_ctrl" },
		{ 0x003, "rx_enable_filter_ctrl" },
		{ 0x005, "ensm_config_2"         },
		{ 0x010, "parallel_port_conf_1"  },
		{ 0x011, "parallel_port_conf_2"  },
		{ 0x012, "parallel_port_conf_3"  },
		{ 0x017, "state"                 },
		{ 0x247, "synth_lock_status"     },
	};

	neorv32_uart0_puts("[chip_status]\n");
	for (size_t i = 0; i < sizeof(regs) / sizeof(regs[0]); i++) {
		int32_t v = ad9361_spi_read(phy->spi, regs[i].reg);
		if (v < 0) {
			neorv32_uart0_printf("  %s (0x%x): SPI ERROR %d\n",
					     regs[i].name, (unsigned)regs[i].reg, (int)v);
		} else {
			neorv32_uart0_printf("  %s (0x%x) = 0x%x\n",
					     regs[i].name, (unsigned)regs[i].reg,
					     (unsigned)(v & 0xFF));
		}
	}

	int32_t rx_en = ad9361_spi_read(phy->spi, 0x003);
	if (rx_en >= 0) {
		/* Per RX_CHANNEL_ENABLE(x) macro in ad9361.h, value x is shifted
		 * to bits 7:6.  x=1 (binary 01) sets bit 6 = RX1, x=2 (binary 10)
		 * sets bit 7 = RX2. So bit 6 = RX1, bit 7 = RX2. */
		neorv32_uart0_printf("  RX1_EN=%u RX2_EN=%u  (both 0 => chip is not producing RX samples)\n",
				     (unsigned)((rx_en >> 6) & 0x1),
				     (unsigned)((rx_en >> 7) & 0x1));
	}
	int32_t tx_en = ad9361_spi_read(phy->spi, 0x002);
	if (tx_en >= 0) {
		neorv32_uart0_printf("  TX1_EN=%u TX2_EN=%u\n",
				     (unsigned)((tx_en >> 6) & 0x1),
				     (unsigned)((tx_en >> 7) & 0x1));
	}
	int32_t state = ad9361_spi_read(phy->spi, 0x017);
	if (state >= 0) {
		neorv32_uart0_printf("  ENSM state=0x%x (%s)\n",
				     (unsigned)(state & 0xF),
				     ad9361_state_name((uint8_t)state));
	}

	/* ------------------------------------------------------------------
	 * Extended chip-health diagnostics. These directly answer:
	 *   - Is the chip alive at the SPI level?  (chip_id)
	 *   - Are the PLLs locked?                  (BB PLL + synth_lock decode)
	 *   - Are calibrations passing?             (synth_lock_status bits)
	 *   - Is there RF signal at the RX baseband? (RSSI)
	 *   - What gain is the RX path running at?  (RX RF gain)
	 *   - What does the chip think its clocks are? (sampling/LO readback)
	 * ------------------------------------------------------------------ */

	/* Chip ID: reg 0x037, expected 0xA on AD9361. Confirms SPI works
	 * and that we're actually talking to the chip we think we are. */
	int32_t chip_id = ad9361_spi_read(phy->spi, 0x037);
	if (chip_id >= 0) {
		neorv32_uart0_printf("  chip_id (0x037) = 0x%x  (expect 0xa for AD9361%s)\n",
				     (unsigned)(chip_id & 0xFF),
				     ((chip_id & 0xFF) == 0xA) ? " — OK" : " — MISMATCH");
	} else {
		neorv32_uart0_printf("  chip_id (0x037): SPI ERROR %d\n", (int)chip_id);
	}

	/* BB PLL lock: reg 0x05E bit 7 = BBPLL_LOCK. If 0, the chip's
	 * master baseband clock is not locked and nothing downstream works. */
	int32_t bbpll = ad9361_spi_read(phy->spi, 0x05E);
	if (bbpll >= 0) {
		unsigned locked = (unsigned)((bbpll >> 7) & 0x1);
		neorv32_uart0_printf("  bbpll (0x05E) = 0x%x  bbpll_lock=%u%s\n",
				     (unsigned)(bbpll & 0xFF), locked,
				     locked ? "" : " — BB PLL NOT LOCKED");
	}

	/* Decode reg 0x247 = REG_RX_CP_OVERRANGE_VCO_LOCK. RX-only register.
	 * Per ad9361.h:
	 *   bit 1 = VCO_LOCK       (RX VCO locked)
	 *   bit 6 = CP_OVRG_LOW    (RX charge pump over-range low)
	 *   bit 7 = CP_OVRG_HIGH   (RX charge pump over-range high) */
	int32_t rx_cp = ad9361_spi_read(phy->spi, 0x247);
	if (rx_cp >= 0) {
		unsigned v = (unsigned)(rx_cp & 0xFF);
		neorv32_uart0_printf("  rx_cp_vco (0x247=0x%x):"
				     " rx_vco_lock=%u cp_ovrg_low=%u cp_ovrg_high=%u\n",
				     v,
				     (v >> 1) & 1, (v >> 6) & 1, (v >> 7) & 1);
	}

	/* Decode reg 0x287 = REG_TX_CP_OVERRANGE_VCO_LOCK. TX equivalent.
	 * Same bit layout as the RX register above. */
	int32_t tx_cp = ad9361_spi_read(phy->spi, 0x287);
	if (tx_cp >= 0) {
		unsigned v = (unsigned)(tx_cp & 0xFF);
		neorv32_uart0_printf("  tx_cp_vco (0x287=0x%x):"
				     " tx_vco_lock=%u cp_ovrg_low=%u cp_ovrg_high=%u\n",
				     v,
				     (v >> 1) & 1, (v >> 6) & 1, (v >> 7) & 1);
	}

	/* RX gain readback: the active gain set by AGC or manual control.
	 * If gain has been pulled to minimum by AGC overload, signal collapses
	 * to noise. ad9361_get_rx_rf_gain(phy, ch, &gain_db) returns dB. */
	int32_t rx_gain = 0;
	int32_t rc = ad9361_get_rx_rf_gain(phy, 0, &rx_gain);
	if (rc == 0) {
		neorv32_uart0_printf("  rx1_rf_gain = %d dB%s\n",
				     (int)rx_gain,
				     (rx_gain <= 0) ? " (very low — possible AGC collapse or no signal)" : "");
	} else {
		neorv32_uart0_printf("  rx1_rf_gain: ad9361_get_rx_rf_gain ret=%d\n", (int)rc);
	}

	/* RX RSSI: actual measured signal power at RX baseband. Directly
	 * answers "is there a signal arriving at the antenna?".
	 * - Floor (~-95 dBm) with TX active loopback = RF chain broken
	 * - Non-floor reading = signal is arriving; if snapshots are still
	 *   zero, the issue is digital-side downstream of the chip. */
	struct rf_rssi rssi = {0};
	rssi.ant = 0;  /* channel 0 */
	rc = ad9361_get_rx_rssi(phy, 0, &rssi);
	if (rc == 0) {
		/* rssi.symbol is in tenths of dB (i.e. value 750 => 75.0 dB attenuation
		 * below max => RX power ~ rssi_offset - 75 dBm). The exact
		 * absolute calibration depends on the gain table; the relative
		 * value is the useful diagnostic. */
		neorv32_uart0_printf("  rx1_rssi: symbol=%u preamble=%u multiplier=%u duration=%u\n",
				     (unsigned)rssi.symbol, (unsigned)rssi.preamble,
				     (unsigned)rssi.multiplier, (unsigned)rssi.duration);
	} else {
		neorv32_uart0_printf("  rx1_rssi: ad9361_get_rx_rssi ret=%d\n", (int)rc);
	}

	/* Sampling frequency readback (chip's own view of the clock rate).
	 * If this disagrees with the FPGA-side l_clk_hz the diag reports
	 * from get_adc_status, clock chain misconfig is likely. */
	uint32_t rx_samp = 0, tx_samp = 0;
	if (ad9361_get_rx_sampling_freq(phy, &rx_samp) == 0)
		neorv32_uart0_printf("  rx_sampling_freq = %u Hz\n", (unsigned)rx_samp);
	if (ad9361_get_tx_sampling_freq(phy, &tx_samp) == 0)
		neorv32_uart0_printf("  tx_sampling_freq = %u Hz\n", (unsigned)tx_samp);
}

/* ---------------------------------------------------------------
 *  diag_dig_tune_one_step
 *
 *  Mirrors what no-OS dig_tune does for one (clock_delay, data_delay)
 *  tap setting, but with full visibility into what each register reads.
 *
 *  W1C SUBTLETY: status bits at 0x404+ch*0x40 are set-priority W1C
 *  (up_adc_channel.v lines 288-296). If the comparator asserts
 *  pn_oos_s every cycle, our clear-write loses to the set-path and
 *  the bit stays at 1. So a "post-clear pn_oos=1" reading does NOT
 *  prove the clear worked or didn't -- it could be either:
 *    (a) clear took, comparator INSTANTLY re-set the bit because
 *        samples are flowing and pattern doesn't match -> samples flow
 *    (b) clear didn't take, no samples flowing -> samples don't flow
 *  To disambiguate we ALSO run the same sequence with BIST DISABLED
 *  -- if the bit stays at 1 even with BIST disabled, samples are
 *  flowing in normal RX too (the comparator runs whenever adc_valid
 *  pulses, regardless of BIST mode). If the bit clears without
 *  BIST but doesn't with BIST, samples flow only with BIST.
 *
 *  Also samples bridge RX_CNT before/during/after to see if the
 *  bridge sees any data.
 * --------------------------------------------------------------- */
/* Helper: print a CHAN_STATUS reading line.
 * NEORV32 printf doesn't support width specifiers (e.g. %-12s, %5d) --
 * those silently consume args incorrectly and shift everything. Stick to
 * plain %s, %x, %u, %d in this file. */
static void diag_print_chan_status(const char *tag, uint32_t cstat0, uint32_t cstat1)
{
	neorv32_uart0_printf("[diag] %s ch0_I=0x%x (or=%u oos=%u err=%u)  ch0_Q=0x%x (or=%u oos=%u err=%u)\n",
			     tag,
			     (unsigned)cstat0,
			     (unsigned)(cstat0 & 0x1),
			     (unsigned)((cstat0 >> 1) & 0x1),
			     (unsigned)((cstat0 >> 2) & 0x1),
			     (unsigned)cstat1,
			     (unsigned)(cstat1 & 0x1),
			     (unsigned)((cstat1 >> 1) & 0x1),
			     (unsigned)((cstat1 >> 2) & 0x1));
}

/* Helper: clear, immediate-read, multi-wait reads. The IMMEDIATE read
 * tells us about W1C behavior; the multi-wait reads tell us how fast
 * the comparator re-sets the bit (= proxy for sample rate). */
static void diag_clear_and_observe(const char *label)
{
	uint32_t c0, c1;

	AD9361_REG(0x0404)            = 0x6;
	AD9361_REG(0x0404 + 1 * 0x40) = 0x6;

	c0 = AD9361_REG(0x0404);
	c1 = AD9361_REG(0x0404 + 1 * 0x40);
	neorv32_uart0_printf("[diag] (%s) cleared CHAN_STATUS\n", label);
	diag_print_chan_status("IMMEDIATE", c0, c1);

	static const int wait_us_steps[] = {10, 100, 1000, 4000};
	for (size_t i = 0; i < sizeof(wait_us_steps)/sizeof(wait_us_steps[0]); i++) {
		int us = wait_us_steps[i];
		no_os_udelay(us);
		c0 = AD9361_REG(0x0404);
		c1 = AD9361_REG(0x0404 + 1 * 0x40);
		neorv32_uart0_printf("[diag] +%uus  ch0_I=0x%x ch0_Q=0x%x\n",
				     (unsigned)us, (unsigned)c0, (unsigned)c1);
	}
}

/* CLEAR-WAIT-READ probe of pn_oos sticky bit. Distinguishes "adc_valid
 * pulsed at least once" from "adc_valid pulses continuously". Each iteration
 * clears CHAN_STATUS, waits, and reads. If pn_oos comes back, comparator ran
 * during the wait — proves an adc_valid edge occurred in that window.
 *
 * Run this with no other RX activity. Bridge state should be RECEIVE.
 */
static void diag_get_valid_rate(void)
{
	const int N_TRIALS  = 200;
	const int WAIT_US   = 10;   /* at 30.72 MSPS, 10us = ~300 sample periods */
	int set_count_i0 = 0, set_count_q0 = 0;

	for (int i = 0; i < N_TRIALS; i++) {
		AD9361_REG(0x0404)            = 0x6;  /* W1C clear pn_oos+pn_err on ch0_I */
		AD9361_REG(0x0404 + 1 * 0x40) = 0x6;  /* W1C clear pn_oos+pn_err on ch0_Q */

		no_os_udelay(WAIT_US);

		uint32_t c0 = AD9361_REG(0x0404);
		uint32_t c1 = AD9361_REG(0x0404 + 1 * 0x40);
		if ((c0 >> 1) & 0x1) set_count_i0++;
		if ((c1 >> 1) & 0x1) set_count_q0++;
	}

	neorv32_uart0_printf("[valid_rate] %d trials, %dus wait each:\n",
			     N_TRIALS, WAIT_US);
	neorv32_uart0_printf("  ch0_I pn_oos re-set %d/%d times (%d%%)\n",
			     set_count_i0, N_TRIALS,
			     (set_count_i0 * 100) / N_TRIALS);
	neorv32_uart0_printf("  ch0_Q pn_oos re-set %d/%d times (%d%%)\n",
			     set_count_q0, N_TRIALS,
			     (set_count_q0 * 100) / N_TRIALS);
	neorv32_uart0_puts(
	    "  100% => adc_valid pulses continuously (gap is downstream of axi_ad9361)\n"
	    "    0% => adc_valid never pulses (chip/LVDS not delivering samples)\n"
	    "  mid% => bursty/intermittent valid (chip stalled or framing flaky)\n");
}

/* Rapid sampler for CHAN_DATA on ch0_I and ch0_Q.
 *
 * Reads both per-channel data registers n times in a tight loop, tracks
 * min/max as signed 16-bit, and records the first 3 distinct values
 * seen on each channel.
 *
 * Interpretation:
 *   min == max == 0  -> the IP's per-channel data register is stuck at 0.
 *                       With BIST PRBS active, that means PRBS bits are
 *                       not reaching the capture register even though
 *                       adc_valid pulses (= no LVDS data lanes delivering).
 *   varying values   -> IP capture works; downstream of the deserializer
 *                       is fine. dig_tune failure is then about pattern
 *                       matching (PN polarity, lane swap/invert), not
 *                       about data getting through.
 *
 * With dfmt_se=1 in CHAN_CNTRL (current ctrl=0x051), data is sign-extended
 * 12-bit signed in the low 16 bits, so int16_t cast is the right read.
 */
static void diag_data_sampler(const char *label, int n_samples)
{
	int16_t min_i =  32767, max_i = -32768;
	int16_t min_q =  32767, max_q = -32768;
	int16_t seen_i[3] = {0, 0, 0}; int n_seen_i = 0;
	int16_t seen_q[3] = {0, 0, 0}; int n_seen_q = 0;

	for (int i = 0; i < n_samples; i++) {
		int16_t vi = (int16_t)(AD9361_REG(0x0408) & 0xFFFF);
		int16_t vq = (int16_t)(AD9361_REG(0x0448) & 0xFFFF);

		if (vi < min_i) min_i = vi;
		if (vi > max_i) max_i = vi;
		if (vq < min_q) min_q = vq;
		if (vq > max_q) max_q = vq;

		if (n_seen_i < 3) {
			int dup = 0;
			for (int j = 0; j < n_seen_i; j++) if (seen_i[j] == vi) dup = 1;
			if (!dup) seen_i[n_seen_i++] = vi;
		}
		if (n_seen_q < 3) {
			int dup = 0;
			for (int j = 0; j < n_seen_q; j++) if (seen_q[j] == vq) dup = 1;
			if (!dup) seen_q[n_seen_q++] = vq;
		}
	}

	neorv32_uart0_printf("[data_sample] %s ch0_I: min=%d max=%d first3=[%d,%d,%d]\n",
			     label, (int)min_i, (int)max_i,
			     (int)seen_i[0], (int)seen_i[1], (int)seen_i[2]);
	neorv32_uart0_printf("[data_sample] %s ch0_Q: min=%d max=%d first3=[%d,%d,%d]\n",
			     label, (int)min_q, (int)max_q,
			     (int)seen_q[0], (int)seen_q[1], (int)seen_q[2]);
}

/* Helper: print bridge RX_CNT */
static void diag_print_rx_cnt(const char *tag)
{
	uint32_t cnt = BRIDGE_REG(BRIDGE_REG_STATUS_RX_COUNT);
	uint32_t st  = BRIDGE_REG(BRIDGE_REG_STATUS_STATE);
	neorv32_uart0_printf("[diag] %s bridge RX_CNT=%u STATE=%u\n",
			     tag, (unsigned)cnt, (unsigned)st);
}

static void diag_dig_tune_one_step(struct ad9361_rf_phy *phy,
				   uint32_t clock_delay,
				   uint32_t data_delay)
{
	if (!phy || !phy->spi) {
		neorv32_uart0_puts("[diag] phy/spi null - skipping\n");
		return;
	}

	uint32_t chip_delay_reg = (data_delay & 0xF) | ((clock_delay & 0xF) << 4);
	int32_t spi_ret;
	uint32_t common_status, cstat0, cstat1;

	neorv32_uart0_printf("\n[diag] === dig_tune comprehensive: clock_delay=%u data_delay=%u ===\n",
			     (unsigned)clock_delay, (unsigned)data_delay);

	/* Set chip RX delay (chip 0x006) */
	spi_ret = ad9361_spi_write(phy->spi, 0x006, chip_delay_reg);
	int32_t rb = ad9361_spi_read(phy->spi, 0x006);
	neorv32_uart0_printf("[diag] chip 0x006 <- 0x%x readback=0x%x ret=%d\n",
			     (unsigned)chip_delay_reg, (unsigned)(rb & 0xFF), (int)spi_ret);

	/* === PHASE 1: BIST DISABLED (control test) ===
	 * If pn_oos re-sets even without BIST, the comparator IS running which
	 * means adc_valid IS pulsing which means samples ARE flowing into the IP. */
	neorv32_uart0_puts("\n[diag] --- PHASE 1: BIST DISABLED (real RX) ---\n");
	ad9361_bist_prbs(phy, BIST_DISABLE);
	int32_t bistrb = ad9361_spi_read(phy->spi, 0x3F4);
	neorv32_uart0_printf("[diag] chip 0x3F4 BIST_CONFIG = 0x%x\n", (unsigned)(bistrb & 0xFF));

	common_status = AD9361_REG(0x005C);
	neorv32_uart0_printf("[diag] common ADC_STATUS=0x%x link_ok=%u\n",
			     (unsigned)common_status, (unsigned)(common_status & 1));
	cstat0 = AD9361_REG(0x0404);
	cstat1 = AD9361_REG(0x0404 + 1 * 0x40);
	diag_print_chan_status("BEFORE", cstat0, cstat1);
	diag_print_rx_cnt("PHASE1 PRE");
	diag_clear_and_observe("BIST_OFF");
	diag_print_rx_cnt("PHASE1 POST");
	neorv32_uart0_puts("[diag] PHASE1 valid-pulse rate (BIST off, real RX path):\n");
	diag_get_valid_rate();
	diag_data_sampler("PHASE1_BIST_OFF", 100);

	/* === PHASE 2: BIST ENABLED (PRBS injection at RX BB) === */
	neorv32_uart0_puts("\n[diag] --- PHASE 2: BIST ENABLED (PRBS_INJ_RX) ---\n");
	spi_ret = ad9361_bist_prbs(phy, BIST_INJ_RX);
	bistrb = ad9361_spi_read(phy->spi, 0x3F4);
	neorv32_uart0_printf("[diag] chip 0x3F4 BIST_CONFIG = 0x%x  (bit0=en, bits3:2=ctrl_point) ret=%d\n",
			     (unsigned)(bistrb & 0xFF), (int)spi_ret);

	common_status = AD9361_REG(0x005C);
	neorv32_uart0_printf("[diag] common ADC_STATUS=0x%x link_ok=%u\n",
			     (unsigned)common_status, (unsigned)(common_status & 1));
	cstat0 = AD9361_REG(0x0404);
	cstat1 = AD9361_REG(0x0404 + 1 * 0x40);
	diag_print_chan_status("BEFORE", cstat0, cstat1);
	diag_print_rx_cnt("PHASE2 PRE");
	diag_clear_and_observe("BIST_ON");
	diag_print_rx_cnt("PHASE2 POST");
	neorv32_uart0_puts("[diag] PHASE2 valid-pulse rate (BIST PRBS_INJ_RX active):\n");
	diag_get_valid_rate();
	diag_data_sampler("PHASE2_BIST_ON", 100);

	/* === PHASE 3: Try pnseq_sel=9 (CUSTOM, uses pn1fn 24-bit standard PN9) === */
	neorv32_uart0_puts("\n[diag] --- PHASE 3: BIST ON + pnseq_sel=9 (pn1fn standard PN9) ---\n");
	/* CHAN_CNTRL_3 at 0x418+ch*0x40, PN_SEL field is bits 19:16 */
	AD9361_REG(0x0418)            = (9u << 16);
	AD9361_REG(0x0418 + 1 * 0x40) = (9u << 16);
	neorv32_uart0_printf("[diag] wrote CHAN_CNTRL_3 = 0x%x  (pn_sel=9 -> pn1fn standard PN9)\n",
			     (unsigned)(9u << 16));
	diag_clear_and_observe("BIST_ON_PN9");
	diag_print_rx_cnt("PHASE3 POST");

	/* Restore: pn_sel=0 (default device-specific pn0fn) */
	AD9361_REG(0x0418)            = 0;
	AD9361_REG(0x0418 + 1 * 0x40) = 0;

	/* Disable BIST so we don't leave the chip in test mode */
	ad9361_bist_prbs(phy, BIST_DISABLE);

	neorv32_uart0_puts("\n[diag] === end ===\n\n");
}

/* Chip-side TX-BB -> RX-BB internal loopback test.
 *
 * Tests whether the chip's RX LVDS output port is functional at all by
 * routing FPGA DAC data through the chip's internal loopback and back out
 * the chip's RX LVDS port to the FPGA.
 *
 * Round trip:
 *   FPGA DAC PN9 source -> FPGA DAC channels -> TX LVDS pins ->
 *   chip TX LVDS receiver -> chip TX BB -> [internal loopback] ->
 *   chip RX BB -> chip RX LVDS driver -> FPGA RX LVDS pins -> IDDRE1 ->
 *   FPGA RX CHAN_DATA register
 *
 * Result interpretation:
 *   varying data  -> FPGA RX LVDS receive path is healthy. The previous
 *                    BIST_INJ_RX result (data=0) was failing because chip-
 *                    side BIST PRBS injection at RX BB specifically isn't
 *                    reaching the LVDS output. Narrows the hunt to chip-
 *                    side BIST config / RX BB chain.
 *   still all 0   -> FPGA RX LVDS path is broken regardless of what the
 *                    chip drives. Narrows the hunt to FPGA-side IBUFDS /
 *                    termination / signal integrity on the 6 RX data lanes.
 *
 * Uses the IP's built-in PN9 source on the DAC channels (CHAN_CNTRL_7 = 9),
 * matching the pattern used by ad9361_dig_tune_tx in ad9361_conv.c.
 */
static void diag_chip_loopback_test(struct ad9361_rf_phy *phy)
{
	if (!phy || !phy->spi) {
		neorv32_uart0_puts("[chip_lb] phy/spi null - skipping\n");
		return;
	}

	neorv32_uart0_puts("\n[diag] === Chip TX-BB -> RX-BB internal loopback test ===\n");

	/* Save DAC chan_cntrl_6 (0x4414) and chan_cntrl_7 (0x4418) for all 4
	 * channels (matches dig_tune_tx pattern even though 1R1T uses only ch0). */
	uint32_t saved_cc6[4], saved_cc7[4];
	for (int ch = 0; ch < 4; ch++) {
		saved_cc6[ch] = AD9361_REG(0x4414 + ch * 0x40);
		saved_cc7[ch] = AD9361_REG(0x4418 + ch * 0x40);
	}

	/* Enable chip TX-BB -> RX-BB internal loopback */
	int32_t rc = ad9361_bist_loopback(phy, 1);
	neorv32_uart0_printf("[chip_lb] ad9361_bist_loopback(1) ret=%d\n", (int)rc);

	/* Configure each DAC channel to source PN9 from IP's internal generator.
	 *   CHAN_CNTRL_7 = 9 : data source select = PN9
	 *   CHAN_CNTRL_6 = 0 : clear IQCOR_ENB so DAC sees PN9 unmodified */
	for (int ch = 0; ch < 4; ch++) {
		AD9361_REG(0x4418 + ch * 0x40) = 9;
		AD9361_REG(0x4414 + ch * 0x40) = 0;
	}
	/* Trigger dac_sync to commit the source-select change */
	AD9361_REG(0x4044) = 1;

	/* Wait for the loopback path to settle through chip BB filters */
	no_os_udelay(1000);

	/* Sample RX CHAN_DATA: should be varying PN9-derived values if RX LVDS
	 * receive path is functional. */
	neorv32_uart0_puts("[chip_lb] sampling RX CHAN_DATA with chip loopback + DAC PN9:\n");
	diag_data_sampler("CHIP_LOOPBACK", 100);

	/* Restore DAC channel control registers */
	for (int ch = 0; ch < 4; ch++) {
		AD9361_REG(0x4414 + ch * 0x40) = saved_cc6[ch];
		AD9361_REG(0x4418 + ch * 0x40) = saved_cc7[ch];
	}
	AD9361_REG(0x4044) = 1;

	/* Disable chip loopback */
	ad9361_bist_loopback(phy, 0);

	neorv32_uart0_puts("[diag] === end chip loopback test ===\n\n");
}

/* FMCOMMS2/4 default configuration (from no-os/projects/ad9361/src/main.c) */
AD9361_InitParam default_init_param = {
	/* Device selection */
	ID_AD9361,	// dev_sel
	/* Reference Clock */
	40000000UL,	// reference_clk_rate (FMCOMMS2/4 40 MHz XTAL)
	/* Base Configuration */
	0,		// two_rx_two_tx_mode_enable  (1R1T to retest dig_tune cleanly with R1 mode verified)
	1,		// one_rx_one_tx_mode_use_rx_num
	1,		// one_rx_one_tx_mode_use_tx_num
	1,		// frequency_division_duplex_mode_enable
	0,		// frequency_division_duplex_independent_mode_enable
	0,		// tdd_use_dual_synth_mode_enable
	0,		// tdd_skip_vco_cal_enable
	0,		// tx_fastlock_delay_ns
	0,		// rx_fastlock_delay_ns
	0,		// rx_fastlock_pincontrol_enable
	0,		// tx_fastlock_pincontrol_enable
	0,		// external_rx_lo_enable
	0,		// external_tx_lo_enable
	5,		// dc_offset_tracking_update_event_mask
	6,		// dc_offset_attenuation_high_range
	5,		// dc_offset_attenuation_low_range
	0x28,		// dc_offset_count_high_range
	0x32,		// dc_offset_count_low_range
	0,		// split_gain_table_mode_enable
	MAX_SYNTH_FREF,	// trx_synthesizer_target_fref_overwrite_hz
	0,		// qec_tracking_slow_mode_enable
	/* ENSM Control */
	0,		// ensm_enable_pin_pulse_mode_enable
	0,		// ensm_enable_txnrx_control_enable
	/* LO Control */
	2400000000UL,	// rx_synthesizer_frequency_hz
	2400000000UL,	// tx_synthesizer_frequency_hz
	1,		// tx_lo_powerdown_managed_enable
	/* Rate & BW Control */
	{983040000, 245760000, 122880000, 61440000, 30720000, 30720000},
	{983040000, 122880000, 122880000, 61440000, 30720000, 30720000},
	18000000,	// rf_rx_bandwidth_hz
	18000000,	// rf_tx_bandwidth_hz
	/* RF Port Control */
	0,		// rx_rf_port_input_select
	0,		// tx_rf_port_input_select
	/* TX Attenuation Control */
	0,		// tx_attenuation_mdB — max TX output power (compensates external 40 dB attenuator in loopback path)
	0,		// update_tx_gain_in_alert_enable
	/* Reference Clock Control */
	0,		// xo_disable_use_ext_refclk_enable
	{8, 5920},	// dcxo_coarse_and_fine_tune
	CLKOUT_DISABLE,	// clk_output_mode_select
	/* Gain Control */
	2,		// gc_rx1_mode
	2,		// gc_rx2_mode
	58,		// gc_adc_large_overload_thresh
	4,		// gc_adc_ovr_sample_size
	47,		// gc_adc_small_overload_thresh
	8192,		// gc_dec_pow_measurement_duration
	0,		// gc_dig_gain_enable
	800,		// gc_lmt_overload_high_thresh
	704,		// gc_lmt_overload_low_thresh
	24,		// gc_low_power_thresh
	15,		// gc_max_dig_gain
	0,		// gc_use_rx_fir_out_for_dec_pwr_meas_enable
	/* Gain MGC Control */
	2,		// mgc_dec_gain_step
	2,		// mgc_inc_gain_step
	0,		// mgc_rx1_ctrl_inp_enable
	0,		// mgc_rx2_ctrl_inp_enable
	0,		// mgc_split_table_ctrl_inp_gain_mode
	/* Gain AGC Control */
	10,		// agc_adc_large_overload_exceed_counter
	2,		// agc_adc_large_overload_inc_steps
	0,		// agc_adc_lmt_small_overload_prevent_gain_inc_enable
	10,		// agc_adc_small_overload_exceed_counter
	4,		// agc_dig_gain_step_size
	3,		// agc_dig_saturation_exceed_counter
	1000,		// agc_gain_update_interval_us
	0,		// agc_immed_gain_change_if_large_adc_overload_enable
	0,		// agc_immed_gain_change_if_large_lmt_overload_enable
	10,		// agc_inner_thresh_high
	1,		// agc_inner_thresh_high_dec_steps
	12,		// agc_inner_thresh_low
	1,		// agc_inner_thresh_low_inc_steps
	10,		// agc_lmt_overload_large_exceed_counter
	2,		// agc_lmt_overload_large_inc_steps
	10,		// agc_lmt_overload_small_exceed_counter
	5,		// agc_outer_thresh_high
	2,		// agc_outer_thresh_high_dec_steps
	18,		// agc_outer_thresh_low
	2,		// agc_outer_thresh_low_inc_steps
	1,		// agc_attack_delay_extra_margin_us
	0,		// agc_sync_for_gain_counter_enable
	/* Fast AGC */
	64,		// fagc_dec_pow_measuremnt_duration
	260,		// fagc_state_wait_time_ns
	/* Fast AGC - Low Power */
	0,		// fagc_allow_agc_gain_increase
	5,		// fagc_lp_thresh_increment_time
	1,		// fagc_lp_thresh_increment_steps
	/* Fast AGC - Lock Level */
	1,		// fagc_lock_level_lmt_gain_increase_en
	5,		// fagc_lock_level_gain_increase_upper_limit
	/* Fast AGC - Peak Detectors and Final Settling */
	1,		// fagc_lpf_final_settling_steps
	1,		// fagc_lmt_final_settling_steps
	3,		// fagc_final_overrange_count
	/* Fast AGC - Final Power Test */
	0,		// fagc_gain_increase_after_gain_lock_en
	/* Fast AGC - Unlocking the Gain */
	0,		// fagc_gain_index_type_after_exit_rx_mode
	1,		// fagc_use_last_lock_level_for_set_gain_en
	1,		// fagc_rst_gla_stronger_sig_thresh_exceeded_en
	5,		// fagc_optimized_gain_offset
	10,		// fagc_rst_gla_stronger_sig_thresh_above_ll
	1,		// fagc_rst_gla_engergy_lost_sig_thresh_exceeded_en
	1,		// fagc_rst_gla_engergy_lost_goto_optim_gain_en
	10,		// fagc_rst_gla_engergy_lost_sig_thresh_below_ll
	8,		// fagc_energy_lost_stronger_sig_gain_lock_exit_cnt
	1,		// fagc_rst_gla_large_adc_overload_en
	1,		// fagc_rst_gla_large_lmt_overload_en
	0,		// fagc_rst_gla_en_agc_pulled_high_en
	0,		// fagc_rst_gla_if_en_agc_pulled_high_mode
	64,		// fagc_power_measurement_duration_in_state5
	2,		// fagc_large_overload_inc_steps
	/* RSSI Control */
	1,		// rssi_delay
	1000,		// rssi_duration
	3,		// rssi_restart_mode
	0,		// rssi_unit_is_rx_samples_enable
	1,		// rssi_wait
	/* Aux ADC Control */
	256,		// aux_adc_decimation
	40000000UL,	// aux_adc_rate
	/* AuxDAC Control */
	1,		// aux_dac_manual_mode_enable
	0,		// aux_dac1_default_value_mV
	0,		// aux_dac1_active_in_rx_enable
	0,		// aux_dac1_active_in_tx_enable
	0,		// aux_dac1_active_in_alert_enable
	0,		// aux_dac1_rx_delay_us
	0,		// aux_dac1_tx_delay_us
	0,		// aux_dac2_default_value_mV
	0,		// aux_dac2_active_in_rx_enable
	0,		// aux_dac2_active_in_tx_enable
	0,		// aux_dac2_active_in_alert_enable
	0,		// aux_dac2_rx_delay_us
	0,		// aux_dac2_tx_delay_us
	/* Temperature Sensor Control */
	256,		// temp_sense_decimation
	1000,		// temp_sense_measurement_interval_ms
	0xCE,		// temp_sense_offset_signed
	1,		// temp_sense_periodic_measurement_enable
	/* Control Out Setup */
	0xFF,		// ctrl_outs_enable_mask
	0,		// ctrl_outs_index
	/* External LNA Control */
	0,		// elna_settling_delay_ns
	0,		// elna_gain_mdB
	0,		// elna_bypass_loss_mdB
	0,		// elna_rx1_gpo0_control_enable
	0,		// elna_rx2_gpo1_control_enable
	0,		// elna_gaintable_all_index_enable
	/* Digital Interface Control */
	2,		// digital_interface_tune_skip_mode  (init skips dig_tune; an
				// explicit RX dig_tune runs post-init (step 6.7) and on
				// power_up, and passes on the axau15. diag_dig_tune_one_step()
				// remains available after init to instrument check_pn
				// (link_ok vs PN errors) if LVDS capture ever needs debugging.)
	0,		// digital_interface_tune_fir_disable
	1,		// pp_tx_swap_enable
	1,		// pp_rx_swap_enable
	0,		// tx_channel_swap_enable
	0,		// rx_channel_swap_enable
	1,		// rx_frame_pulse_mode_enable  (PULSE mode = ADI reference 0x010=0xC8).
				//   ILA showed RX_FRAME stuck HIGH (i_rx_frame D0/D1) while data lanes
				//   toggle: that is the LEVEL-mode signature. axi_ad9361_lvds_if.v
				//   delineates on a frame TRANSITION (1R1T case 5'b10011 needs
				//   rx_frame 11->00 each l_clk); a static-high frame falls through to
				//   default => adc_valid=0, adc_data=0x0000. Pulse mode toggles the
				//   frame so the deserializer can latch samples.
	0,		// two_t_two_r_timing_enable    (back to ADI reference default)
	0,		// invert_data_bus_enable
	0,		// invert_data_clk_enable
	0,		// fdd_alt_word_order_enable
	0,		// invert_rx_frame_enable
	0,		// fdd_rx_rate_2tx_enable
	0,		// swap_ports_enable
	0,		// single_data_rate_enable
	1,		// lvds_mode_enable
	0,		// half_duplex_mode_enable
	0,		// single_port_mode_enable
	0,		// full_port_enable
	0,		// full_duplex_swap_bits_enable
	0,		// delay_rx_data
	0,		// rx_data_clock_delay
	4,		// rx_data_delay
	7,		// tx_fb_clock_delay
	0,		// tx_data_delay
	150,		// lvds_bias_mV
	1,		// lvds_rx_onchip_termination_enable
	0,		// rx1rx2_phase_inversion_en
	0xFF,		// lvds_invert1_control
	0x0F,		// lvds_invert2_control
	/* GPO Control */
	0,		// gpo_manual_mode_enable
	0,		// gpo_manual_mode_enable_mask
	0,		// gpo0_inactive_state_high_enable
	0,		// gpo1_inactive_state_high_enable
	0,		// gpo2_inactive_state_high_enable
	0,		// gpo3_inactive_state_high_enable
	0,		// gpo0_slave_rx_enable
	0,		// gpo0_slave_tx_enable
	0,		// gpo1_slave_rx_enable
	0,		// gpo1_slave_tx_enable
	0,		// gpo2_slave_rx_enable
	0,		// gpo2_slave_tx_enable
	0,		// gpo3_slave_rx_enable
	0,		// gpo3_slave_tx_enable
	0,		// gpo0_rx_delay_us
	0,		// gpo0_tx_delay_us
	0,		// gpo1_rx_delay_us
	0,		// gpo1_tx_delay_us
	0,		// gpo2_rx_delay_us
	0,		// gpo2_tx_delay_us
	0,		// gpo3_rx_delay_us
	0,		// gpo3_tx_delay_us
	/* Tx Monitor Control */
	37000,		// low_high_gain_threshold_mdB
	0,		// low_gain_dB
	24,		// high_gain_dB
	0,		// tx_mon_track_en
	0,		// one_shot_mode_en
	511,		// tx_mon_delay
	8192,		// tx_mon_duration
	2,		// tx1_mon_front_end_gain
	2,		// tx2_mon_front_end_gain
	48,		// tx1_mon_lo_cm
	48,		// tx2_mon_lo_cm
	/* GPIO definitions */
	{
		.number = GPIO_RESET_PIN,
		.platform_ops = &neorv32_gpio_ops,
		.extra = NULL
	},		// gpio_resetb
	{
		.number = -1,
		.platform_ops = &neorv32_gpio_ops,
		.extra = NULL
	},		// gpio_sync (not used, single-chip)
	{
		.number = -1,
		.platform_ops = &neorv32_gpio_ops,
		.extra = NULL
	},		// gpio_cal_sw1
	{
		.number = -1,
		.platform_ops = &neorv32_gpio_ops,
		.extra = NULL
	},		// gpio_cal_sw2
	/* SPI */
	{
		.device_id = SPI_DEVICE_ID,
		.mode = NO_OS_SPI_MODE_1,
		.chip_select = SPI_CS,
		.max_speed_hz = 2500000,
		.platform_ops = &neorv32_spi_ops,
		.extra = NULL
	},
	/* External LO clocks */
	NULL,		// ad9361_rfpll_ext_recalc_rate
	NULL,		// ad9361_rfpll_ext_round_rate
	NULL,		// ad9361_rfpll_ext_set_rate
	&rx_adc_init,	// rx_adc_init
	&tx_dac_init,	// tx_dac_init
};

int main(void)
{
	struct ad9361_rf_phy *phy = NULL;
	uint32_t ensm_mode;
	uint64_t rx_lo, tx_lo;
	int32_t ret;

	/* 1. NEORV32 runtime + exception handlers */
	neorv32_rte_setup();

	/* 2. Check required peripherals */
	if (!neorv32_uart0_available()) return 1;
	if (!neorv32_gpio_available())  return 1;
	if (!neorv32_spi_available())   return 1;

	/* 3. Init UART */
	neorv32_uart0_setup(BAUD_RATE, 0);
	neorv32_uart0_puts("\n[ad9361_no-os] NEORV32 + AD9361 driver starting...\n");

	/* 4. Init AD9361 via SPI (full calibration sequence) */
	neorv32_uart0_puts("[ad9361_no-os] Calling ad9361_init()...\n");
	ret = ad9361_init(&phy, &default_init_param);
	if (ret) {
		neorv32_uart0_printf("[ad9361_no-os] ad9361_init FAILED: %d\n", (int)ret);
		goto halt;
	}
	neorv32_uart0_puts("[ad9361_no-os] ad9361_init OK\n");

	/* 5. Enable FDD mode */
	ret = ad9361_set_en_state_machine_mode(phy, ENSM_MODE_FDD);
	if (ret) {
		neorv32_uart0_printf("[ad9361_no-os] ENSM FDD FAILED: %d\n", (int)ret);
		goto halt;
	}
	neorv32_uart0_puts("[ad9361_no-os] ENSM -> FDD\n");

	/* 6. axi_ad9361 FPGA core: per-channel CTRL writes, R1/R2 mode, sync,
	 * reset release, AND LVDS IDELAY calibration (dig_tune) are now all
	 * handled by ad9361_init() -> ad9361_post_setup() upstream, since we
	 * now compile in cf_axi_adc / cf_axi_dac (see makefile note).
	 * The previous hand-rolled register-poke block was removed because
	 * post_setup overwrites those same registers, AND because the manual
	 * block had no calibration step — leaving IDELAYs at the IP default,
	 * with header_s=0 across all RX channels and snapshots reading 0. */
	neorv32_uart0_puts("[ad9361_no-os] axi_ad9361 FPGA core configured by ad9361_post_setup() incl. dig_tune\n");

	/* 6.5. Release axi_ad9361 IP resets explicitly.
	 *
	 * The ADC reset (0x0040) is rescued by accident: at the end of
	 * ad9361_dig_tune() (ad9361_conv.c:579-580) there's a kick sequence
	 *   axi_adc_write(rx_adc, AXI_ADC_REG_RSTN, AXI_ADC_MMCM_RSTN);
	 *   axi_adc_write(rx_adc, AXI_ADC_REG_RSTN, AXI_ADC_RSTN | AXI_ADC_MMCM_RSTN);
	 * which restarts the ADC MMCM and releases the core reset. Even with
	 * skip_mode=2 the cleanup tail still runs, so 0x0040 typically reads 0x3
	 * after init. But there's no equivalent for the DAC anywhere in the
	 * no-OS code path we use -- axi_dac_init() would have done it but we
	 * don't call that. Without an explicit write, 0x4040 stays at 0 and the
	 * DAC half of the IP is frozen, so TX never reaches the AD9361 chip
	 * (-> no signal in the loopback -> RX sees noise -> no constellation).
	 *
	 * Write both defensively so we don't depend on dig_tune side effects. */
	AD9361_REG(0x0040) = 0x3;        /* ADC: resetn + mmcm_resetn released */
	AD9361_REG(0x4040) = 0x3;        /* DAC: resetn + mmcm_resetn released */

	/* 6.55. Clear IQCOR_ENB (bit 9) on the per-channel CTRL registers.
	 *
	 * ad9361_post_setup() leaves IQCOR_ENB set on every channel (ctrl=0x251)
	 * but does NOT program iqcor_coeff_1 / iqcor_coeff_2 in our boot path.
	 * The IP's ad_iqcor block then computes:
	 *     data_out = coeff_1 * I + coeff_2 * Q  =  0 * I + 0 * Q  =  0
	 * which silently zeros every captured sample (constellation collapses
	 * to the origin). With IQCOR_ENB cleared, ad_iqcor passes I (or Q)
	 * through unchanged.
	 *
	 * The matching loopback firmware in deps/neorv32/sw/ad9361_loopback
	 * writes ctrl=0x051 (no IQCOR_ENB) and is verified working in the
	 * Section 5.6 Questa simulation. Clearing the bit here brings the IP
	 * register state in line with that proven configuration.
	 *
	 * Bit positions in CHAN_CNTRL (per ADI axi_ad9361 spec):
	 *   [0] enable       [4] dfmt_enable    [6] dfmt_se   [9] iqcor_enb
	 * So 0x251 -> 0x051 clears bit 9 only, preserving enable + format. */
	AD9361_REG(0x0400) &= ~(1u << 9);  /* ch0_I */
	AD9361_REG(0x0440) &= ~(1u << 9);  /* ch0_Q */
	AD9361_REG(0x0480) &= ~(1u << 9);  /* ch1_I (unused in 1R1T but keep symmetric) */
	AD9361_REG(0x04C0) &= ~(1u << 9);  /* ch1_Q */

	/* 6.57. Select the DAC channel data source = DMA (external/streamed input).
	 *
	 * The ADI DAC datapath only asserts dac_enable_* to the external source
	 * (our axi_ad9361_adapter) when a channel's data_sel = DMA. The adapter
	 * gates its output on that signal (dac_data = dac_enable ? tx : 0), so until
	 * data_sel is set the IP holds dac_enable LOW and the adapter emits zero --
	 * TX never carries the QPSK samples and the loopback collapses to the
	 * origin. Default after DAC reset is DDS/zero; axi_dac_init() would set
	 * this, but we don't call it. CHAN_CNTRL_7[3:0] = data_sel (DMA = 2).
	 * Mirrors axi_dac_set_datasel(): write each channel, then pulse SYNC. */
	AD9361_REG(0x4418 + 0 * 0x40) = AXI_DAC_DATA_SEL_DMA;  /* DAC ch0 = TX1 I */
	AD9361_REG(0x4418 + 1 * 0x40) = AXI_DAC_DATA_SEL_DMA;  /* DAC ch1 = TX1 Q */
	AD9361_REG(0x4044) = 0x1;        /* DAC SYNC_CONTROL: latch data-source change */

	/* 6.6. dig_tune diagnostic: probe what dig_tune's check_pn would see.
	 * Tests one (clock_delay, data_delay) tap at the middle of range with
	 * BIST PRBS injection enabled. Output distinguishes failure mode A
	 * (link drops with BIST on) from failure mode B (link OK but PN errors
	 * latched -- pattern or sample-phase mismatch). */
	diag_dig_tune_one_step(phy, 8, 8);

	/* 6.65. Chip TX-BB -> RX-BB internal loopback test.
	 *
	 * Independent yes/no test on whether the FPGA-side RX LVDS receive path
	 * works at all. Drives FPGA DAC channels with PN9 -> goes out TX LVDS ->
	 * loops inside the chip from TX BB back to RX BB -> comes back out RX
	 * LVDS -> arrives at FPGA RX CHAN_DATA register.
	 *
	 * If CHAN_DATA shows varying values, FPGA RX LVDS is fine and the data=0
	 * we see with BIST_INJ_RX is a chip-side BIST PRBS path issue. If CHAN_DATA
	 * is still all zero, FPGA-side IBUFDS / termination / signal integrity on
	 * the 6 RX data lanes is the suspect.
	 */
	diag_chip_loopback_test(phy);

	/* 6.7. Full ad9361_dig_tune() RX sweep with verbose output.
	 *
	 * Init still has digital_interface_tune_skip_mode=2 so init didn't run
	 * dig_tune; this is an explicit, post-init invocation we control.
	 *
	 * IMPORTANT: ad9361_dig_tune() itself checks phy->pdata->dig_interface_
	 * tune_skipmode at ad9361_conv.c:529 and short-circuits to the restore
	 * path (returns 0 without sweeping) if skipmode==2. So we must override
	 * skipmode here before the call, otherwise the call is a no-op and we
	 * get a vacuous "PASS" with no field grid printed.
	 *
	 * Override to 1 = "RX only" (skip TX dig_tune). TX dig_tune uses HDL
	 * loopback through the DAC, takes longer, and is uninformative until
	 * RX itself passes. Restore the original value afterward.
	 *
	 * The 2x16 (clock_delay x data_delay) field grid is printed via printk
	 * in ad9361_dig_tune_verbose_print(), which routes to UART because
	 * HAVE_VERBOSE_MESSAGES is defined in app_config.h.
	 *
	 * max_freq=0 -> sweep at current rate only (don't try 25/40/61.44 MHz).
	 * BE_MOREVERBOSE would print the 2x16 field grid, but that grid goes out
	 * via printk, which is silenced in this build (HAVE_DEBUG_MESSAGES off, to
	 * quiet boot spew). So the pass indicator is the RETURN CODE, not a grid.
	 *
	 * Verified PASS on the axau15 (boot spew): "ad9361_dig_tune returned 0".
	 * Corroborated in the same boot log by the diagnostics above/below:
	 *   - PHASE 2 (BIST PRBS_INJ_RX): pn_oos=0, 0/200 re-sets -> PN checker
	 *     locks to the injected PRBS (the mechanism dig_tune depends on);
	 *   - adc_status: "sw_taps_per_ui=4.89 (>3 = healthy)" -> IDELAYCTRL
	 *     locked, RX eye well-resolved;
	 *   - l_clk_hz ~= 61.44 MHz, bbpll_lock=1, rx_vco_lock=1, link_ok=1.
	 * This establishes the working RX IDELAY taps. The diag dumps stay on so
	 * any future LVDS-capture regression is visible in the boot log.
	 */
	uint8_t saved_skipmode = phy->pdata->dig_interface_tune_skipmode;
	phy->pdata->dig_interface_tune_skipmode = 1;  /* RX only, no TX */

	neorv32_uart0_puts("\n[ad9361_no-os] === Explicit ad9361_dig_tune(BE_MOREVERBOSE|DO_IDELAY), skipmode=1 (RX) ===\n");
	int32_t dt_ret = ad9361_dig_tune(phy, 0, BE_MOREVERBOSE | DO_IDELAY);
	neorv32_uart0_printf("[ad9361_no-os] ad9361_dig_tune returned %d (0=pass, <0=fail)\n",
			     (int)dt_ret);

	phy->pdata->dig_interface_tune_skipmode = saved_skipmode;

	/* 7. Start streaming adapter bridge and configure datapath */
	neorv32_uart0_puts("[ad9361_no-os] Configuring streaming adapter bridge...\n");

	/* Reset bridge to IDLE state (no-op if already IDLE) */
	bridge_reset();

	/* Load 1024 QPSK IQ samples into TX buffer */
	bridge_load_tx_data(qpsk_tx_samples, QPSK_TX_NUM_SAMPLES);

	/* Enable bridge: IDLE -> INIT -> SEND_AND_RECEIVE -> RECEIVE */
	if (!bridge_enable()) {
		neorv32_uart0_puts("[ad9361_no-os] Bridge enable TIMEOUT\n");
	}
	neorv32_uart0_printf("[ad9361_no-os] TX burst sent: %u samples\n",
			     (unsigned)QPSK_TX_NUM_SAMPLES);
	neorv32_uart0_puts("[ad9361_no-os] Bridge running (TX complete, RX capturing)\n");

	/* 8. Assert up_enable and up_txnrx (data path enable) */
	neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 1);
	neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 1);
	neorv32_uart0_puts("[ad9361_no-os] Data path enabled (up_enable=1, up_txnrx=1)\n");

	/* 9. Read back LO frequencies */
	ad9361_get_rx_lo_freq(phy, &rx_lo);
	ad9361_get_tx_lo_freq(phy, &tx_lo);
	neorv32_uart0_printf("[ad9361_no-os] RX LO: %u MHz, TX LO: %u MHz\n",
			     (unsigned)(rx_lo / 1000000ULL),
			     (unsigned)(tx_lo / 1000000ULL));

	/* 10. One-shot diagnostic dump (Phase 1 + Phase 2 RX-path) */
	neorv32_uart0_puts("\n[ad9361_no-os] === RX-path diagnostic dump (boot) ===\n");
	dump_adc_status();
	dump_dac_status();
	dump_chip_status(phy);
	neorv32_uart0_puts("[ad9361_no-os] === end diagnostic dump ===\n\n");

	/* 10b. Default operating mode: REAL RF PATH (external SMA cable).
	 *
	 * RF bring-up R1: the device no longer boots into the AD9361 internal
	 * baseband loopback (reg 0x3F5 DATA_PORT_LOOP_TEST_ENABLE). RX now listens
	 * to the SMA cable:  TX1A_OUT -> external 40-60 dB attenuator pad -> RX1A_IN.
	 * The samples therefore traverse DAC -> mixer -> RF -> mixer -> ADC and pick
	 * up real impairments (the constellation will smear/rotate until the R2 TX
	 * pulse shaping and R3 RX DSP are in place — that is expected).
	 *
	 * The internal BB loopback is still the digital reference / noise floor,
	 * one command away: `loopback_on` re-enables it, `loopback_off` returns
	 * here, and get_status reports LB: so you can tell which path is live.
	 *
	 * !!! HARDWARE: the external attenuator pad is MANDATORY. Driving full TX
	 *     power straight into RX1A_IN saturates / damages the RX front end. */
	ad9361_bist_prbs(phy, BIST_DISABLE);   /* no RX PRBS injection */
	ad9361_bist_loopback(phy, 0);          /* RF path: internal BB loopback OFF */

	/* RX gain: MANUAL (MGC) for a STABLE bring-up constellation. The init-param
	 * default is slow-attack AGC (gc_rx1_mode=2), which hunts and makes the
	 * cluster breathe while the link is being tuned. Switch RX1 to MGC and set
	 * a defined mid-table starting gain; tune on hardware from the RSSI / RX
	 * gain readback in get_chip_status. */
	ad9361_set_rx_gain_control_mode(phy, 0, RF_GAIN_MGC);
	ad9361_set_rx_rf_gain(phy, 0, 30);         /* dB — starting point, tune to taste */

	/* TX attenuation: defined starting point into the external pad. 10 dB keeps
	 * the DAC out of hard clip and leaves headroom for the RRC overshoot the R2
	 * waveform will add; with a 40-60 dB pad this still lands a usable level at
	 * RX. Tune against RSSI on hardware. (Init-param tx_attenuation_mdB=0 was
	 * max power, appropriate only for the now-retired internal-loopback path.) */
	ad9361_set_tx_attenuation(phy, 0, 10000);  /* mdB */

	neorv32_uart0_puts("[ad9361_no-os] Boot path: RF (SMA cable) — MGC rx_gain=30dB, tx_atten=10dB\n");
	neorv32_uart0_puts("[ad9361_no-os] !!! external 40-60 dB pad REQUIRED between TX1A_OUT and RX1A_IN\n");

	/* Snapshot the boot TX-quad correction (the chip cal result) so power_up can
	 * RESTORE it deterministically instead of re-running the drift-prone cal.
	 * ad9361_init() above ran the TX_QUAD cal to a good result (boot EVM ~2.5%). */
	for (int i = 0; i < 4; i++)
		tx_quad_corr_snap[i] = ad9361_spi_read(phy->spi, TX_QUAD_CORR_REG[i]) & 0xFF;
	tx_quad_corr_valid = 1;
	neorv32_uart0_printf("[ad9361_no-os] TX-quad corr boot snapshot: %02x %02x %02x %02x\n",
			     tx_quad_corr_snap[0], tx_quad_corr_snap[1],
			     tx_quad_corr_snap[2], tx_quad_corr_snap[3]);

	/* 11. UART command loop */
	neorv32_uart0_puts("[ad9361_no-os] Ready — awaiting commands\n");
	char cmd_buffer[CMD_BUFFER_SIZE];
	long cmd_arg;

	while (1) {
		int len = read_command(cmd_buffer, CMD_BUFFER_SIZE);
		if (len <= 0)
			continue;

		if (strcmp_cmd(cmd_buffer, CMD_ENABLE_RF)) {
			neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 1);
			neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 1);
			rf_enabled = 1;
			neorv32_uart0_puts(RESP_RF_ENABLED);

		} else if (strcmp_cmd(cmd_buffer, CMD_DISABLE_RF)) {
			neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 0);
			neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 0);
			rf_enabled = 0;
			neorv32_uart0_puts(RESP_RF_DISABLED);

		} else if (strcmp_cmd(cmd_buffer, CMD_ENABLE_SNAPSHOT)) {
			if (!power_state) { neorv32_uart0_puts("powered_down\n"); continue; }
			/* Wait for RX buffer to fill (1024 samples from ADC auto-drain) */
			if (!bridge_wait_rx_full()) {
				neorv32_uart0_puts("snapshot_timeout\n");
			} else {
				neorv32_uart0_puts(RESP_SNAPSHOT);
				send_rx_snapshot();
				/* Release RX buffer so adapter can capture next burst */
				bridge_release_rx();
			}

		} else if (strcmp_cmd(cmd_buffer, CMD_GET_STATUS)) {
			ad9361_get_en_state_machine_mode(phy, &ensm_mode);
			uint32_t bridge_state = BRIDGE_REG(BRIDGE_REG_STATUS_STATE);
			uint32_t tx_count = BRIDGE_REG(BRIDGE_REG_STATUS_TX_COUNT);
			uint32_t rx_count = BRIDGE_REG(BRIDGE_REG_STATUS_RX_COUNT);
			uint32_t gpio_status = neorv32_gpio_port_get() & 0xFF;
			neorv32_uart0_printf("ENSM:%s RF:%s PWR:%s LB:%d STATE:%u TX_CNT:%u RX_CNT:%u GPIO:0x%x\n",
					     (ensm_mode < 8) ? ensm_mode_str[ensm_mode] : "?",
					     rf_enabled ? "ON" : "OFF",
					     power_state ? "UP" : "DOWN",
					     (int)phy->bist_loopback_mode,
					     (unsigned)bridge_state,
					     (unsigned)tx_count,
					     (unsigned)rx_count,
					     (unsigned)gpio_status);

		} else if (strcmp_cmd(cmd_buffer, CMD_GET_ADC_STATUS)) {
			/* Allowed while powered down: pure fabric AXI reads in the
			 * always-on up domain (no chip SPI, no l_clk dependency;
			 * compute paths guard l_clk_hz==0). This is how the sleep
			 * state is OBSERVED: expect l_clk_pll_locked=0 and a
			 * free-running l_clk_hz on PolarFire, l_clk_hz=0 on Xilinx. */
			dump_adc_status();

		} else if (strcmp_cmd(cmd_buffer, CMD_GET_DAC_STATUS)) {
			/* Allowed while powered down: same fabric-only reads as
			 * get_adc_status. */
			dump_dac_status();

		} else if (strcmp_cmd(cmd_buffer, CMD_GET_VALID_RATE)) {
			if (!power_state) { neorv32_uart0_puts("powered_down\n"); continue; }
			diag_get_valid_rate();

		} else if (strcmp_cmd(cmd_buffer, CMD_GET_CHIP_STATUS)) {
			dump_chip_status(phy);

		} else if (strcmp_cmd(cmd_buffer, CMD_HOLD_BIST)) {
			/* Drive a continuous PRBS on the chip's RX digital interface
			 * (same BIST_INJ_RX as PHASE 2 of the boot diag) and LEAVE IT
			 * ON, so an armed ILA on the rx_data capture path has a
			 * deterministic toggling stimulus. stop_bist returns to real RX. */
			int32_t r = ad9361_bist_prbs(phy, BIST_INJ_RX);
			int32_t cfg = ad9361_spi_read(phy->spi, 0x3F4);
			neorv32_uart0_printf("bist_held BIST_CONFIG=0x%x ret=%d\n",
					     (unsigned)(cfg & 0xFF), (int)r);

		} else if (strcmp_cmd(cmd_buffer, CMD_STOP_BIST)) {
			int32_t r = ad9361_bist_prbs(phy, BIST_DISABLE);
			neorv32_uart0_printf("bist_stopped ret=%d\n", (int)r);

		} else if (strcmp_cmd(cmd_buffer, CMD_PINCTL_RX)) {
			if (!power_state) { neorv32_uart0_puts("powered_down\n"); continue; }
			/* Experiment: hand RX/TX gating to the chip's ENABLE/TXNRX *pins*
			 * (level mode) and assert them, in case the data port only streams
			 * when ENABLE is physically high (vs SPI-only ENSM=FDD). The reg
			 * value mirrors ad9361_ensm_set_state(FDD, pinctrl=1); GPIO[0]/[1]
			 * reach the chip enable/txnrx through the IP. Reversible: pinctl_off.
			 * Pair with hold_bist for a deterministic RX stimulus. */
			neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 1);
			neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 1);
			ad9361_spi_write(phy->spi, REG_ENSM_CONFIG_1,
					 LEVEL_MODE | ENABLE_ENSM_PIN_CTRL | TO_ALERT | FORCE_TX_ON);
			no_os_udelay(1000);
			int32_t cfg = ad9361_spi_read(phy->spi, REG_ENSM_CONFIG_1);
			int32_t st  = ad9361_spi_read(phy->spi, 0x017);   /* ENSM state (0xa=FDD) */
			/* OR-accumulate ch0 I/Q over a window: any non-zero => RX data appeared */
			AD9361_REG(0x0404)        = 0x6;   /* W1C clear pn_oos/err ch0_I */
			AD9361_REG(0x0404 + 0x40) = 0x6;   /* ch0_Q */
			uint32_t seen = 0;
			for (int k = 0; k < 512; k++) {
				seen |= (AD9361_REG(0x0408) & 0xFFFF);
				seen |= (AD9361_REG(0x0448) & 0xFFFF);
			}
			neorv32_uart0_printf("pinctl_rx ENSM_CFG1=0x%x state=0x%x ch0_data=%s (OR=0x%x)\n",
					     (unsigned)(cfg & 0xFF), (unsigned)(st & 0xFF),
					     seen ? "NONZERO" : "still-zero", (unsigned)seen);

		} else if (strcmp_cmd(cmd_buffer, CMD_PINCTL_OFF)) {
			/* Restore SPI-controlled FDD (clears ENABLE_ENSM_PIN_CTRL). */
			ad9361_spi_write(phy->spi, REG_ENSM_CONFIG_1,
					 LEVEL_MODE | TO_ALERT | FORCE_TX_ON);
			int32_t cfg = ad9361_spi_read(phy->spi, REG_ENSM_CONFIG_1);
			neorv32_uart0_printf("pinctl_off ENSM_CFG1=0x%x (SPI FDD restored)\n",
					     (unsigned)(cfg & 0xFF));

		} else if (strcmp_cmd(cmd_buffer, CMD_LOOPBACK_ON)) {
			/* AD9361 internal TX->RX baseband loopback (RF bypassed).
			 *
			 * The BB loopback path bypasses the RX analog DC-offset /
			 * gain handling. Treat loopback
			 * EVM as qualitative only; use hold_bist + get_valid_rate
			 * (PN lock) as the quantitative interface-integrity metric
			 * and RF EVM as the end-to-end quality metric. */
			ad9361_bist_prbs(phy, BIST_DISABLE);
			int32_t r = ad9361_bist_loopback(phy, 1);
			neorv32_uart0_printf("loopback_on mode=%d ret=%d\n",
					     (int)phy->bist_loopback_mode, (int)r);

		} else if (strcmp_cmd(cmd_buffer, CMD_LOOPBACK_OFF)) {
			/* Disable internal loopback; RX listens to the external SMA cable / RF. */
			int32_t r = ad9361_bist_loopback(phy, 0);
			neorv32_uart0_printf("loopback_off mode=%d ret=%d\n",
					     (int)phy->bist_loopback_mode, (int)r);

		} else if (strcmp_cmd(cmd_buffer, CMD_CLKSEL_ON)) {
			/* Invert TX FB_CLK: chip samples TX data mid-eye instead of at
			 * the transitions (see DAC_REG_CLKSEL comment). */
			AD9361_REG(DAC_REG_CLKSEL) = 1;
			neorv32_uart0_printf("clksel_on CLKSEL=0x%x (FB_CLK inverted, mid-eye)\n",
					     (unsigned)AD9361_REG(DAC_REG_CLKSEL));

		} else if (strcmp_cmd(cmd_buffer, CMD_CLKSEL_OFF)) {
			AD9361_REG(DAC_REG_CLKSEL) = 0;
			neorv32_uart0_printf("clksel_off CLKSEL=0x%x (FB_CLK edge-aligned default)\n",
					     (unsigned)AD9361_REG(DAC_REG_CLKSEL));

		} else if (parse_cmd_arg(cmd_buffer, CMD_SET_TX_ATTEN, &cmd_arg)) {
			/* R4: runtime TX attenuation (mdB) for the atten/gain sweep. */
			int32_t r = ad9361_set_tx_attenuation(phy, 0, (uint32_t)cmd_arg);
			neorv32_uart0_printf("tx_atten_set %d mdB ret=%d\n",
					     (int)cmd_arg, (int)r);

		} else if (parse_cmd_arg(cmd_buffer, CMD_SET_RX_GAIN, &cmd_arg)) {
			/* R4: runtime manual RX gain (dB). Requires MGC mode (set at boot). */
			int32_t r = ad9361_set_rx_rf_gain(phy, 0, (int32_t)cmd_arg);
			neorv32_uart0_printf("rx_gain_set %d dB ret=%d\n",
					     (int)cmd_arg, (int)r);

		} else if (strcmp_cmd(cmd_buffer, CMD_GET_RSSI)) {
			/* R4: compact single-line RSSI + current RX gain for sweep logging. */
			struct rf_rssi rssi = {0};
			rssi.ant = 0;
			int32_t r = ad9361_get_rx_rssi(phy, 0, &rssi);
			int32_t g = 0;
			ad9361_get_rx_rf_gain(phy, 0, &g);
			neorv32_uart0_printf("rssi symbol=%u gain=%d ret=%d\n",
					     (unsigned)rssi.symbol, (int)g, (int)r);

		} else if (strcmp_cmd(cmd_buffer, CMD_POWER_DOWN)) {
			/* Tier-0 deep low-power: chip ENSM SLEEP only (the dominant Watts:
			 * RF synths, mixers, ADC/DAC, BB filters). Measured on mpf300
			 * hardware: this SLEEP sequence leaves BBPLL/DATA_CLK RUNNING
			 * (l_clk monitor unchanged at 61.44 MHz, PF_CCC locked
			 * throughout) -- a WAIT-class state, so the l_clk fabric domain
			 * keeps clocking on both platforms; the datapath is parked below
			 * before the chip descends, which is what makes that harmless.
			 * The wake-side relock gate in power_up stays as armor for any
			 * future clocks-off deep sleep. The fabric pwr_dn gate (Tier-1: clk_out2 +
			 * s_axi_aresetn reset-hold) is DELIBERATELY NOT used: on this
			 * bitstream the gate cycle corrupts the axi_ad9361 IDELAY/dev_if so
			 * that no IDELAY tap recovers on wake (dig_tune all-'#'). Verified by
			 * the Tier-0 knockout (power_down_t0/up_t0): with pwr_dn left low the
			 * RX capture recovers fully (PHASE 2 pn_oos->0, dig_tune passes).
			 * Re-enabling Tier-1 requires an FPGA fix to the IDELAYCTRL recovery
			 * (separate clk-restart from reset-release) -- future work. */
			if (!power_state) { neorv32_uart0_puts("already_down\n"); continue; }
			/* 1. HLS bridge -> IDLE while l_clk still runs. */
			bridge_reset();
			/* 2. Drop datapath enables into axi_ad9361 (same as disable_rf). */
			neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 0);
			neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 0);
			rf_enabled = 0;
			/* 3. Graceful chip descent: ALERT (TX/RX off, still clocked). */
			ad9361_set_en_state_machine_mode(phy, ENSM_MODE_ALERT);
			/* 4. Kill both RF synthesizers -- the largest power lever. */
			ad9361_rx_lo_powerdown(phy, 1);
			ad9361_tx_lo_powerdown(phy, 1);
			/* 5. Deep SLEEP: BBPLL stops -> DATA_CLK stops -> l_clk dies, so
			 *    axi_ad9361 dev_if + HLS adapter + FIFO l_clk sides quiesce.
			 *    The fabric (clk_out2, IDELAY, up-domain) stays fully powered/
			 *    clocked and undisturbed -- that is what makes wake reliable. */
			ad9361_set_en_state_machine_mode(phy, ENSM_MODE_SLEEP);
			power_state = 0;
			neorv32_uart0_puts("power_down ok\n");

		} else if (strcmp_cmd(cmd_buffer, CMD_POWER_UP)) {
			/* Tier-0 wake. The fabric was never gated in power_down, so the
			 * axi_ad9361 up-domain registers (ADC channel enables) and the
			 * IDELAY taps PERSIST -- no fabric re-config is needed. But the
			 * chip-side power-down (LO power-down + ENSM SLEEP) and the wake
			 * dig_tune invalidate THREE things, and ALL must be recovered or the
			 * constellation is destroyed:
			 *   (a) TX quadrature correction -- stale after the LO power-cycle.
			 *       RESTORED from the boot snapshot (step 2b); re-running the cal
			 *       drifts to ~60% EVM by the 2nd cycle.
			 *   (b) LVDS capture eye -- re-centered by dig_tune (step 4).
			 *   (c) chip TX-enable / data-port / BIST state -- dig_tune leaves a
			 *       residual that compounds across repeated wakes; cleared by the
			 *       bist_loopback toggle (step 4b) -- the same net effect as the
			 *       bench "Measure Floor".
			 * (a) and (c) are independent fixes for independent failures and are
			 * BOTH REQUIRED: (a) alone still dies on the 2nd-cycle BIST residual;
			 * (c) alone still has the stale TX quad. Confirmed on HW. */
			if (power_state) { neorv32_uart0_puts("already_up\n"); continue; }
			/* 1. Wake the chip (SPI is alive even in SLEEP): ALERT, LOs on. */
			ad9361_set_en_state_machine_mode(phy, ENSM_MODE_ALERT);
			ad9361_rx_lo_powerdown(phy, 0);
			ad9361_tx_lo_powerdown(phy, 0);
			/* 2. Wait for BBPLL relock (it powers the sample/DATA clock; l_clk
			 *    only returns once locked). Poll 0x05E[7], bounded ~100 ms. */
			for (int i = 0; i < 1000; i++) {
				int32_t bb = ad9361_spi_read(phy->spi, 0x05E);
				if (bb >= 0 && (bb & 0x80)) break;
				no_os_udelay(100);
			}
			/* 2b. Restore the LO-dependent RF corrections that the LO
			 *     power-cycle invalidated.
			 *
			 *     RF DC offset: re-run the cal -- it has no cross-wake state and
			 *     was verified stable (ret=0, no DC drift), so a fresh measure is
			 *     fine.
			 *
			 *     TX quadrature: DO NOT re-run the cal. ad9361_tx_quad_calib
			 *     seeds from phy->last_tx_quad_cal_phase, so each wake builds on
			 *     the previous result and drifts -- it returns 0 ("success") yet
			 *     lands at ~1 dB I/Q imbalance (EVM ~60%) by the 2nd cycle and
			 *     never self-corrects. Instead RESTORE the boot cal result (the
			 *     chip-written TX1 phase/gain corr regs), which is deterministic.
			 *     Done after the RFDC cal so do_calib's state churn can't disturb
			 *     it, and before FDD/TX so the correction is in place first. */
			int32_t cret_dc = ad9361_do_calib(phy, RFDC_CAL, -1);
			if (tx_quad_corr_valid)
				for (int i = 0; i < 4; i++)
					ad9361_spi_write(phy->spi, TX_QUAD_CORR_REG[i],
							 tx_quad_corr_snap[i]);
			neorv32_uart0_printf("[power_up] RFDC ret=%d  TX-quad restored(boot)=%d\n",
					     (int)cret_dc, tx_quad_corr_valid);
			/* 3. FDD: chip resumes DATA_CLK -> l_clk returns and the (never-reset)
			 *    axi_ad9361 dev_if resumes capturing on the same IDELAY taps. */
			ad9361_set_en_state_machine_mode(phy, ENSM_MODE_FDD);
			no_os_mdelay(1);
			/* 3b. Gate on the link clock really being back: poll the l_clk rate
			 *     monitor to the expected DATA_CLK rate (see wait_l_clk_rate --
			 *     on PolarFire this is the PF_CCC relock gate; nothing below may
			 *     run against a free-running l_clk). Timeout = warn loudly and
			 *     continue: nothing below is destructive, and a wrecked
			 *     constellation plus this line is the diagnosis. */
			{
				int ms = wait_l_clk_rate();
				if (ms < 0)
					neorv32_uart0_puts("[power_up] WARNING: l_clk rate poll TIMED OUT (PLL not relocked?)\n");
				else
					neorv32_uart0_printf("[power_up] l_clk at rate after %d ms\n", ms);
				uint32_t st = AD9361_REG(ADC_REG_STATUS);
				neorv32_uart0_printf("[power_up] adc_status=0x%x link_ok=%u%s\n",
						     (unsigned)st, (unsigned)(st & 0x1),
						     PLATFORM_IS_XILINX() ? "" :
						     " (PolarFire: PF_CCC lock && frame ok)");
			}
			/* 4. Xilinx only: re-center the LVDS capture eye (IDELAY re-tune
			 *    against the relocked DATA_CLK phase). PolarFire has no
			 *    IDELAYs -- RX timing is static (SDC + P&R), nothing to
			 *    re-acquire -- so the step is skipped. */
			if (PLATFORM_IS_XILINX()) {
				uint8_t sk = phy->pdata->dig_interface_tune_skipmode;
				phy->pdata->dig_interface_tune_skipmode = 1;
				ad9361_dig_tune(phy, 0, BE_MOREVERBOSE | DO_IDELAY);
				phy->pdata->dig_interface_tune_skipmode = sk;
			} else {
				neorv32_uart0_puts("[power_up] dig_tune skipped (PolarFire: static SDC timing)\n");
			}
			/* 4b. Clear the chip TX-enable / data-port / BIST residual the wake
			 *     dig_tune leaves behind (it drives BIST + internal loopback +
			 *     the data port to tune). The residual is harmless on a one-shot
			 *     boot but COMPOUNDS across repeated wakes and mangles RX by the
			 *     2nd cycle. This is a SEPARATE failure from the TX-quad staleness
			 *     in 2b -- both fixes are required (the bench "Measure Floor"
			 *     clears exactly this residual, which is how it was found).
			 *     Replicate Measure Floor's net effect: disable any PRBS
			 *     injection, then toggle bist_loopback. bist_loopback(0) re-runs
			 *     fix_ch_cross/en_dis_tx (TX channel re-enabled) and rewrites the
			 *     REG_OBSERVE_CONFIG loop-test bits. Kept on PolarFire too (no
			 *     wake dig_tune there, so no residual): it is idempotent and
			 *     re-runs en_dis_tx after SLEEP, keeping both platforms' wake
			 *     sequences identical. */
			ad9361_bist_prbs(phy, BIST_DISABLE);
			ad9361_bist_loopback(phy, 1);
			ad9361_bist_loopback(phy, 0);
			/* 5. Datapath enables + re-prime the TX burst (mirrors boot). */
			neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 1);
			neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 1);
			rf_enabled = 1;
			bridge_reset();
			bridge_load_tx_data(qpsk_tx_samples, QPSK_TX_NUM_SAMPLES);
			bridge_enable();
			/* 6. Restore the R1 operating point. */
			ad9361_set_rx_gain_control_mode(phy, 0, RF_GAIN_MGC);
			ad9361_set_rx_rf_gain(phy, 0, 30);
			ad9361_set_tx_attenuation(phy, 0, 10000);
			power_state = 1;
			neorv32_uart0_puts("power_up ok\n");

		} else if (strcmp_cmd(cmd_buffer, CMD_POWER_DOWN_T0)) {
			/* Bench twin of power_down -- RETAINED as a diagnostic/A-B tool, not
			 * for normal use (use power_down for that).
			 *
			 * It is the same Tier-0 sequence production power_down now uses
			 * (chip ENSM SLEEP, pwr_dn left LOW so clk_out2 / s_axi_aresetn are
			 * never gated and the axi_ad9361 up-domain + IDELAY + dev_if stay
			 * intact). Originally the "knockout" that proved the Tier-1 fabric
			 * gate cycle was what broke wake capture. Kept in because:
			 *   (1) if Tier-1 is ever re-enabled in the FPGA, production would
			 *       assert pwr_dn again and this pair is the Tier-0 reference for
			 *       an A/B power / functionality comparison; and
			 *   (2) power_up_t0 dumps the verbose RX-capture diagnostic on wake.
			 * Keep it byte-for-byte equal to production power_down (minus pwr_dn,
			 * which production also no longer sets) so the comparison stays honest. */
			if (!power_state) { neorv32_uart0_puts("already_down\n"); continue; }
			bridge_reset();
			neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 0);
			neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 0);
			rf_enabled = 0;
			ad9361_set_en_state_machine_mode(phy, ENSM_MODE_ALERT);
			ad9361_rx_lo_powerdown(phy, 1);
			ad9361_tx_lo_powerdown(phy, 1);
			ad9361_set_en_state_machine_mode(phy, ENSM_MODE_SLEEP);
			/* NO pwr_dn -- fabric left running. */
			power_state = 0;
			neorv32_uart0_puts("power_down_t0 ok\n");

		} else if (strcmp_cmd(cmd_buffer, CMD_POWER_UP_T0)) {
			/* Bench twin of power_up -- RETAINED as a diagnostic tool (use
			 * power_up for normal operation). It is the SAME Tier-0 wake as
			 * production -- including the RFDC/TX_QUAD re-cal that restores EVM,
			 * so it leaves a CLEAN operating point (no 60% EVM footgun) -- PLUS a
			 * verbose diag_dig_tune_one_step() readout of the RX-capture state
			 * after the l_clk stop/restart. Reach for this when you want the
			 * PHASE 1/2/3 capture dump on a power cycle. Keep it in step with
			 * production power_up (minus the probe) so the comparison is honest. */
			if (power_state) { neorv32_uart0_puts("already_up\n"); continue; }
			ad9361_set_en_state_machine_mode(phy, ENSM_MODE_ALERT);
			ad9361_rx_lo_powerdown(phy, 0);
			ad9361_tx_lo_powerdown(phy, 0);
			for (int i = 0; i < 1000; i++) {
				int32_t bb = ad9361_spi_read(phy->spi, 0x05E);
				if (bb >= 0 && (bb & 0x80)) break;
				no_os_udelay(100);
			}
			/* Restore the LO-dependent corrections (same as production
			 * power_up): re-run RFDC, restore the boot TX-quad result rather
			 * than re-running the drift-prone TX_QUAD cal. */
			ad9361_do_calib(phy, RFDC_CAL, -1);
			if (tx_quad_corr_valid)
				for (int i = 0; i < 4; i++)
					ad9361_spi_write(phy->spi, TX_QUAD_CORR_REG[i],
							 tx_quad_corr_snap[i]);
			ad9361_set_en_state_machine_mode(phy, ENSM_MODE_FDD);
			no_os_mdelay(1);
			/* Link-clock gate, same as production power_up (PolarFire: PF_CCC
			 * relock; Xilinx: DATA_CLK returned). */
			{
				int ms = wait_l_clk_rate();
				if (ms < 0)
					neorv32_uart0_puts("[power_up_t0] WARNING: l_clk rate poll TIMED OUT (PLL not relocked?)\n");
				else
					neorv32_uart0_printf("[power_up_t0] l_clk at rate after %d ms\n", ms);
			}
			/* Verbose capture readout (boot 6.6 probe) -- the point of the t0
			 * twin, kept on both platforms + re-acquire dig_tune (Xilinx only,
			 * same gating as production power_up). */
			diag_dig_tune_one_step(phy, 8, 8);
			if (PLATFORM_IS_XILINX()) {
				uint8_t sk = phy->pdata->dig_interface_tune_skipmode;
				phy->pdata->dig_interface_tune_skipmode = 1;
				ad9361_dig_tune(phy, 0, BE_MOREVERBOSE | DO_IDELAY);
				phy->pdata->dig_interface_tune_skipmode = sk;
			} else {
				neorv32_uart0_puts("[power_up_t0] dig_tune skipped (PolarFire: static SDC timing)\n");
			}
			/* Re-establish TX-enable / data-port / BIST state (see power_up). */
			ad9361_bist_prbs(phy, BIST_DISABLE);
			ad9361_bist_loopback(phy, 1);
			ad9361_bist_loopback(phy, 0);
			neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 1);
			neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 1);
			rf_enabled = 1;
			bridge_reset();
			bridge_load_tx_data(qpsk_tx_samples, QPSK_TX_NUM_SAMPLES);
			bridge_enable();
			ad9361_set_rx_gain_control_mode(phy, 0, RF_GAIN_MGC);
			ad9361_set_rx_rf_gain(phy, 0, 30);
			ad9361_set_tx_attenuation(phy, 0, 10000);
			power_state = 1;
			neorv32_uart0_puts("power_up_t0 ok\n");
		}
		/* Unknown commands silently ignored */
	}

halt:
	neorv32_uart0_puts("[ad9361_no-os] HALTED\n");
	while (1)
		__asm__ volatile ("wfi");
	return 0;
}

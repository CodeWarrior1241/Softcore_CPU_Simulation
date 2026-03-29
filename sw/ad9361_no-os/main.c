/*
 * AD9361 no-os driver application for NEORV32 + FMCOMMS2/4 on AU15P.
 *
 * Initialises the AD9361 via SPI using the Analog Devices no-os driver,
 * sets FDD mode at 2.4 GHz, and enters a status monitoring loop.
 */

#include <neorv32.h>
#include "ad9361_api.h"
#include "parameters.h"
#include "neorv32_no_os_spi.h"
#include "neorv32_no_os_gpio.h"
#include "axi_ad9361_adapter_ctrl.h"
#include "qpsk_tx_data.h"

/* ---------- UART command interface ---------- */
#define CMD_BUFFER_SIZE    32
#define NUM_RX_SAMPLES     1024

/* Command strings */
#define CMD_ENABLE_RF       "enable_rf"
#define CMD_DISABLE_RF      "disable_rf"
#define CMD_ENABLE_SNAPSHOT "enable_snapshot"
#define CMD_GET_STATUS      "get_status"

/* Response strings */
#define RESP_RF_ENABLED     "rf_enabled\n"
#define RESP_RF_DISABLED    "rf_disabled\n"
#define RESP_SNAPSHOT       "snapshot_enabled\n"

static int rf_enabled = 0;

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

/* FMCOMMS2/4 default configuration (from no-os/projects/ad9361/src/main.c) */
AD9361_InitParam default_init_param = {
	/* Device selection */
	ID_AD9361,	// dev_sel
	/* Reference Clock */
	40000000UL,	// reference_clk_rate (FMCOMMS2/4 40 MHz XTAL)
	/* Base Configuration */
	1,		// two_rx_two_tx_mode_enable
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
	10000,		// tx_attenuation_mdB
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
	0,		// digital_interface_tune_skip_mode
	0,		// digital_interface_tune_fir_disable
	1,		// pp_tx_swap_enable
	1,		// pp_rx_swap_enable
	0,		// tx_channel_swap_enable
	0,		// rx_channel_swap_enable
	1,		// rx_frame_pulse_mode_enable
	0,		// two_t_two_r_timing_enable
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

	/* 6. Start streaming adapter bridge and configure datapath */
	neorv32_uart0_puts("[ad9361_no-os] Configuring streaming adapter bridge...\n");

	/* Start ap_ctrl_chain (must be called once before any register access) */
	bridge_start();

	/* Soft-reset adapter (clears pointers, sticky flags) */
	BRIDGE_REG(BRIDGE_REG_CTRL) = BRIDGE_CTRL_SOFT_RESET;

	/* Enable TX channel 0 (I0/Q0) and RX channel 0 (I0/Q0) */
	BRIDGE_REG(BRIDGE_REG_TX_CTRL) = BRIDGE_CH_EN_CH0;
	BRIDGE_REG(BRIDGE_REG_RX_CTRL) = BRIDGE_CH_EN_CH0;

	/* Enable adapter: global + TX + RX */
	BRIDGE_REG(BRIDGE_REG_CTRL) = BRIDGE_CTRL_ENABLE | BRIDGE_CTRL_TX_ENABLE | BRIDGE_CTRL_RX_ENABLE;

	/* Load 1024 QPSK IQ samples into TX buffer and trigger burst */
	bridge_load_tx_data(qpsk_tx_samples, QPSK_TX_NUM_SAMPLES);
	if (!bridge_trigger_tx(QPSK_TX_NUM_SAMPLES)) {
		neorv32_uart0_puts("[ad9361_no-os] TX burst trigger TIMEOUT\n");
	}
	neorv32_uart0_printf("[ad9361_no-os] TX loaded and triggered: %u samples\n",
			     (unsigned)QPSK_TX_NUM_SAMPLES);
	neorv32_uart0_puts("[ad9361_no-os] Adapter enabled (TX + RX)\n");

	/* 7. Assert up_enable and up_txnrx (data path enable) */
	neorv32_gpio_pin_set(GPIO_UP_ENABLE_PIN, 1);
	neorv32_gpio_pin_set(GPIO_UP_TXNRX_PIN, 1);
	neorv32_uart0_puts("[ad9361_no-os] Data path enabled (up_enable=1, up_txnrx=1)\n");

	/* 8. Read back LO frequencies */
	ad9361_get_rx_lo_freq(phy, &rx_lo);
	ad9361_get_tx_lo_freq(phy, &tx_lo);
	neorv32_uart0_printf("[ad9361_no-os] RX LO: %u MHz, TX LO: %u MHz\n",
			     (unsigned)(rx_lo / 1000000ULL),
			     (unsigned)(tx_lo / 1000000ULL));

	/* 9. UART command loop */
	neorv32_uart0_puts("[ad9361_no-os] Ready — awaiting commands\n");
	char cmd_buffer[CMD_BUFFER_SIZE];

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
			/* Clear RX buffer, then trigger drain and wait for RX data */
			BRIDGE_REG(BRIDGE_REG_CTRL) =
				BRIDGE_CTRL_ENABLE | BRIDGE_CTRL_TX_ENABLE | BRIDGE_CTRL_RX_ENABLE | BRIDGE_CTRL_RX_CLEAR;
			/* Wait for RX buffer to fill and bridge to signal RX_READY */
			if (!bridge_wait_rx_ready()) {
				neorv32_uart0_puts("snapshot_timeout\n");
			} else {
				neorv32_uart0_puts(RESP_SNAPSHOT);
				send_rx_snapshot();
				bridge_release_rx();
			}

		} else if (strcmp_cmd(cmd_buffer, CMD_GET_STATUS)) {
			ad9361_get_en_state_machine_mode(phy, &ensm_mode);
			uint32_t adapter_status = BRIDGE_REG(BRIDGE_REG_STATUS);
			uint32_t rx_fill = BRIDGE_REG(BRIDGE_REG_RX_FILL);
			uint32_t bridge_status = BRIDGE_REG(BRIDGE_REG_BRIDGE_STATUS);
			uint32_t gpio_status = neorv32_gpio_port_get() & 0xFF;
			neorv32_uart0_printf("ENSM:%s RF:%s ADAPTER:0x%02x RX_FILL:%u BRIDGE:0x%02x GPIO:0x%02x\n",
					     (ensm_mode < 8) ? ensm_mode_str[ensm_mode] : "?",
					     rf_enabled ? "ON" : "OFF",
					     (unsigned)adapter_status,
					     (unsigned)rx_fill,
					     (unsigned)bridge_status,
					     (unsigned)gpio_status);
		}
		/* Unknown commands silently ignored */
	}

halt:
	neorv32_uart0_puts("[ad9361_no-os] HALTED\n");
	while (1)
		__asm__ volatile ("wfi");
	return 0;
}

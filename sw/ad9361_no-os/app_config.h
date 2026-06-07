#ifndef APP_CONFIG_H_
#define APP_CONFIG_H_

#define HAVE_SPLIT_GAIN_TABLE   1
#define HAVE_TDD_SYNTH_TABLE    1
#define AD9361_DEVICE           1
#define AD9364_DEVICE           0

/* AXI_ADC_NOT_PRESENT used to be force-defined here, which stubbed out
 * ad9361_dig_tune() (LVDS IDELAY calibration) and left RX framing
 * un-aligned (header_s=0 across all channels). We now compile in
 * cf_axi_adc / cf_axi_dac via the makefile so dig_tune is real. */

/* Verbose messages cost ~5-10 KB; enabled here so dev_err() / dev_warn()
 * actually print. Without this, every "Failed X" log inside no-OS is
 * swallowed and post_setup / dig_tune failures look like opaque -ENODEV. */
#define HAVE_VERBOSE_MESSAGES
/* HAVE_DEBUG_MESSAGES disabled to quiet the startup spew: it routes ~82 dev_dbg
 * sites (many in per-register / per-lane loops) inside ad9361_init / post_setup
 * / dig_tune to the UART, producing hundreds of lines at boot. HAVE_VERBOSE_
 * MESSAGES stays on so dev_err() / dev_warn() still surface real failures.
 * Re-enable for deep per-lane IODELAY-window / chosen-tap tracing. */
/* #define HAVE_DEBUG_MESSAGES */         /* dev_dbg: per-lane IODELAY window + chosen tap (and full no-OS debug flood) */

#endif /* APP_CONFIG_H_ */

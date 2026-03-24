#ifndef APP_CONFIG_H_
#define APP_CONFIG_H_

#define HAVE_SPLIT_GAIN_TABLE   1
#define HAVE_TDD_SYNTH_TABLE    1
#define AD9361_DEVICE           1
#define AD9364_DEVICE           0

#ifndef AXI_ADC_NOT_PRESENT
#define AXI_ADC_NOT_PRESENT
#endif

/* Disable verbose messages to save ~5-10KB code size.
 * Enable during debugging with 128KB IMEM. */
/* #define HAVE_VERBOSE_MESSAGES */

#endif /* APP_CONFIG_H_ */

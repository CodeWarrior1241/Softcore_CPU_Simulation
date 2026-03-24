#ifndef PARAMETERS_H_
#define PARAMETERS_H_

/* SPI configuration */
#define SPI_DEVICE_ID       0
#define SPI_CS              0       /* AD9361 on spi_csn_o[0] */

/* GPIO pin numbers (NEORV32 gpio_o bit positions, from build_all.tcl) */
#define GPIO_UP_ENABLE_PIN  0       /* gpio_o[0] = up_enable */
#define GPIO_UP_TXNRX_PIN  1       /* gpio_o[1] = up_txnrx */
#define GPIO_RESET_PIN      2       /* gpio_o[2] = gpio_resetb */
#define GPIO_SYNC_PIN       3       /* gpio_o[3] = gpio_sync */
#define GPIO_EN_AGC_PIN     4       /* gpio_o[4] = gpio_en_agc */
#define GPIO_CTL0_PIN       5       /* gpio_o[5] = gpio_ctl[0] */

/* AXI peripheral base addresses (from build_all.tcl) */
#define AXI_AD9361_BASE         0x44A00000UL
#define AXI_AD9361_ADAPTER_BASE 0x44A10000UL
#define BRAM_BASE               0xC0000000UL

/* System clocks */
#define CPU_CLOCK_HZ        100000000UL
#define BAUD_RATE           115200

#endif /* PARAMETERS_H_ */

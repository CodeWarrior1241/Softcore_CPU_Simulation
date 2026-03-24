/*
 * NEORV32 SPI platform wrapper for Analog Devices no-os framework.
 *
 * Maps no_os_spi_platform_ops to the NEORV32 SPI HAL.
 * AD9361 uses SPI Mode 1 (CPOL=0, CPHA=1), MSB-first, 3-byte transactions.
 *
 * Clock calculation (100 MHz CPU):
 *   spi_clk = cpu_clk / (2 * PRSC_LUT[prsc] * (1 + cdiv))
 *   PRSC=0 (prescaler=2), CDIV=19 -> 100M / (2*2*(1+19)) = 1.25 MHz
 *   PRSC=0 (prescaler=2), CDIV=9  -> 100M / (2*2*(1+9))  = 2.5  MHz
 */

#include <neorv32.h>
#include "no_os_spi.h"
#include "no_os_alloc.h"
#include "no_os_error.h"
#include "neorv32_no_os_spi.h"
#include "parameters.h"

/* NEORV32 SPI prescaler lookup (from neorv32_spi.c) */
static const uint32_t prsc_lut[8] = {2, 4, 8, 64, 128, 1024, 2048, 4096};

/*
 * Find prescaler/divider combination for the requested SPI clock.
 * Picks the fastest clock that does not exceed max_speed_hz.
 */
static void spi_calc_clock(uint32_t max_speed_hz, int *prsc, int *cdiv)
{
	uint32_t cpu_clk = CPU_CLOCK_HZ;

	for (int p = 0; p < 8; p++) {
		for (int d = 0; d < 16; d++) {
			uint32_t actual = cpu_clk / (2 * prsc_lut[p] * (1 + d));
			if (actual <= max_speed_hz) {
				*prsc = p;
				*cdiv = d;
				return;
			}
		}
	}
	/* Slowest possible */
	*prsc = 7;
	*cdiv = 15;
}

static int32_t neorv32_spi_init(struct no_os_spi_desc **desc,
				const struct no_os_spi_init_param *param)
{
	struct no_os_spi_desc *d;
	int prsc, cdiv;
	int clk_phase, clk_polarity;

	if (!desc || !param)
		return -EINVAL;

	d = (struct no_os_spi_desc *)no_os_calloc(1, sizeof(*d));
	if (!d)
		return -ENOMEM;

	d->device_id    = param->device_id;
	d->chip_select  = param->chip_select;
	d->mode         = param->mode;
	d->bit_order    = param->bit_order;
	d->max_speed_hz = param->max_speed_hz;
	d->platform_ops = param->platform_ops;

	/* AD9361: Mode 1 (CPOL=0, CPHA=1). Derive from param->mode. */
	clk_polarity = (param->mode & NO_OS_SPI_CPOL) ? 1 : 0;
	clk_phase    = (param->mode & NO_OS_SPI_CPHA) ? 1 : 0;

	/* Calculate prescaler for requested speed (default ~2.5 MHz) */
	uint32_t speed = param->max_speed_hz ? param->max_speed_hz : 2500000;
	spi_calc_clock(speed, &prsc, &cdiv);

	neorv32_spi_setup(prsc, cdiv, clk_phase, clk_polarity);

	*desc = d;
	return 0;
}

static int32_t neorv32_spi_write_and_read(struct no_os_spi_desc *desc,
					  uint8_t *data,
					  uint16_t bytes_number)
{
	if (!desc || !data)
		return -EINVAL;

	neorv32_spi_cs_en((int)desc->chip_select);

	for (uint16_t i = 0; i < bytes_number; i++)
		data[i] = neorv32_spi_transfer(data[i]);

	neorv32_spi_cs_dis();

	return 0;
}

static int32_t neorv32_spi_remove(struct no_os_spi_desc *desc)
{
	if (!desc)
		return -EINVAL;

	neorv32_spi_disable();
	no_os_free(desc);
	return 0;
}

const struct no_os_spi_platform_ops neorv32_spi_ops = {
	.init           = neorv32_spi_init,
	.write_and_read = neorv32_spi_write_and_read,
	.transfer       = NULL,  /* framework fallback uses write_and_read */
	.transfer_dma   = NULL,
	.transfer_dma_async = NULL,
	.remove         = neorv32_spi_remove,
	.transfer_abort = NULL,
};

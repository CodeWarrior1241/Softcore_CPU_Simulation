/*
 * NEORV32 GPIO platform wrapper for Analog Devices no-os framework.
 *
 * Maps no_os_gpio_platform_ops to the NEORV32 GPIO HAL.
 * Direction is fixed in HDL (outputs on gpio_o, inputs on gpio_i),
 * so direction_input/output are no-ops that always succeed.
 *
 * Pin mapping (from build_all.tcl xlslice cells):
 *   gpio_o[0] = up_enable      gpio_o[4] = gpio_en_agc
 *   gpio_o[1] = up_txnrx       gpio_o[5..7] = gpio_ctl[0..2]
 *   gpio_o[2] = gpio_resetb    gpio_i[0..7] = gpio_status[0..7]
 *   gpio_o[3] = gpio_sync
 */

#include <neorv32.h>
#include "no_os_gpio.h"
#include "no_os_alloc.h"
#include "no_os_error.h"
#include "neorv32_no_os_gpio.h"

static int32_t neorv32_gpio_get(struct no_os_gpio_desc **desc,
				const struct no_os_gpio_init_param *param)
{
	struct no_os_gpio_desc *d;

	if (!desc || !param)
		return -EINVAL;

	d = (struct no_os_gpio_desc *)no_os_calloc(1, sizeof(*d));
	if (!d)
		return -ENOMEM;

	d->number       = param->number;
	d->port         = param->port;
	d->pull         = param->pull;
	d->platform_ops = param->platform_ops;
	d->extra        = param->extra;

	*desc = d;
	return 0;
}

static int32_t neorv32_gpio_get_optional(struct no_os_gpio_desc **desc,
					 const struct no_os_gpio_init_param *param)
{
	if (!desc)
		return -EINVAL;

	if (!param || param->number < 0) {
		*desc = NULL;
		return 0;
	}

	return neorv32_gpio_get(desc, param);
}

static int32_t neorv32_gpio_remove(struct no_os_gpio_desc *desc)
{
	if (!desc)
		return -EINVAL;

	no_os_free(desc);
	return 0;
}

static int32_t neorv32_gpio_direction_input(struct no_os_gpio_desc *desc)
{
	/* Direction fixed in HDL — no software direction register */
	(void)desc;
	return 0;
}

static int32_t neorv32_gpio_direction_output(struct no_os_gpio_desc *desc,
					     uint8_t value)
{
	/* Direction fixed in HDL — just set the initial value */
	if (!desc)
		return -EINVAL;

	neorv32_gpio_pin_set((int)desc->number, (int)value);
	return 0;
}

static int32_t neorv32_gpio_get_direction(struct no_os_gpio_desc *desc,
					  uint8_t *direction)
{
	(void)desc;
	if (!direction)
		return -EINVAL;

	/* Report as output; direction is fixed in HDL */
	*direction = NO_OS_GPIO_OUT;
	return 0;
}

static int32_t neorv32_gpio_set_value(struct no_os_gpio_desc *desc,
				      uint8_t value)
{
	if (!desc)
		return -EINVAL;

	neorv32_gpio_pin_set((int)desc->number, (int)value);
	return 0;
}

static int32_t neorv32_gpio_get_value(struct no_os_gpio_desc *desc,
				      uint8_t *value)
{
	if (!desc || !value)
		return -EINVAL;

	/* neorv32_gpio_pin_get returns a bitmask, not 0/1 */
	*value = neorv32_gpio_pin_get((int)desc->number) ? 1 : 0;
	return 0;
}

const struct no_os_gpio_platform_ops neorv32_gpio_ops = {
	.gpio_ops_get              = neorv32_gpio_get,
	.gpio_ops_get_optional     = neorv32_gpio_get_optional,
	.gpio_ops_remove           = neorv32_gpio_remove,
	.gpio_ops_direction_input  = neorv32_gpio_direction_input,
	.gpio_ops_direction_output = neorv32_gpio_direction_output,
	.gpio_ops_get_direction    = neorv32_gpio_get_direction,
	.gpio_ops_set_value        = neorv32_gpio_set_value,
	.gpio_ops_get_value        = neorv32_gpio_get_value,
};

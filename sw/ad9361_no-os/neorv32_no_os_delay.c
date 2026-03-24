#include <neorv32.h>
#include "no_os_delay.h"
#include "parameters.h"

void no_os_udelay(uint32_t usecs)
{
	uint64_t start = neorv32_clint_time_get();
	uint64_t ticks = (uint64_t)usecs * (CPU_CLOCK_HZ / 1000000UL);
	while ((neorv32_clint_time_get() - start) < ticks)
		;
}

void no_os_mdelay(uint32_t msecs)
{
	uint64_t start = neorv32_clint_time_get();
	uint64_t ticks = (uint64_t)msecs * (CPU_CLOCK_HZ / 1000UL);
	while ((neorv32_clint_time_get() - start) < ticks)
		;
}

struct no_os_time no_os_get_time(void)
{
	uint64_t ticks = neorv32_clint_time_get();
	struct no_os_time t;
	t.s  = (unsigned int)(ticks / CPU_CLOCK_HZ);
	t.us = (unsigned int)((ticks % CPU_CLOCK_HZ) / (CPU_CLOCK_HZ / 1000000UL));
	return t;
}

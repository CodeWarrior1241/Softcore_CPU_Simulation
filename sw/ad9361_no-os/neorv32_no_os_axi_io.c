/*
 * NEORV32 implementation of no_os_axi_io.h.
 *
 * Bare-metal volatile reads/writes — NEORV32's CPU sees AXI peripherals
 * directly in its 32-bit address space via the XBUS, so no Xil_In32 /
 * mmap wrapper is needed.
 */

#include <stdint.h>
#include "no_os_axi_io.h"

int32_t no_os_axi_io_read(uint32_t base, uint32_t offset, uint32_t *data)
{
	*data = *((volatile uint32_t *)(base + offset));
	return 0;
}

int32_t no_os_axi_io_write(uint32_t base, uint32_t offset, uint32_t data)
{
	*((volatile uint32_t *)(base + offset)) = data;
	return 0;
}

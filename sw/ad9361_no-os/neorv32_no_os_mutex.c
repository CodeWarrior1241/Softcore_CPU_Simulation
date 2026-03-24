/*
 * No-op mutex implementation for bare-metal (no RTOS).
 * The SPI bus dispatcher requires these symbols.
 */
#include "no_os_mutex.h"
#include "no_os_alloc.h"

void no_os_mutex_init(void **mutex)
{
	/* Allocate a dummy byte so the pointer is non-NULL.
	 * The SPI bus code checks for NULL before locking. */
	if (*mutex == (void *)0)
		*mutex = no_os_calloc(1, 1);
}

void no_os_mutex_lock(void *mutex)
{
	(void)mutex;
}

void no_os_mutex_unlock(void *mutex)
{
	(void)mutex;
}

void no_os_mutex_remove(void *mutex)
{
	no_os_free(mutex);
}

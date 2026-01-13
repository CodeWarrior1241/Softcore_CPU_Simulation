// ================================================================================ //
// Snapshot Handler - NEORV32 UART Command Interface                                //
// Exists to exercise the QPSK snapshot BRAM and RF control via UART commands.      //
// Part of the QPSK Triple Comparison Project                                       //
// Licensed under the BSD-3-Clause license                                          //
// ================================================================================ //

/**
 * @file snapshot_handler/main.c
 * @brief UART command handler for QPSK signal capture and RF control.
 *
 * This application implements a UART command interface for communication with
 * a MATLAB of Python GUI. It handles RF enable/disable commands and IQ sample capture.
 *
 * UART Protocol (115200 baud, LF terminated):
 *   Commands received:
 *     "enable_rf"       -> Respond: "rf_enabled"
 *     "disable_rf"      -> Respond: "rf_disabled"
 *     "enable_snapshot" -> Respond: "snapshot_enabled" + 4096 bytes IQ data
 *
 *   IQ Data Format (little-endian):
 *     1024 samples x 4 bytes = 4096 bytes
 *     Each sample: [I_lo, I_hi, Q_lo, Q_hi] (16-bit signed I and Q)
 */

#include <neorv32.h>
#include <string.h>


/**********************************************************************//**
 * @name User configuration
 **************************************************************************/
/**@{*/
/** UART BAUD rate */
#define BAUD_RATE 115200

/** Maximum command buffer size */
#define CMD_BUFFER_SIZE 32

/** Number of IQ samples per snapshot */
#define NUM_IQ_SAMPLES 1024

/** GPIO pin for RF enable control */
#define RF_ENABLE_PIN 0

/** IQ BRAM base address (memory-mapped via AXI switch) */
#define IQ_BRAM_BASE 0xC0000000UL
/**@}*/


/**********************************************************************//**
 * @name Command and response strings
 **************************************************************************/
/**@{*/
#define CMD_ENABLE_RF       "enable_rf"
#define CMD_DISABLE_RF      "disable_rf"
#define CMD_ENABLE_SNAPSHOT "enable_snapshot"

#define RESP_RF_ENABLED     "rf_enabled\n"
#define RESP_RF_DISABLED    "rf_disabled\n"
#define RESP_SNAPSHOT       "snapshot_enabled\n"
/**@}*/


/**********************************************************************//**
 * @name Global variables
 **************************************************************************/
/**@{*/
/** IQ sample buffer: 1024 samples x 4 bytes = 4096 bytes */
static uint8_t iq_buffer[NUM_IQ_SAMPLES * 4];

/** RF enabled state */
static int rf_enabled = 0;
/**@}*/


/**********************************************************************//**
 * @name Function prototypes
 **************************************************************************/
/**@{*/
static void handle_enable_rf(void);
static void handle_disable_rf(void);
static void handle_enable_snapshot(void);
static void capture_iq_samples(void);
static void send_iq_data(void);
static int read_command(char *buffer, int max_len);
static int strcmp_cmd(const char *cmd, const char *ref);
/**@}*/


/**********************************************************************//**
 * Enable RF via GPIO.
 **************************************************************************/
static void handle_enable_rf(void) {
  neorv32_gpio_pin_set(RF_ENABLE_PIN, 1);
  rf_enabled = 1;
  neorv32_uart0_puts(RESP_RF_ENABLED);
}


/**********************************************************************//**
 * Disable RF via GPIO.
 **************************************************************************/
static void handle_disable_rf(void) {
  neorv32_gpio_pin_set(RF_ENABLE_PIN, 0);
  rf_enabled = 0;
  neorv32_uart0_puts(RESP_RF_DISABLED);
}


/**********************************************************************//**
 * Handle snapshot request: capture IQ samples and send them.
 **************************************************************************/
static void handle_enable_snapshot(void) {
  // Send acknowledgment first
  neorv32_uart0_puts(RESP_SNAPSHOT);

  // Capture IQ samples from hardware
  capture_iq_samples();

  // Send binary IQ data
  send_iq_data();
}


/**********************************************************************//**
 * Capture IQ samples from hardware into the buffer.
 *
 * Reads IQ samples from the IQ BRAM at address 0xC0000000. The BRAM is
 * connected via AXI switch and contains 1024 x 32-bit IQ samples where:
 *   - I[15:0] is in the lower 16 bits
 *   - Q[31:16] is in the upper 16 bits
 **************************************************************************/
static void capture_iq_samples(void) {
  // Pointer to IQ BRAM (memory-mapped)
  volatile uint32_t *iq_bram = (volatile uint32_t *)IQ_BRAM_BASE;

  for (int i = 0; i < NUM_IQ_SAMPLES; i++) {
    // Read 32-bit IQ word from BRAM
    uint32_t iq_word = iq_bram[i];

    // Extract I (lower 16 bits) and Q (upper 16 bits)
    int16_t i_val = (int16_t)(iq_word & 0xFFFF);
    int16_t q_val = (int16_t)((iq_word >> 16) & 0xFFFF);

    // Pack into buffer (little-endian: I_lo, I_hi, Q_lo, Q_hi)
    int idx = i * 4;
    iq_buffer[idx + 0] = (uint8_t)(i_val & 0xFF);
    iq_buffer[idx + 1] = (uint8_t)((i_val >> 8) & 0xFF);
    iq_buffer[idx + 2] = (uint8_t)(q_val & 0xFF);
    iq_buffer[idx + 3] = (uint8_t)((q_val >> 8) & 0xFF);
  }
}


/**********************************************************************//**
 * Send IQ data buffer over UART as raw bytes.
 **************************************************************************/
static void send_iq_data(void) {
  for (int i = 0; i < NUM_IQ_SAMPLES * 4; i++) {
    neorv32_uart0_putc((char)iq_buffer[i]);
  }
}


/**********************************************************************//**
 * Read a command line from UART (blocking, LF terminated).
 *
 * @param[out] buffer Destination buffer for the command string.
 * @param[in] max_len Maximum buffer length.
 * @return Number of characters read (excluding terminator), or -1 on overflow.
 **************************************************************************/
static int read_command(char *buffer, int max_len) {
  int idx = 0;
  char c;

  while (idx < max_len - 1) {
    c = neorv32_uart0_getc();

    // Check for line terminator (LF or CR)
    if (c == '\n' || c == '\r') {
      buffer[idx] = '\0';
      return idx;
    }

    buffer[idx++] = c;
  }

  // Buffer overflow - null terminate and return error
  buffer[max_len - 1] = '\0';
  return -1;
}


/**********************************************************************//**
 * Compare command string (case-sensitive).
 *
 * @param[in] cmd Received command string.
 * @param[in] ref Reference command to compare against.
 * @return 1 if match, 0 otherwise.
 **************************************************************************/
static int strcmp_cmd(const char *cmd, const char *ref) {
  while (*ref) {
    if (*cmd != *ref) {
      return 0;
    }
    cmd++;
    ref++;
  }
  // Check that cmd is also at end (no extra characters)
  return (*cmd == '\0' || *cmd == '\r' || *cmd == '\n');
}


/**********************************************************************//**
 * Main function: initialize hardware and run command loop.
 *
 * @return Will never return.
 **************************************************************************/
int main(void) {

  char cmd_buffer[CMD_BUFFER_SIZE];

  // Capture all exceptions and give debug info via UART
  neorv32_rte_setup();

  // Check if UART0 is available
  if (neorv32_uart0_available() == 0) {
    return 1; // UART not available
  }

  // Check if GPIO is available
  if (neorv32_gpio_available() == 0) {
    return 1; // GPIO not available
  }

  // Setup UART0 at 115200 baud, no interrupts
  neorv32_uart0_setup(BAUD_RATE, 0);

  // Initialize GPIO - set RF enable pin low (disabled)
  neorv32_gpio_pin_set(RF_ENABLE_PIN, 0);

  // Main command loop
  while (1) {
    // Read command from UART (blocking)
    int len = read_command(cmd_buffer, CMD_BUFFER_SIZE);

    if (len <= 0) {
      // Empty command or overflow, ignore
      continue;
    }

    // Parse and execute command
    if (strcmp_cmd(cmd_buffer, CMD_ENABLE_RF)) {
      handle_enable_rf();
    }
    else if (strcmp_cmd(cmd_buffer, CMD_DISABLE_RF)) {
      handle_disable_rf();
    }
    else if (strcmp_cmd(cmd_buffer, CMD_ENABLE_SNAPSHOT)) {
      handle_enable_snapshot();
    }
    // Unknown commands are silently ignored
  }

  return 0;
}

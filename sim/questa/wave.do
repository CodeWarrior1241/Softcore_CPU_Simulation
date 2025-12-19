# ================================================================================
# NEORV32 - Questa Prime Waveform Configuration
# ================================================================================
# Custom waveform configuration for detailed CPU analysis
# Usage: In Questa, run "do wave.do" after loading the design
# ================================================================================

# Clear existing waveforms
delete wave *

# ================================================================================
# Clock and Reset
# ================================================================================
add wave -divider "=== CLOCK & RESET ==="
add wave -format Logic -color Gold      /neorv32_tb/clk_gen
add wave -format Logic -color Red       /neorv32_tb/rst_gen

# ================================================================================
# GPIO
# ================================================================================
add wave -divider "=== GPIO ==="
add wave -format Literal -radix hex     /neorv32_tb/gpio

# ================================================================================
# UART Interfaces
# ================================================================================
add wave -divider "=== UART0 ==="
add wave -format Logic -color Cyan      /neorv32_tb/uart0_txd
add wave -format Logic -color Cyan      /neorv32_tb/uart0_ctsn

add wave -divider "=== UART1 ==="
add wave -format Logic -color Green     /neorv32_tb/uart1_txd
add wave -format Logic -color Green     /neorv32_tb/uart1_ctsn

# ================================================================================
# SPI Interface
# ================================================================================
add wave -divider "=== SPI ==="
add wave -format Logic                  /neorv32_tb/spi_clk
add wave -format Logic                  /neorv32_tb/spi_do
add wave -format Logic                  /neorv32_tb/spi_di
add wave -format Literal -radix hex     /neorv32_tb/spi_csn

# ================================================================================
# I2C / TWI Interface
# ================================================================================
add wave -divider "=== I2C/TWI ==="
add wave -format Logic                  /neorv32_tb/i2c_scl
add wave -format Logic                  /neorv32_tb/i2c_sda

# ================================================================================
# External Bus (XBUS/Wishbone)
# ================================================================================
add wave -divider "=== XBUS Request ==="
add wave -format Literal -radix hex     /neorv32_tb/xbus_core_req.addr
add wave -format Literal -radix hex     /neorv32_tb/xbus_core_req.data
add wave -format Logic                  /neorv32_tb/xbus_core_req.we
add wave -format Literal -radix hex     /neorv32_tb/xbus_core_req.sel
add wave -format Logic                  /neorv32_tb/xbus_core_req.stb
add wave -format Logic                  /neorv32_tb/xbus_core_req.cyc

add wave -divider "=== XBUS Response ==="
add wave -format Literal -radix hex     /neorv32_tb/xbus_core_rsp.data
add wave -format Logic                  /neorv32_tb/xbus_core_rsp.ack
add wave -format Logic                  /neorv32_tb/xbus_core_rsp.err

# ================================================================================
# Stream Link
# ================================================================================
add wave -divider "=== Stream Link TX ==="
add wave -format Literal -radix hex     /neorv32_tb/slink_tx.data
add wave -format Literal -radix hex     /neorv32_tb/slink_tx.addr
add wave -format Logic                  /neorv32_tb/slink_tx.valid
add wave -format Logic                  /neorv32_tb/slink_tx.last
add wave -format Logic                  /neorv32_tb/slink_tx.ready

add wave -divider "=== Stream Link RX ==="
add wave -format Literal -radix hex     /neorv32_tb/slink_rx.data
add wave -format Logic                  /neorv32_tb/slink_rx.valid
add wave -format Logic                  /neorv32_tb/slink_rx.ready

# ================================================================================
# External Interrupts
# ================================================================================
add wave -divider "=== Interrupts ==="
add wave -format Logic -color Orange    /neorv32_tb/msi
add wave -format Logic -color Orange    /neorv32_tb/mti
add wave -format Logic -color Orange    /neorv32_tb/mei

# ================================================================================
# Configure Wave Window
# ================================================================================
configure wave -namecolwidth 300
configure wave -valuecolwidth 150
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns

# Zoom to fit
wave zoom full

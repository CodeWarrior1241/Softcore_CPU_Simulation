# =============================================================================
# NEORV32 Simulation Constraints for AUBoard-15P (XCAU15P-2FFVB676E)
# =============================================================================

# -----------------------------------------------------------------------------
# Differential System Clock (300 MHz LVDS from ECS oscillator X1)
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN AD21 [get_ports ecs_clk_in_clk_p]
set_property PACKAGE_PIN AE21 [get_ports ecs_clk_in_clk_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports ecs_clk_in_clk_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports ecs_clk_in_clk_n]

# Clock constraint for 300 MHz input clock
# Unnecessary as clocking wizard's internal XDC covers this
# create_clock -period 3.333 -name sys_clk [get_ports ecs_clk_in_clk_p]

# -----------------------------------------------------------------------------
# System Reset (Active-Low Push Button PB3)
# -----------------------------------------------------------------------------
set_property PACKAGE_PIN V19 [get_ports system_resetn]
set_property IOSTANDARD LVCMOS12 [get_ports system_resetn]

# -----------------------------------------------------------------------------
# UART Interface (USB-to-UART Bridge via FTDI U21)
# -----------------------------------------------------------------------------
# UART TX - FPGA transmits to host (FPGA output)
set_property PACKAGE_PIN AF15 [get_ports uart0_txd]
set_property IOSTANDARD LVCMOS18 [get_ports uart0_txd]

# UART RX - FPGA receives from host (FPGA input)
set_property PACKAGE_PIN AF14 [get_ports uart0_rxd]
set_property IOSTANDARD LVCMOS18 [get_ports uart0_rxd]

# -----------------------------------------------------------------------------
# Timing Constraints
# -----------------------------------------------------------------------------
# False path for reset signal (asynchronous)
set_false_path -from [get_ports system_resetn]

# UART signals are asynchronous
set_false_path -from [get_ports uart0_rxd]
set_false_path -to [get_ports uart0_txd]

# -----------------------------------------------------------------------------
# Configuration and Bitstream Settings
# -----------------------------------------------------------------------------
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CFGBVS GND [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 2.7 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_32BIT_ADDR YES [current_design]

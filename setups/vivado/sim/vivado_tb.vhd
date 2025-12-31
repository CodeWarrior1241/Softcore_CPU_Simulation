-- ================================================================================ --
-- Vivado Block Design Testbench for NEORV32 RISC-V Processor                       --
-- -------------------------------------------------------------------------------- --
-- This testbench instantiates the Top_wrapper from the Vivado block design and    --
-- provides clock generation, reset, and UART monitoring for simulation.            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vivado_tb is
  generic (
    -- Clock and timing
    CLOCK_FREQUENCY : real := 300.0e6;  -- 300 MHz differential clock input
    BAUD_RATE       : real := 115200.0; -- UART baud rate
    -- Simulation control
    RESET_TIME_NS   : natural := 100    -- Reset duration in nanoseconds
  );
end entity vivado_tb;

architecture sim of vivado_tb is

  -- Clock period for 300 MHz differential clock
  constant CLK_PERIOD : time := (1.0e9 / CLOCK_FREQUENCY) * 1 ns; -- ~3.333 ns

  -- Clock and reset signals
  signal clk_p     : std_logic := '0';
  signal clk_n     : std_logic := '1';
  signal rst_n     : std_logic := '0';

  -- UART signals
  signal uart_txd  : std_logic;
  signal uart_rxd  : std_logic := '1'; -- Idle high

begin

  -- ============================================================================
  -- Clock Generation (300 MHz differential)
  -- ============================================================================
  clk_gen: process
  begin
    clk_p <= '0';
    clk_n <= '1';
    wait for CLK_PERIOD / 2;
    clk_p <= '1';
    clk_n <= '0';
    wait for CLK_PERIOD / 2;
  end process clk_gen;

  -- ============================================================================
  -- Reset Generation
  -- ============================================================================
  rst_gen: process
  begin
    rst_n <= '0';
    wait for RESET_TIME_NS * 1 ns;
    rst_n <= '1';
    wait;
  end process rst_gen;

  -- ============================================================================
  -- Device Under Test: Top_wrapper (Vivado Block Design)
  -- ============================================================================
  uut: entity work.Top_wrapper
    port map (
      ecs_clk_in_clk_p => clk_p,
      ecs_clk_in_clk_n => clk_n,
      system_resetn    => rst_n,
      uart0_rxd        => uart_rxd,
      uart0_txd        => uart_txd
    );

  -- ============================================================================
  -- UART Receiver (logs to console and file)
  -- ============================================================================
  -- Note: The clock for UART receiver should match the CPU clock (100 MHz after PLL)
  -- The PLL divides 300 MHz down to 100 MHz for the CPU
  sim_rx_uart0: entity work.sim_uart_rx
    generic map (
      NAME => "tb.uart0_rx",
      FCLK => 100.0e6,  -- CPU runs at 100 MHz (300 MHz / 3)
      BAUD => BAUD_RATE
    )
    port map (
      clk => clk_p,
      rxd => uart_txd
    );

end architecture sim;

-- ================================================================================ --
-- Simulation UART Transmitter - Sends test commands to NEORV32 UART              --
-- -------------------------------------------------------------------------------- --
-- Part of the QPSK Triple Comparison Project                                      --
-- Licensed under the BSD-3-Clause license                                         --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity sim_uart_tx is
  generic (
    NAME : string := "uart_tx"; -- transmitter name for reporting
    FCLK : real   := 100.0e6;   -- clock speed of clk_i in Hz
    BAUD : real   := 115200.0   -- baud rate
  );
  port (
    clk       : in  std_ulogic; -- global clock
    rstn      : in  std_ulogic; -- global reset, async, active low
    txd       : out std_ulogic; -- serial UART TX data
    -- Control interface
    tx_data   : in  std_ulogic_vector(7 downto 0); -- data to transmit
    tx_valid  : in  std_ulogic; -- data valid, start transmission
    tx_ready  : out std_ulogic  -- ready for new data
  );
end entity sim_uart_tx;

architecture sim_uart_tx_rtl of sim_uart_tx is

  constant baud_val_c : real := FCLK / BAUD;

  type state_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
  signal state   : state_t := IDLE;
  signal sreg    : std_ulogic_vector(7 downto 0) := (others => '0');
  signal baudcnt : real := 0.0;
  signal bitcnt  : integer := 0;

begin

  tx_process: process(clk, rstn)
  begin
    if rstn = '0' then
      state    <= IDLE;
      txd      <= '1'; -- idle high
      tx_ready <= '1';
      sreg     <= (others => '0');
      baudcnt  <= 0.0;
      bitcnt   <= 0;
    elsif rising_edge(clk) then
      case state is

        when IDLE =>
          txd      <= '1'; -- idle high
          tx_ready <= '1';
          if tx_valid = '1' then
            sreg     <= tx_data;
            tx_ready <= '0';
            baudcnt  <= baud_val_c;
            state    <= START_BIT;
            report NAME & ": Sending byte 0x" & to_hstring(tx_data) &
                   " '" & character'val(to_integer(unsigned(tx_data))) & "'";
          end if;

        when START_BIT =>
          txd <= '0'; -- start bit
          if baudcnt <= 0.0 then
            baudcnt <= baud_val_c;
            bitcnt  <= 0;
            state   <= DATA_BITS;
          else
            baudcnt <= baudcnt - 1.0;
          end if;

        when DATA_BITS =>
          txd <= sreg(0); -- LSB first
          if baudcnt <= 0.0 then
            baudcnt <= baud_val_c;
            sreg    <= '0' & sreg(7 downto 1); -- shift right
            if bitcnt = 7 then
              state <= STOP_BIT;
            else
              bitcnt <= bitcnt + 1;
            end if;
          else
            baudcnt <= baudcnt - 1.0;
          end if;

        when STOP_BIT =>
          txd <= '1'; -- stop bit
          if baudcnt <= 0.0 then
            state <= IDLE;
          else
            baudcnt <= baudcnt - 1.0;
          end if;

      end case;
    end if;
  end process tx_process;

end architecture sim_uart_tx_rtl;

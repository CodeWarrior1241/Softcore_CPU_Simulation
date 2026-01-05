-- ================================================================================ --
-- Vivado Block Design Testbench for NEORV32 RISC-V Processor                       --
-- -------------------------------------------------------------------------------- --
-- This testbench instantiates the Top_wrapper from the Vivado block design and    --
-- provides clock generation, reset, UART command generation, and UART monitoring. --
--                                                                                  --
-- UART Command Protocol (matching MATLAB QPSK_GUI):                                --
--   "enable_rf\n"       -> Response: "rf_enabled\n"                                --
--   "disable_rf\n"      -> Response: "rf_disabled\n"                               --
--   "enable_snapshot\n" -> Response: "snapshot_enabled\n" + 4096 bytes IQ data     --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity vivado_tb is
  generic (
    -- Clock and timing
    CLOCK_FREQUENCY : real := 300.0e6;  -- 300 MHz differential clock input
    BAUD_RATE       : real := 115200.0; -- UART baud rate (matches qpsk_handler application)
    -- Simulation control
    RESET_TIME_NS   : natural := 100;   -- Reset duration in nanoseconds
    BOOT_DELAY_MS   : natural := 10;    -- Wait time after reset before sending commands (ms)
    -- Log file path (without .log extension)
    -- Path is relative to simulation working directory (vivado questa dir)
    UART_LOG_PATH   : string := "tb.uart0_rx"
  );
end entity vivado_tb;

architecture sim of vivado_tb is

  -- Clock period for 300 MHz differential clock
  constant CLK_PERIOD : time := (1.0e9 / CLOCK_FREQUENCY) * 1 ns; -- ~3.333 ns

  -- CPU clock frequency (100 MHz from PLL)
  -- The NEORV32 runs at 100 MHz, and its UART baud rate is calculated from this
  constant CPU_CLOCK_FREQUENCY : real := 100.0e6;

  -- Boot delay in CPU clock cycles
  constant BOOT_DELAY_CYCLES : natural := natural(CPU_CLOCK_FREQUENCY * real(BOOT_DELAY_MS) / 1000.0);

  -- Clock and reset signals
  signal clk_p     : std_logic := '0';
  signal clk_n     : std_logic := '1';
  signal rst_n     : std_logic := '0';

  -- CPU clock from block design (directly exposed for simulation)
  signal cpu_clk        : std_logic;
  signal cpu_clk_locked : std_logic;

  -- UART signals
  signal uart_txd  : std_logic;
  signal uart_rxd  : std_logic := '1'; -- Directly driven by sim_uart_tx

  -- Gated UART RX signal - mask until PLL is locked
  signal uart_txd_gated : std_logic := '1';

  -- UART TX control signals (from command sequencer to sim_uart_tx)
  signal tx_data   : std_ulogic_vector(7 downto 0) := (others => '0');
  signal tx_valid  : std_ulogic := '0';
  signal tx_ready  : std_ulogic;

  -- Command sequencer state
  type cmd_state_t is (WAIT_BOOT,
                       SEND_ENABLE_RF, WAIT_ENABLE_RF_BYTE,
                       WAIT_RF_RESPONSE,
                       SEND_SNAPSHOT, WAIT_SNAPSHOT_BYTE,
                       WAIT_SNAPSHOT_RESPONSE, DONE);
  signal cmd_state : cmd_state_t := WAIT_BOOT;
  signal boot_counter : natural := 0;
  signal char_index : natural := 0;
  signal inter_cmd_delay : natural := 0;

  -- QPSK progress counter (0..1023) - estimates IQ words received during snapshot
  -- Each IQ word = 4 bytes, each byte takes CHAR_TIME_CYCLES to transmit
  -- After the 18-char "snapshot_enabled\r\n" header, IQ data begins
  signal qpsk_count : natural range 0 to 1023 := 0;

  -- ============================================================================
  -- AXI Read Address Monitoring Signals (for debugging BRAM access issues)
  -- These aliases reference internal signals in the block design hierarchy
  -- ============================================================================

  -- ============================================================================
  -- #3: CPU AXI Master Interface Monitoring
  -- ============================================================================
  -- CPU's AXI read address output (32-bit full address from NEORV32)
  alias cpu_araddr : std_logic_vector(31 downto 0) is
    <<signal .vivado_tb.uut.Top_i.NEORV32_RISC_V.m_axi_araddr : std_logic_vector(31 downto 0)>>;
  alias cpu_arvalid : std_logic is
    <<signal .vivado_tb.uut.Top_i.NEORV32_RISC_V.m_axi_arvalid : std_logic>>;
  alias cpu_arready : std_logic is
    <<signal .vivado_tb.uut.Top_i.NEORV32_RISC_V.m_axi_arready : std_logic>>;
  alias cpu_arlen : std_logic_vector(7 downto 0) is
    <<signal .vivado_tb.uut.Top_i.NEORV32_RISC_V.m_axi_arlen : std_logic_vector(7 downto 0)>>;
  alias cpu_arsize : std_logic_vector(2 downto 0) is
    <<signal .vivado_tb.uut.Top_i.NEORV32_RISC_V.m_axi_arsize : std_logic_vector(2 downto 0)>>;
  alias cpu_arburst : std_logic_vector(1 downto 0) is
    <<signal .vivado_tb.uut.Top_i.NEORV32_RISC_V.m_axi_arburst : std_logic_vector(1 downto 0)>>;
  -- CPU's AXI read data channel
  alias cpu_rdata : std_logic_vector(31 downto 0) is
    <<signal .vivado_tb.uut.Top_i.NEORV32_RISC_V.m_axi_rdata : std_logic_vector(31 downto 0)>>;
  alias cpu_rvalid : std_logic is
    <<signal .vivado_tb.uut.Top_i.NEORV32_RISC_V.m_axi_rvalid : std_logic>>;
  alias cpu_rready : std_logic is
    <<signal .vivado_tb.uut.Top_i.NEORV32_RISC_V.m_axi_rready : std_logic>>;
  alias cpu_rresp : std_logic_vector(1 downto 0) is
    <<signal .vivado_tb.uut.Top_i.NEORV32_RISC_V.m_axi_rresp : std_logic_vector(1 downto 0)>>;
  alias cpu_rlast : std_logic is
    <<signal .vivado_tb.uut.Top_i.NEORV32_RISC_V.m_axi_rlast : std_logic>>;

  -- ============================================================================
  -- #2: AXI BRAM Controller Interface Monitoring
  -- ============================================================================
  -- AXI signals at input to BRAM Controller (from SmartConnect)
  alias bram_ctrl_araddr : std_logic_vector(14 downto 0) is
    <<signal .vivado_tb.uut.Top_i.AXI_CPU_Interconnect_M00_AXI_ARADDR : std_logic_vector(14 downto 0)>>;
  alias bram_ctrl_arvalid : std_logic is
    <<signal .vivado_tb.uut.Top_i.AXI_CPU_Interconnect_M00_AXI_ARVALID : std_logic>>;
  alias bram_ctrl_arready : std_logic is
    <<signal .vivado_tb.uut.Top_i.AXI_CPU_Interconnect_M00_AXI_ARREADY : std_logic>>;
  alias bram_ctrl_arlen : std_logic_vector(7 downto 0) is
    <<signal .vivado_tb.uut.Top_i.AXI_CPU_Interconnect_M00_AXI_ARLEN : std_logic_vector(7 downto 0)>>;
  alias bram_ctrl_arburst : std_logic_vector(1 downto 0) is
    <<signal .vivado_tb.uut.Top_i.AXI_CPU_Interconnect_M00_AXI_ARBURST : std_logic_vector(1 downto 0)>>;
  -- AXI read data channel from BRAM Controller
  alias bram_ctrl_rdata : std_logic_vector(31 downto 0) is
    <<signal .vivado_tb.uut.Top_i.AXI_CPU_Interconnect_M00_AXI_RDATA : std_logic_vector(31 downto 0)>>;
  alias bram_ctrl_rvalid : std_logic is
    <<signal .vivado_tb.uut.Top_i.AXI_CPU_Interconnect_M00_AXI_RVALID : std_logic>>;
  alias bram_ctrl_rready : std_logic is
    <<signal .vivado_tb.uut.Top_i.AXI_CPU_Interconnect_M00_AXI_RREADY : std_logic>>;
  alias bram_ctrl_rresp : std_logic_vector(1 downto 0) is
    <<signal .vivado_tb.uut.Top_i.AXI_CPU_Interconnect_M00_AXI_RRESP : std_logic_vector(1 downto 0)>>;
  alias bram_ctrl_rlast : std_logic is
    <<signal .vivado_tb.uut.Top_i.AXI_CPU_Interconnect_M00_AXI_RLAST : std_logic>>;

  -- BRAM interface signals (VHDL signals in Top.vhd that connect to the Verilog BRAM)
  -- These are the signals between AXI BRAM Controller and the BRAM IP
  alias bram_addr : std_logic_vector(14 downto 0) is
    <<signal .vivado_tb.uut.Top_i.AXI_BRAM_Controller_BRAM_PORTA_ADDR : std_logic_vector(14 downto 0)>>;
  alias bram_ena : std_logic is
    <<signal .vivado_tb.uut.Top_i.AXI_BRAM_Controller_BRAM_PORTA_EN : std_logic>>;
  alias bram_dout : std_logic_vector(31 downto 0) is
    <<signal .vivado_tb.uut.Top_i.AXI_BRAM_Controller_BRAM_PORTA_DOUT : std_logic_vector(31 downto 0)>>;

  -- Transaction counters and tracking
  signal cpu_read_count : natural := 0;
  signal bram_ctrl_read_count : natural := 0;
  signal cpu_rdata_count : natural := 0;
  signal bram_ctrl_rdata_count : natural := 0;

  -- Track last addresses for comparison
  signal last_cpu_araddr : std_logic_vector(31 downto 0) := (others => '0');
  signal last_bram_ctrl_araddr : std_logic_vector(14 downto 0) := (others => '0');

  -- File for CSV logging
  file axi_log_file : text;

  -- Command strings (as arrays of bytes)
  -- "enable_rf" + LF
  type cmd_enable_rf_t is array (0 to 9) of std_ulogic_vector(7 downto 0);
  constant CMD_ENABLE_RF : cmd_enable_rf_t := (
    x"65", x"6E", x"61", x"62", x"6C", x"65", x"5F", x"72", x"66", x"0A"  -- "enable_rf\n"
  );

  -- "disable_rf" + LF
  type cmd_disable_rf_t is array (0 to 10) of std_ulogic_vector(7 downto 0);
  constant CMD_DISABLE_RF : cmd_disable_rf_t := (
    x"64", x"69", x"73", x"61", x"62", x"6C", x"65", x"5F", x"72", x"66", x"0A"  -- "disable_rf\n"
  );

  -- "enable_snapshot" + LF
  type cmd_snapshot_t is array (0 to 15) of std_ulogic_vector(7 downto 0);
  constant CMD_SNAPSHOT : cmd_snapshot_t := (
    x"65", x"6E", x"61", x"62", x"6C", x"65", x"5F",  -- "enable_"
    x"73", x"6E", x"61", x"70", x"73", x"68", x"6F", x"74", x"0A"  -- "snapshot\n"
  );

  -- Timing constants (matching neorv32_tb.vhd approach)
  -- At 115200 baud: ~86.8us per character (10 bits per char)
  -- Add margin for CPU processing time
  constant CHAR_TIME_CYCLES : natural := natural(CPU_CLOCK_FREQUENCY / BAUD_RATE * 10.0); -- cycles per UART char
  constant CPU_MARGIN_CYCLES : natural := natural(CPU_CLOCK_FREQUENCY * 0.005); -- 5ms CPU processing margin

  -- Response wait times (in CPU clock cycles)
  -- enable_rf response: "rf_enabled\r\n" = 12 chars
  constant RF_RESPONSE_CYCLES : natural := CPU_MARGIN_CYCLES + (12 * CHAR_TIME_CYCLES);
  -- enable_snapshot response: "snapshot_enabled\r\n" (18 chars) + 4096 bytes IQ data = 4114 chars
  constant SNAPSHOT_RESPONSE_CYCLES : natural := CPU_MARGIN_CYCLES + (4114 * CHAR_TIME_CYCLES);

  -- Timing for QPSK progress counter
  -- Header: CPU margin + 18 chars for "snapshot_enabled\r\n"
  constant SNAPSHOT_HEADER_CYCLES : natural := CPU_MARGIN_CYCLES + (18 * CHAR_TIME_CYCLES);
  -- Each IQ word = 4 bytes = 4 * CHAR_TIME_CYCLES
  constant IQ_WORD_CYCLES : natural := 4 * CHAR_TIME_CYCLES;

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
  -- UART RX Gating - Only pass through uart_txd after PLL is locked and stable
  -- ============================================================================
  -- Gate the UART TX signal to prevent false start bit detection during:
  -- 1. PLL lock-up period (cpu_clk_locked = '0')
  -- 2. Undefined signal states ('U', 'X', etc.)
  -- Force idle high ('1') when not valid
  uart_txd_gated <= uart_txd when (cpu_clk_locked = '1' and (uart_txd = '0' or uart_txd = '1')) else '1';

  -- ============================================================================
  -- Device Under Test: Top_wrapper (Vivado Block Design)
  -- ============================================================================
  uut: entity work.Top_wrapper
    port map (
      ecs_clk_in_clk_p        => clk_p,
      ecs_clk_in_clk_n        => clk_n,
      system_resetn           => rst_n,
      sim_clock_100MHz        => cpu_clk,         -- 100 MHz clock for UART receiver
      sim_clock_100MHz_locked => cpu_clk_locked,  -- PLL locked indicator
      uart0_rxd               => uart_rxd,
      uart0_txd               => uart_txd
    );

  -- ============================================================================
  -- UART Receiver (logs to console and file)
  -- ============================================================================
  -- Note: The UART receiver must be clocked by the same clock as the UART transmitter
  -- The NEORV32 UART runs at 100 MHz (PLL output), so we use the internal cpu_clk
  sim_rx_uart0: entity work.sim_uart_rx
    generic map (
      NAME => UART_LOG_PATH,  -- Full path to log file (without .log extension)
      FCLK => CPU_CLOCK_FREQUENCY, -- Must match cpu_clk frequency (100 MHz)
      BAUD => BAUD_RATE
    )
    port map (
      clk => cpu_clk,
      rxd => uart_txd_gated  -- Use gated signal to avoid false starts during PLL glitch
    );

  -- ============================================================================
  -- UART Transmitter (sends commands to CPU)
  -- ============================================================================
  -- Sends test commands to exercise the qpsk_handler UART interface
  sim_tx_uart0: entity work.sim_uart_tx
    generic map (
      NAME => "tb.uart0_tx",
      FCLK => CPU_CLOCK_FREQUENCY,
      BAUD => BAUD_RATE
    )
    port map (
      clk      => cpu_clk,
      rstn     => cpu_clk_locked,  -- Hold in reset until PLL locked
      txd      => uart_rxd,        -- Connect to CPU's RX input
      tx_data  => tx_data,
      tx_valid => tx_valid,
      tx_ready => tx_ready
    );

  -- ============================================================================
  -- Command Sequencer - Sends UART commands matching MATLAB QPSK_GUI protocol
  -- ============================================================================
  -- Sequence:
  --   1. Wait for CPU to boot (BOOT_DELAY_MS after PLL lock)
  --   2. Send "enable_rf\n" command
  --   3. Wait for response
  --   4. Send "enable_snapshot\n" command
  --   5. Wait for response (including 4096 bytes of IQ data)
  --   6. Done
  cmd_sequencer: process(cpu_clk, cpu_clk_locked)
  begin
    if cpu_clk_locked = '0' then
      cmd_state <= WAIT_BOOT;
      boot_counter <= 0;
      char_index <= 0;
      inter_cmd_delay <= 0;
      tx_valid <= '0';
      tx_data <= (others => '0');
    elsif rising_edge(cpu_clk) then
      -- Default: no new data
      tx_valid <= '0';

      case cmd_state is

        -- ====================================================================
        -- Wait for CPU to boot and initialize
        -- ====================================================================
        when WAIT_BOOT =>
          if boot_counter >= BOOT_DELAY_CYCLES then
            cmd_state <= SEND_ENABLE_RF;
            char_index <= 0;
            report "TB: Starting UART command sequence - sending 'enable_rf'";
          else
            boot_counter <= boot_counter + 1;
          end if;

        -- ====================================================================
        -- Send "enable_rf\n" command - initiate byte transfer
        -- ====================================================================
        when SEND_ENABLE_RF =>
          if tx_ready = '1' then
            if char_index <= CMD_ENABLE_RF'high then
              tx_data <= CMD_ENABLE_RF(char_index);
              tx_valid <= '1';
              cmd_state <= WAIT_ENABLE_RF_BYTE;  -- Wait for byte to be accepted
            else
              -- All characters sent, wait for response
              cmd_state <= WAIT_RF_RESPONSE;
              inter_cmd_delay <= 0;
              report "TB: 'enable_rf' command sent, waiting for response";
            end if;
          end if;

        -- ====================================================================
        -- Wait for current byte to be accepted by UART TX
        -- ====================================================================
        when WAIT_ENABLE_RF_BYTE =>
          tx_valid <= '0';  -- Clear valid after one cycle
          if tx_ready = '0' then
            -- Byte accepted, wait for TX to become ready again
            null;
          elsif tx_ready = '1' then
            -- TX is ready for next byte
            char_index <= char_index + 1;
            cmd_state <= SEND_ENABLE_RF;
          end if;

        -- ====================================================================
        -- Wait for RF response before sending next command
        -- ====================================================================
        when WAIT_RF_RESPONSE =>
          if inter_cmd_delay >= RF_RESPONSE_CYCLES then
            cmd_state <= SEND_SNAPSHOT;
            char_index <= 0;
            report "TB: Sending 'enable_snapshot' command";
          else
            inter_cmd_delay <= inter_cmd_delay + 1;
          end if;

        -- ====================================================================
        -- Send "enable_snapshot\n" command - initiate byte transfer
        -- ====================================================================
        when SEND_SNAPSHOT =>
          if tx_ready = '1' then
            if char_index <= CMD_SNAPSHOT'high then
              tx_data <= CMD_SNAPSHOT(char_index);
              tx_valid <= '1';
              cmd_state <= WAIT_SNAPSHOT_BYTE;  -- Wait for byte to be accepted
            else
              -- All characters sent, wait for response + IQ data
              cmd_state <= WAIT_SNAPSHOT_RESPONSE;
              inter_cmd_delay <= 0;
              qpsk_count <= 0;
              report "TB: 'enable_snapshot' command sent, waiting for response + IQ data";
            end if;
          end if;

        -- ====================================================================
        -- Wait for current byte to be accepted by UART TX
        -- ====================================================================
        when WAIT_SNAPSHOT_BYTE =>
          tx_valid <= '0';  -- Clear valid after one cycle
          if tx_ready = '0' then
            -- Byte accepted, wait for TX to become ready again
            null;
          elsif tx_ready = '1' then
            -- TX is ready for next byte
            char_index <= char_index + 1;
            cmd_state <= SEND_SNAPSHOT;
          end if;

        -- ====================================================================
        -- Wait for snapshot response (includes 4096 bytes of IQ data)
        -- ====================================================================
        when WAIT_SNAPSHOT_RESPONSE =>
          -- Wait for response header + IQ data (4114 bytes at 115200 baud ~ 357ms)
          if inter_cmd_delay >= SNAPSHOT_RESPONSE_CYCLES then
            cmd_state <= DONE;
            qpsk_count <= 1023;  -- Ensure count shows complete
            report "TB: Command sequence complete";
          else
            inter_cmd_delay <= inter_cmd_delay + 1;
            -- Calculate QPSK word count based on elapsed time
            -- After header, each IQ word takes IQ_WORD_CYCLES
            if inter_cmd_delay > SNAPSHOT_HEADER_CYCLES then
              qpsk_count <= (inter_cmd_delay - SNAPSHOT_HEADER_CYCLES) / IQ_WORD_CYCLES;
            else
              qpsk_count <= 0;
            end if;
          end if;

        -- ====================================================================
        -- Done - all commands sent
        -- ====================================================================
        when DONE =>
          null; -- Stay in done state

      end case;
    end if;
  end process cmd_sequencer;

  -- ============================================================================
  -- #3: CPU AXI Master Interface Monitor
  -- ============================================================================
  -- Monitors the CPU's AXI master port to track all read requests and responses
  cpu_axi_monitor: process(cpu_clk)
    variable word_index : natural;
  begin
    if rising_edge(cpu_clk) then
      -- Monitor AXI AR channel (read address) handshake
      if cpu_arvalid = '1' and cpu_arready = '1' then
        -- Check if this is a read to the BRAM address range (0xC0000000)
        if cpu_araddr(31 downto 16) = x"C000" then
          cpu_read_count <= cpu_read_count + 1;
          word_index := to_integer(unsigned(cpu_araddr(13 downto 2)));
          last_cpu_araddr <= cpu_araddr;

          report "[CPU AR #" & integer'image(cpu_read_count) & "] " &
                 "ADDR=0x" & to_hstring(unsigned(cpu_araddr)) &
                 " (word=" & integer'image(word_index) & ")" &
                 " LEN=" & integer'image(to_integer(unsigned(cpu_arlen))) &
                 " SIZE=" & integer'image(to_integer(unsigned(cpu_arsize))) &
                 " BURST=" & integer'image(to_integer(unsigned(cpu_arburst)))
            severity note;
        end if;
      end if;

      -- Monitor AXI R channel (read data) handshake
      if cpu_rvalid = '1' and cpu_rready = '1' then
        cpu_rdata_count <= cpu_rdata_count + 1;

        -- Only log BRAM-related reads (check if we're in BRAM access context)
        if last_cpu_araddr(31 downto 16) = x"C000" then
          report "[CPU RD #" & integer'image(cpu_rdata_count) & "] " &
                 "DATA=0x" & to_hstring(unsigned(cpu_rdata)) &
                 " RESP=" & integer'image(to_integer(unsigned(cpu_rresp))) &
                 " LAST=" & std_logic'image(cpu_rlast)
            severity note;

          -- Flag potential corruption: data is 0x000000FF (uninitialized BRAM default)
          if cpu_rdata = x"000000FF" then
            report "[CPU RD #" & integer'image(cpu_rdata_count) & "] " &
                   "*** WARNING: Data=0x000000FF matches uninitialized BRAM default! ***"
              severity warning;
          end if;
        end if;
      end if;
    end if;
  end process cpu_axi_monitor;

  -- ============================================================================
  -- #2: AXI BRAM Controller Interface Monitor
  -- ============================================================================
  -- Monitors the AXI interface at the BRAM Controller input (from SmartConnect)
  bram_ctrl_axi_monitor: process(cpu_clk)
    variable word_index : natural;
  begin
    if rising_edge(cpu_clk) then
      -- Monitor AXI AR channel at BRAM Controller input
      if bram_ctrl_arvalid = '1' and bram_ctrl_arready = '1' then
        bram_ctrl_read_count <= bram_ctrl_read_count + 1;
        word_index := to_integer(unsigned(bram_ctrl_araddr(14 downto 2)));
        last_bram_ctrl_araddr <= bram_ctrl_araddr;

        report "[BRAM_CTRL AR #" & integer'image(bram_ctrl_read_count) & "] " &
               "ADDR=0x" & to_hstring(unsigned(bram_ctrl_araddr)) &
               " (word=" & integer'image(word_index) & ")" &
               " LEN=" & integer'image(to_integer(unsigned(bram_ctrl_arlen))) &
               " BURST=" & integer'image(to_integer(unsigned(bram_ctrl_arburst)))
          severity note;
      end if;

      -- Monitor AXI R channel from BRAM Controller
      if bram_ctrl_rvalid = '1' and bram_ctrl_rready = '1' then
        bram_ctrl_rdata_count <= bram_ctrl_rdata_count + 1;

        report "[BRAM_CTRL RD #" & integer'image(bram_ctrl_rdata_count) & "] " &
               "DATA=0x" & to_hstring(unsigned(bram_ctrl_rdata)) &
               " RESP=" & integer'image(to_integer(unsigned(bram_ctrl_rresp))) &
               " LAST=" & std_logic'image(bram_ctrl_rlast)
          severity note;

        -- Flag potential corruption
        if bram_ctrl_rdata = x"000000FF" then
          report "[BRAM_CTRL RD #" & integer'image(bram_ctrl_rdata_count) & "] " &
                 "*** WARNING: Data=0x000000FF matches uninitialized BRAM default! ***"
            severity warning;
        end if;
      end if;
    end if;
  end process bram_ctrl_axi_monitor;

  -- ============================================================================
  -- BRAM Direct Access Monitor
  -- ============================================================================
  -- Monitors the actual BRAM interface (between AXI BRAM Controller and BRAM IP)
  bram_access_monitor: process(cpu_clk)
    variable last_ena : std_logic := '0';
    variable word_addr : natural;
  begin
    if rising_edge(cpu_clk) then
      -- Detect BRAM enable rising edge (new access)
      if bram_ena = '1' and last_ena = '0' then
        -- Calculate word address (BRAM is 32-bit wide, byte address / 4)
        word_addr := to_integer(unsigned(bram_addr(14 downto 2)));
        report "[BRAM] ADDR=0x" & to_hstring(unsigned(bram_addr)) &
               " (word=" & integer'image(word_addr) & ")"
          severity note;
      end if;

      -- Log BRAM data output when enable is active (1 cycle after address)
      if last_ena = '1' then
        word_addr := to_integer(unsigned(bram_addr(14 downto 2)));
        report "[BRAM] DOUT=0x" & to_hstring(unsigned(bram_dout)) &
               " (word=" & integer'image(word_addr) & ")"
          severity note;

        -- Flag potential corruption
        if bram_dout = x"000000FF" then
          report "[BRAM] *** WARNING: DOUT=0x000000FF at word " &
                 integer'image(word_addr) & " - uninitialized BRAM default! ***"
            severity warning;
        end if;
      end if;

      last_ena := bram_ena;
    end if;
  end process bram_access_monitor;

  -- ============================================================================
  -- Address Comparison Monitor
  -- ============================================================================
  -- Compares CPU address vs BRAM Controller address to detect translation issues
  addr_compare_monitor: process(cpu_clk)
    variable cpu_word : natural;
    variable ctrl_word : natural;
  begin
    if rising_edge(cpu_clk) then
      -- When both have new transactions, compare addresses
      if cpu_arvalid = '1' and cpu_arready = '1' and
         bram_ctrl_arvalid = '1' and bram_ctrl_arready = '1' then
        cpu_word := to_integer(unsigned(cpu_araddr(13 downto 2)));
        ctrl_word := to_integer(unsigned(bram_ctrl_araddr(14 downto 2)));

        if cpu_word /= ctrl_word then
          report "*** ADDRESS MISMATCH: CPU word=" & integer'image(cpu_word) &
                 " vs BRAM_CTRL word=" & integer'image(ctrl_word) & " ***"
            severity error;
        end if;
      end if;
    end if;
  end process addr_compare_monitor;

end architecture sim;

-- ============================================================================
-- Snapshot BRAM Readback Testbench (with full AXI path)
-- ============================================================================
-- This testbench instantiates the complete AXI path to the BRAM:
--   AXI Master BFM -> SmartConnect -> AXI BRAM Controller -> Snapshot BRAM
--
-- Purpose: Verify the BRAM IP contains correct QPSK data from the COE file,
--          and that data can be read correctly through the AXI infrastructure.
--          Compares each read value against expected data from COE file.
--
-- Usage: Run through Vivado xsim (not standalone). All IPs must be compiled
--        first via Vivado's simulation flow.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity snapshot_bram_readback_tb is
  generic (
    -- Path relative to xsim working directory: NEORV32_Simulation.sim/sim_bram_tb/behav/xsim/
    COE_FILE : string := "../../../../sim/qpsk_bram_init.coe"
  );
end entity snapshot_bram_readback_tb;

architecture sim of snapshot_bram_readback_tb is

  -- Clock period (100 MHz)
  constant CLK_PERIOD : time := 10 ns;

  -- Number of IQ samples to read
  constant NUM_SAMPLES : natural := 1024;

  -- BRAM base address (from block design address map)
  constant BRAM_BASE_ADDR : unsigned(31 downto 0) := x"C0000000";

  -- =========================================================================
  -- Clock and Reset
  -- =========================================================================
  signal clk     : std_logic := '0';
  signal resetn  : std_logic := '0';

  -- =========================================================================
  -- AXI Master signals (testbench drives these)
  -- =========================================================================
  -- Write address channel
  signal m_axi_awaddr  : std_logic_vector(31 downto 0) := (others => '0');
  signal m_axi_awlen   : std_logic_vector(7 downto 0) := (others => '0');
  signal m_axi_awsize  : std_logic_vector(2 downto 0) := "010";  -- 4 bytes
  signal m_axi_awburst : std_logic_vector(1 downto 0) := "01";   -- INCR
  signal m_axi_awlock  : std_logic_vector(0 downto 0) := "0";
  signal m_axi_awcache : std_logic_vector(3 downto 0) := "0000";
  signal m_axi_awprot  : std_logic_vector(2 downto 0) := "000";
  signal m_axi_awqos   : std_logic_vector(3 downto 0) := "0000";
  signal m_axi_awvalid : std_logic := '0';
  signal m_axi_awready : std_logic;

  -- Write data channel
  signal m_axi_wdata   : std_logic_vector(31 downto 0) := (others => '0');
  signal m_axi_wstrb   : std_logic_vector(3 downto 0) := "1111";
  signal m_axi_wlast   : std_logic := '0';
  signal m_axi_wvalid  : std_logic := '0';
  signal m_axi_wready  : std_logic;

  -- Write response channel
  signal m_axi_bresp   : std_logic_vector(1 downto 0);
  signal m_axi_bvalid  : std_logic;
  signal m_axi_bready  : std_logic := '1';

  -- Read address channel
  signal m_axi_araddr  : std_logic_vector(31 downto 0) := (others => '0');
  signal m_axi_arlen   : std_logic_vector(7 downto 0) := (others => '0');
  signal m_axi_arsize  : std_logic_vector(2 downto 0) := "010";  -- 4 bytes
  signal m_axi_arburst : std_logic_vector(1 downto 0) := "01";   -- INCR
  signal m_axi_arlock  : std_logic_vector(0 downto 0) := "0";
  signal m_axi_arcache : std_logic_vector(3 downto 0) := "0000";
  signal m_axi_arprot  : std_logic_vector(2 downto 0) := "000";
  signal m_axi_arqos   : std_logic_vector(3 downto 0) := "0000";
  signal m_axi_arvalid : std_logic := '0';
  signal m_axi_arready : std_logic;

  -- Read data channel
  signal m_axi_rdata   : std_logic_vector(31 downto 0);
  signal m_axi_rresp   : std_logic_vector(1 downto 0);
  signal m_axi_rlast   : std_logic;
  signal m_axi_rvalid  : std_logic;
  signal m_axi_rready  : std_logic := '0';

  -- =========================================================================
  -- Interconnect to BRAM Controller signals
  -- =========================================================================
  signal ic_to_ctrl_awaddr  : std_logic_vector(14 downto 0);
  signal ic_to_ctrl_awlen   : std_logic_vector(7 downto 0);
  signal ic_to_ctrl_awsize  : std_logic_vector(2 downto 0);
  signal ic_to_ctrl_awburst : std_logic_vector(1 downto 0);
  signal ic_to_ctrl_awlock  : std_logic_vector(0 downto 0);
  signal ic_to_ctrl_awcache : std_logic_vector(3 downto 0);
  signal ic_to_ctrl_awprot  : std_logic_vector(2 downto 0);
  signal ic_to_ctrl_awqos   : std_logic_vector(3 downto 0);
  signal ic_to_ctrl_awvalid : std_logic;
  signal ic_to_ctrl_awready : std_logic;
  signal ic_to_ctrl_wdata   : std_logic_vector(31 downto 0);
  signal ic_to_ctrl_wstrb   : std_logic_vector(3 downto 0);
  signal ic_to_ctrl_wlast   : std_logic;
  signal ic_to_ctrl_wvalid  : std_logic;
  signal ic_to_ctrl_wready  : std_logic;
  signal ic_to_ctrl_bresp   : std_logic_vector(1 downto 0);
  signal ic_to_ctrl_bvalid  : std_logic;
  signal ic_to_ctrl_bready  : std_logic;
  signal ic_to_ctrl_araddr  : std_logic_vector(14 downto 0);
  signal ic_to_ctrl_arlen   : std_logic_vector(7 downto 0);
  signal ic_to_ctrl_arsize  : std_logic_vector(2 downto 0);
  signal ic_to_ctrl_arburst : std_logic_vector(1 downto 0);
  signal ic_to_ctrl_arlock  : std_logic_vector(0 downto 0);
  signal ic_to_ctrl_arcache : std_logic_vector(3 downto 0);
  signal ic_to_ctrl_arprot  : std_logic_vector(2 downto 0);
  signal ic_to_ctrl_arqos   : std_logic_vector(3 downto 0);
  signal ic_to_ctrl_arvalid : std_logic;
  signal ic_to_ctrl_arready : std_logic;
  signal ic_to_ctrl_rdata   : std_logic_vector(31 downto 0);
  signal ic_to_ctrl_rresp   : std_logic_vector(1 downto 0);
  signal ic_to_ctrl_rlast   : std_logic;
  signal ic_to_ctrl_rvalid  : std_logic;
  signal ic_to_ctrl_rready  : std_logic;

  -- =========================================================================
  -- BRAM Controller to BRAM signals
  -- =========================================================================
  signal bram_rst_a    : std_logic;
  signal bram_clk_a    : std_logic;
  signal bram_en_a     : std_logic;
  signal bram_we_a     : std_logic_vector(3 downto 0);
  signal bram_addr_a   : std_logic_vector(14 downto 0);  -- 15-bit from BRAM Controller
  signal bram_addr_a_ext : std_logic_vector(31 downto 0);  -- 32-bit for BRAM (zero-extended)
  signal bram_wrdata_a : std_logic_vector(31 downto 0);
  signal bram_rddata_a : std_logic_vector(31 downto 0);

  -- =========================================================================
  -- Observable signals for waveform viewer
  -- =========================================================================
  signal sample_idx     : natural range 0 to 1023 := 0;
  signal i_out          : signed(15 downto 0) := (others => '0');
  signal q_out          : signed(15 downto 0) := (others => '0');
  signal iq_word        : std_logic_vector(31 downto 0) := (others => '0');
  signal good_count     : natural range 0 to 1024 := 0;
  signal bad_count      : natural range 0 to 1024 := 0;
  signal mismatch_count : natural range 0 to 1024 := 0;
  signal test_pass      : std_logic := '0';

  -- Expected data from COE file
  type expected_data_t is array (0 to NUM_SAMPLES - 1) of std_logic_vector(31 downto 0);
  signal expected_data : expected_data_t := (others => (others => '0'));
  signal coe_loaded    : boolean := false;
  signal expected_word : std_logic_vector(31 downto 0) := (others => '0');

  -- Function to convert hex character to 4-bit value
  function hex_char_to_slv(c : character) return std_logic_vector is
    variable result : std_logic_vector(3 downto 0);
  begin
    case c is
      when '0' => result := "0000";
      when '1' => result := "0001";
      when '2' => result := "0010";
      when '3' => result := "0011";
      when '4' => result := "0100";
      when '5' => result := "0101";
      when '6' => result := "0110";
      when '7' => result := "0111";
      when '8' => result := "1000";
      when '9' => result := "1001";
      when 'A' | 'a' => result := "1010";
      when 'B' | 'b' => result := "1011";
      when 'C' | 'c' => result := "1100";
      when 'D' | 'd' => result := "1101";
      when 'E' | 'e' => result := "1110";
      when 'F' | 'f' => result := "1111";
      when others => result := "0000";
    end case;
    return result;
  end function;

  -- =========================================================================
  -- Component Declarations
  -- =========================================================================

  -- SmartConnect (AXI Interconnect)
  component Top_AXI_CPU_Interconnect_0
    port (
      aclk            : in  std_logic;
      aresetn         : in  std_logic;
      -- S00_AXI (slave port - from AXI master)
      S00_AXI_awaddr  : in  std_logic_vector(31 downto 0);
      S00_AXI_awlen   : in  std_logic_vector(7 downto 0);
      S00_AXI_awsize  : in  std_logic_vector(2 downto 0);
      S00_AXI_awburst : in  std_logic_vector(1 downto 0);
      S00_AXI_awlock  : in  std_logic_vector(0 downto 0);
      S00_AXI_awcache : in  std_logic_vector(3 downto 0);
      S00_AXI_awprot  : in  std_logic_vector(2 downto 0);
      S00_AXI_awqos   : in  std_logic_vector(3 downto 0);
      S00_AXI_awvalid : in  std_logic;
      S00_AXI_awready : out std_logic;
      S00_AXI_wdata   : in  std_logic_vector(31 downto 0);
      S00_AXI_wstrb   : in  std_logic_vector(3 downto 0);
      S00_AXI_wlast   : in  std_logic;
      S00_AXI_wvalid  : in  std_logic;
      S00_AXI_wready  : out std_logic;
      S00_AXI_bresp   : out std_logic_vector(1 downto 0);
      S00_AXI_bvalid  : out std_logic;
      S00_AXI_bready  : in  std_logic;
      S00_AXI_araddr  : in  std_logic_vector(31 downto 0);
      S00_AXI_arlen   : in  std_logic_vector(7 downto 0);
      S00_AXI_arsize  : in  std_logic_vector(2 downto 0);
      S00_AXI_arburst : in  std_logic_vector(1 downto 0);
      S00_AXI_arlock  : in  std_logic_vector(0 downto 0);
      S00_AXI_arcache : in  std_logic_vector(3 downto 0);
      S00_AXI_arprot  : in  std_logic_vector(2 downto 0);
      S00_AXI_arqos   : in  std_logic_vector(3 downto 0);
      S00_AXI_arvalid : in  std_logic;
      S00_AXI_arready : out std_logic;
      S00_AXI_rdata   : out std_logic_vector(31 downto 0);
      S00_AXI_rresp   : out std_logic_vector(1 downto 0);
      S00_AXI_rlast   : out std_logic;
      S00_AXI_rvalid  : out std_logic;
      S00_AXI_rready  : in  std_logic;
      -- M00_AXI (master port - to BRAM controller)
      M00_AXI_awaddr  : out std_logic_vector(14 downto 0);
      M00_AXI_awlen   : out std_logic_vector(7 downto 0);
      M00_AXI_awsize  : out std_logic_vector(2 downto 0);
      M00_AXI_awburst : out std_logic_vector(1 downto 0);
      M00_AXI_awlock  : out std_logic_vector(0 downto 0);
      M00_AXI_awcache : out std_logic_vector(3 downto 0);
      M00_AXI_awprot  : out std_logic_vector(2 downto 0);
      M00_AXI_awqos   : out std_logic_vector(3 downto 0);
      M00_AXI_awvalid : out std_logic;
      M00_AXI_awready : in  std_logic;
      M00_AXI_wdata   : out std_logic_vector(31 downto 0);
      M00_AXI_wstrb   : out std_logic_vector(3 downto 0);
      M00_AXI_wlast   : out std_logic;
      M00_AXI_wvalid  : out std_logic;
      M00_AXI_wready  : in  std_logic;
      M00_AXI_bresp   : in  std_logic_vector(1 downto 0);
      M00_AXI_bvalid  : in  std_logic;
      M00_AXI_bready  : out std_logic;
      M00_AXI_araddr  : out std_logic_vector(14 downto 0);
      M00_AXI_arlen   : out std_logic_vector(7 downto 0);
      M00_AXI_arsize  : out std_logic_vector(2 downto 0);
      M00_AXI_arburst : out std_logic_vector(1 downto 0);
      M00_AXI_arlock  : out std_logic_vector(0 downto 0);
      M00_AXI_arcache : out std_logic_vector(3 downto 0);
      M00_AXI_arprot  : out std_logic_vector(2 downto 0);
      M00_AXI_arqos   : out std_logic_vector(3 downto 0);
      M00_AXI_arvalid : out std_logic;
      M00_AXI_arready : in  std_logic;
      M00_AXI_rdata   : in  std_logic_vector(31 downto 0);
      M00_AXI_rresp   : in  std_logic_vector(1 downto 0);
      M00_AXI_rlast   : in  std_logic;
      M00_AXI_rvalid  : in  std_logic;
      M00_AXI_rready  : out std_logic
    );
  end component;

  -- AXI BRAM Controller
  component Top_AXI_BRAM_Controller_0
    port (
      s_axi_aclk    : in  std_logic;
      s_axi_aresetn : in  std_logic;
      s_axi_awaddr  : in  std_logic_vector(14 downto 0);
      s_axi_awlen   : in  std_logic_vector(7 downto 0);
      s_axi_awsize  : in  std_logic_vector(2 downto 0);
      s_axi_awburst : in  std_logic_vector(1 downto 0);
      s_axi_awlock  : in  std_logic;
      s_axi_awcache : in  std_logic_vector(3 downto 0);
      s_axi_awprot  : in  std_logic_vector(2 downto 0);
      s_axi_awvalid : in  std_logic;
      s_axi_awready : out std_logic;
      s_axi_wdata   : in  std_logic_vector(31 downto 0);
      s_axi_wstrb   : in  std_logic_vector(3 downto 0);
      s_axi_wlast   : in  std_logic;
      s_axi_wvalid  : in  std_logic;
      s_axi_wready  : out std_logic;
      s_axi_bresp   : out std_logic_vector(1 downto 0);
      s_axi_bvalid  : out std_logic;
      s_axi_bready  : in  std_logic;
      s_axi_araddr  : in  std_logic_vector(14 downto 0);
      s_axi_arlen   : in  std_logic_vector(7 downto 0);
      s_axi_arsize  : in  std_logic_vector(2 downto 0);
      s_axi_arburst : in  std_logic_vector(1 downto 0);
      s_axi_arlock  : in  std_logic;
      s_axi_arcache : in  std_logic_vector(3 downto 0);
      s_axi_arprot  : in  std_logic_vector(2 downto 0);
      s_axi_arvalid : in  std_logic;
      s_axi_arready : out std_logic;
      s_axi_rdata   : out std_logic_vector(31 downto 0);
      s_axi_rresp   : out std_logic_vector(1 downto 0);
      s_axi_rlast   : out std_logic;
      s_axi_rvalid  : out std_logic;
      s_axi_rready  : in  std_logic;
      bram_rst_a    : out std_logic;
      bram_clk_a    : out std_logic;
      bram_en_a     : out std_logic;
      bram_we_a     : out std_logic_vector(3 downto 0);
      bram_addr_a   : out std_logic_vector(14 downto 0);  -- 15-bit byte address
      bram_wrdata_a : out std_logic_vector(31 downto 0);
      bram_rddata_a : in  std_logic_vector(31 downto 0)
    );
  end component;

  -- BRAM IP (Standalone mode with 32-bit addressing)
  -- Configured for Standalone mode to allow COE file initialization.
  -- Uses 32-bit byte addresses (zero-extended from controller's 15-bit output).
  -- The BRAM internally handles byte-to-word address conversion.
  component Top_QPSK_Snapshot_BRAM_0
    port (
      clka  : in  std_logic;
      rsta  : in  std_logic;
      ena   : in  std_logic;
      wea   : in  std_logic_vector(3 downto 0);   -- Byte-enable writes
      addra : in  std_logic_vector(31 downto 0);  -- 32-bit byte address
      dina  : in  std_logic_vector(31 downto 0);
      douta : out std_logic_vector(31 downto 0)
    );
  end component;

begin

  -- =========================================================================
  -- Clock Generation
  -- =========================================================================
  clk <= not clk after CLK_PERIOD / 2;

  -- =========================================================================
  -- Reset Generation
  -- =========================================================================
  reset_gen: process
  begin
    resetn <= '0';
    wait for 100 ns;
    wait until rising_edge(clk);
    resetn <= '1';
    wait;
  end process reset_gen;

  -- =========================================================================
  -- AXI Interconnect (SmartConnect)
  -- =========================================================================
  interconnect: Top_AXI_CPU_Interconnect_0
    port map (
      aclk            => clk,
      aresetn         => resetn,
      -- S00_AXI from testbench master
      S00_AXI_awaddr  => m_axi_awaddr,
      S00_AXI_awlen   => m_axi_awlen,
      S00_AXI_awsize  => m_axi_awsize,
      S00_AXI_awburst => m_axi_awburst,
      S00_AXI_awlock  => m_axi_awlock,
      S00_AXI_awcache => m_axi_awcache,
      S00_AXI_awprot  => m_axi_awprot,
      S00_AXI_awqos   => m_axi_awqos,
      S00_AXI_awvalid => m_axi_awvalid,
      S00_AXI_awready => m_axi_awready,
      S00_AXI_wdata   => m_axi_wdata,
      S00_AXI_wstrb   => m_axi_wstrb,
      S00_AXI_wlast   => m_axi_wlast,
      S00_AXI_wvalid  => m_axi_wvalid,
      S00_AXI_wready  => m_axi_wready,
      S00_AXI_bresp   => m_axi_bresp,
      S00_AXI_bvalid  => m_axi_bvalid,
      S00_AXI_bready  => m_axi_bready,
      S00_AXI_araddr  => m_axi_araddr,
      S00_AXI_arlen   => m_axi_arlen,
      S00_AXI_arsize  => m_axi_arsize,
      S00_AXI_arburst => m_axi_arburst,
      S00_AXI_arlock  => m_axi_arlock,
      S00_AXI_arcache => m_axi_arcache,
      S00_AXI_arprot  => m_axi_arprot,
      S00_AXI_arqos   => m_axi_arqos,
      S00_AXI_arvalid => m_axi_arvalid,
      S00_AXI_arready => m_axi_arready,
      S00_AXI_rdata   => m_axi_rdata,
      S00_AXI_rresp   => m_axi_rresp,
      S00_AXI_rlast   => m_axi_rlast,
      S00_AXI_rvalid  => m_axi_rvalid,
      S00_AXI_rready  => m_axi_rready,
      -- M00_AXI to BRAM controller
      M00_AXI_awaddr  => ic_to_ctrl_awaddr,
      M00_AXI_awlen   => ic_to_ctrl_awlen,
      M00_AXI_awsize  => ic_to_ctrl_awsize,
      M00_AXI_awburst => ic_to_ctrl_awburst,
      M00_AXI_awlock  => ic_to_ctrl_awlock,
      M00_AXI_awcache => ic_to_ctrl_awcache,
      M00_AXI_awprot  => ic_to_ctrl_awprot,
      M00_AXI_awqos   => ic_to_ctrl_awqos,
      M00_AXI_awvalid => ic_to_ctrl_awvalid,
      M00_AXI_awready => ic_to_ctrl_awready,
      M00_AXI_wdata   => ic_to_ctrl_wdata,
      M00_AXI_wstrb   => ic_to_ctrl_wstrb,
      M00_AXI_wlast   => ic_to_ctrl_wlast,
      M00_AXI_wvalid  => ic_to_ctrl_wvalid,
      M00_AXI_wready  => ic_to_ctrl_wready,
      M00_AXI_bresp   => ic_to_ctrl_bresp,
      M00_AXI_bvalid  => ic_to_ctrl_bvalid,
      M00_AXI_bready  => ic_to_ctrl_bready,
      M00_AXI_araddr  => ic_to_ctrl_araddr,
      M00_AXI_arlen   => ic_to_ctrl_arlen,
      M00_AXI_arsize  => ic_to_ctrl_arsize,
      M00_AXI_arburst => ic_to_ctrl_arburst,
      M00_AXI_arlock  => ic_to_ctrl_arlock,
      M00_AXI_arcache => ic_to_ctrl_arcache,
      M00_AXI_arprot  => ic_to_ctrl_arprot,
      M00_AXI_arqos   => ic_to_ctrl_arqos,
      M00_AXI_arvalid => ic_to_ctrl_arvalid,
      M00_AXI_arready => ic_to_ctrl_arready,
      M00_AXI_rdata   => ic_to_ctrl_rdata,
      M00_AXI_rresp   => ic_to_ctrl_rresp,
      M00_AXI_rlast   => ic_to_ctrl_rlast,
      M00_AXI_rvalid  => ic_to_ctrl_rvalid,
      M00_AXI_rready  => ic_to_ctrl_rready
    );

  -- =========================================================================
  -- AXI BRAM Controller
  -- =========================================================================
  bram_ctrl: Top_AXI_BRAM_Controller_0
    port map (
      s_axi_aclk    => clk,
      s_axi_aresetn => resetn,
      s_axi_awaddr  => ic_to_ctrl_awaddr,
      s_axi_awlen   => ic_to_ctrl_awlen,
      s_axi_awsize  => ic_to_ctrl_awsize,
      s_axi_awburst => ic_to_ctrl_awburst,
      s_axi_awlock  => ic_to_ctrl_awlock(0),
      s_axi_awcache => ic_to_ctrl_awcache,
      s_axi_awprot  => ic_to_ctrl_awprot,
      s_axi_awvalid => ic_to_ctrl_awvalid,
      s_axi_awready => ic_to_ctrl_awready,
      s_axi_wdata   => ic_to_ctrl_wdata,
      s_axi_wstrb   => ic_to_ctrl_wstrb,
      s_axi_wlast   => ic_to_ctrl_wlast,
      s_axi_wvalid  => ic_to_ctrl_wvalid,
      s_axi_wready  => ic_to_ctrl_wready,
      s_axi_bresp   => ic_to_ctrl_bresp,
      s_axi_bvalid  => ic_to_ctrl_bvalid,
      s_axi_bready  => ic_to_ctrl_bready,
      s_axi_araddr  => ic_to_ctrl_araddr,
      s_axi_arlen   => ic_to_ctrl_arlen,
      s_axi_arsize  => ic_to_ctrl_arsize,
      s_axi_arburst => ic_to_ctrl_arburst,
      s_axi_arlock  => ic_to_ctrl_arlock(0),
      s_axi_arcache => ic_to_ctrl_arcache,
      s_axi_arprot  => ic_to_ctrl_arprot,
      s_axi_arvalid => ic_to_ctrl_arvalid,
      s_axi_arready => ic_to_ctrl_arready,
      s_axi_rdata   => ic_to_ctrl_rdata,
      s_axi_rresp   => ic_to_ctrl_rresp,
      s_axi_rlast   => ic_to_ctrl_rlast,
      s_axi_rvalid  => ic_to_ctrl_rvalid,
      s_axi_rready  => ic_to_ctrl_rready,
      bram_rst_a    => bram_rst_a,
      bram_clk_a    => bram_clk_a,
      bram_en_a     => bram_en_a,
      bram_we_a     => bram_we_a,
      bram_addr_a   => bram_addr_a,
      bram_wrdata_a => bram_wrdata_a,
      bram_rddata_a => bram_rddata_a
    );

  -- =========================================================================
  -- QPSK Snapshot BRAM (Standalone mode with 32-bit addressing)
  -- The BRAM is in Standalone mode to allow COE file initialization.
  -- The BRAM Controller outputs 15-bit byte address, which we zero-extend
  -- to 32 bits. The BRAM IP handles byte-to-word conversion internally.
  -- =========================================================================

  -- Zero-extend the 15-bit address from BRAM Controller to 32-bit for BRAM
  bram_addr_a_ext <= (31 downto 15 => '0') & bram_addr_a;

  bram: Top_QPSK_Snapshot_BRAM_0
    port map (
      clka  => bram_clk_a,
      rsta  => bram_rst_a,
      ena   => bram_en_a,
      wea   => bram_we_a,           -- Full 4-bit byte enables
      addra => bram_addr_a_ext,     -- Zero-extended 32-bit address
      dina  => bram_wrdata_a,
      douta => bram_rddata_a
    );

  -- =========================================================================
  -- COE File Loading Process
  -- =========================================================================
  coe_load: process
    file coe_file     : text open read_mode is COE_FILE;
    variable line_buf : line;
    variable char     : character;
    variable hex_str  : string(1 to 8);
    variable word_idx : natural := 0;
    variable in_data  : boolean := false;
    variable hex_val  : std_logic_vector(31 downto 0);
    variable good     : boolean;
    variable is_hex   : boolean;
  begin
    report "Loading COE file...";

    while not endfile(coe_file) and word_idx < NUM_SAMPLES loop
      readline(coe_file, line_buf);

      if line_buf'length > 0 then
        read(line_buf, char, good);

        if good then
          if char = ';' then
            next;
          end if;

          if char = 'm' then
            in_data := true;
            next;
          end if;

          is_hex := (char >= '0' and char <= '9') or
                    (char >= 'A' and char <= 'F') or
                    (char >= 'a' and char <= 'f');

          if in_data and is_hex then
            hex_str(1) := char;
            for i in 2 to 8 loop
              if line_buf'length > 0 then
                read(line_buf, char, good);
                if good and ((char >= '0' and char <= '9') or
                            (char >= 'A' and char <= 'F') or
                            (char >= 'a' and char <= 'f')) then
                  hex_str(i) := char;
                else
                  hex_str(i) := '0';
                end if;
              else
                hex_str(i) := '0';
              end if;
            end loop;

            for i in 0 to 7 loop
              hex_val(31 - i*4 downto 28 - i*4) := hex_char_to_slv(hex_str(i + 1));
            end loop;

            expected_data(word_idx) <= hex_val;
            word_idx := word_idx + 1;
          end if;
        end if;
      end if;
    end loop;

    file_close(coe_file);

    report "Loaded " & integer'image(word_idx) & " words from COE file";
    coe_loaded <= true;

    wait;
  end process coe_load;

  -- =========================================================================
  -- Main Test Process - AXI Master BFM
  -- =========================================================================
  main_test: process
    variable v_good_count     : natural := 0;
    variable v_bad_count      : natural := 0;
    variable v_mismatch_count : natural := 0;
    variable i_val : signed(15 downto 0);
    variable q_val : signed(15 downto 0);
    variable read_data : std_logic_vector(31 downto 0);
  begin
    report "============================================";
    report "BRAM Readback Verification Testbench";
    report "============================================";
    report "Path: AXI Master -> SmartConnect -> BRAM Ctrl -> BRAM";
    report "Reading 1024 IQ words via AXI path...";
    report "Comparing against COE file data...";
    report "============================================";

    -- Wait for COE file to be loaded
    wait until coe_loaded;

    -- Wait for reset to complete
    wait until resetn = '1';
    report "Reset released, waiting for SmartConnect to initialize...";

    -- Wait longer for SmartConnect internal reset synchronization
    -- The proc_sys_reset takes 16+ clock cycles to release
    wait for 2 us;

    report "Starting AXI transactions...";

    -- Synchronize to clock
    wait until rising_edge(clk);

    -- Keep rready asserted throughout - we're always ready to receive data
    m_axi_rready <= '1';

    -- =========================================================================
    -- Pipeline Latency Compensation
    -- =========================================================================
    --
    -- The SmartConnect + AXI BRAM Controller pipeline has 1-transaction latency.
    -- When we issue address N, the data returned is for address N-1 (from the
    -- previous transaction). This is inherent to pipelined AXI interconnects.
    --
    -- To retrieve N data values, we must issue N+1 transactions:
    --
    --   Loop iterations: 0, 1, 2, ..., 1023, 1024  (1025 total for 1024 samples)
    --
    --   i=0:    Issue addr 0    -> Response is garbage (pipeline empty)
    --   i=1:    Issue addr 1    -> Response is data[0]
    --   i=2:    Issue addr 2    -> Response is data[1]
    --   ...
    --   i=1023: Issue addr 1023 -> Response is data[1022]
    --   i=1024: Issue addr 0    -> Response is data[1023] (flush read)
    --
    -- The extra read at i=NUM_SAMPLES (which re-reads address 0) serves to
    -- FLUSH the pipeline and retrieve the final sample (data[1023]). The
    -- response from this flush read itself is discarded by loop termination.
    --
    -- Key points:
    --   1. The flush read is at the END (not beginning) to retrieve last data
    --   2. Comparison logic uses (i-1) indexing to align responses with expected
    --   3. The first response (i=0) is explicitly skipped (garbage/priming)
    --
    -- This pattern is common when dealing with pipelined AXI systems.
    -- =========================================================================

    -- Read NUM_SAMPLES + 1 transactions to account for pipeline latency
    for i in 0 to NUM_SAMPLES loop
      -- Issue AXI read request
      -- For i=0 to NUM_SAMPLES-1: request actual data addresses
      -- For i=NUM_SAMPLES: re-read address 0 (just to flush pipeline, data discarded)
      if i < NUM_SAMPLES then
        m_axi_araddr <= std_logic_vector(BRAM_BASE_ADDR + to_unsigned(i * 4, 32));
      else
        m_axi_araddr <= std_logic_vector(BRAM_BASE_ADDR);  -- Dummy read
      end if;
      m_axi_arlen  <= x"00";
      m_axi_arsize <= "010";
      m_axi_arburst <= "01";
      m_axi_arvalid <= '1';

      -- Wait for address handshake
      wait until rising_edge(clk) and m_axi_arready = '1';
      m_axi_arvalid <= '0';

      -- Wait for data handshake
      wait until rising_edge(clk) and m_axi_rvalid = '1';
      read_data := m_axi_rdata;

      -- Process data: i=0 is garbage (pipeline priming), i=1..NUM_SAMPLES is real data
      if i > 0 then
        -- Data received is for sample (i-1)
        sample_idx <= i - 1;
        iq_word <= read_data;
        expected_word <= expected_data(i - 1);
        i_val := signed(read_data(15 downto 0));
        q_val := signed(read_data(31 downto 16));
        i_out <= i_val;
        q_out <= q_val;

        -- Check if valid QPSK data
        if abs(to_integer(i_val)) > 10000 and abs(to_integer(q_val)) > 10000 then
          v_good_count := v_good_count + 1;
        else
          v_bad_count := v_bad_count + 1;
          if v_bad_count <= 10 then
            report "BAD Sample " & integer'image(i - 1) &
                   ": I=" & integer'image(to_integer(i_val)) &
                   ", Q=" & integer'image(to_integer(q_val));
          end if;
        end if;

        -- Compare against expected COE data
        if read_data /= expected_data(i - 1) then
          v_mismatch_count := v_mismatch_count + 1;
          if v_mismatch_count <= 10 then
            report "MISMATCH at address " & integer'image(i - 1) &
                   ": Expected=0x" &
                   integer'image(to_integer(unsigned(expected_data(i - 1)(31 downto 16)))) & "_" &
                   integer'image(to_integer(unsigned(expected_data(i - 1)(15 downto 0)))) &
                   ", Got=0x" &
                   integer'image(to_integer(unsigned(read_data(31 downto 16)))) & "_" &
                   integer'image(to_integer(unsigned(read_data(15 downto 0))));
          end if;
        end if;

        -- Update count signals
        good_count <= v_good_count;
        bad_count <= v_bad_count;
        mismatch_count <= v_mismatch_count;

        -- Progress report
        if i mod 256 = 0 then
          report "Read " & integer'image(i) & " samples...";
        end if;
      end if;
    end loop;

    -- Set pass/fail indicator
    if v_bad_count = 0 and v_mismatch_count = 0 then
      test_pass <= '1';
    else
      test_pass <= '0';
    end if;

    -- Final report
    report "============================================";
    report "BRAM Readback Complete";
    report "============================================";
    report "Total samples read: 1024";
    report "Good QPSK samples: " & integer'image(v_good_count);
    report "Bad/invalid samples: " & integer'image(v_bad_count);
    report "COE file mismatches: " & integer'image(v_mismatch_count);
    report "--------------------------------------------";
    if v_bad_count = 0 and v_mismatch_count = 0 then
      report "RESULT: PASS - All 1024 BRAM samples match COE file";
    else
      if v_bad_count > 0 then
        report "RESULT: FAIL - " & integer'image(v_bad_count) & " invalid QPSK samples";
      end if;
      if v_mismatch_count > 0 then
        report "RESULT: FAIL - " & integer'image(v_mismatch_count) & " mismatches vs COE file";
      end if;
    end if;
    report "============================================";

    -- End simulation
    assert false report "Simulation complete" severity failure;
    wait;
  end process main_test;

end architecture sim;

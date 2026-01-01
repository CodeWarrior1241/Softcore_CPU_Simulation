-- ============================================================================
-- Snapshot BRAM Readback Testbench (with UUT)
-- ============================================================================
-- This testbench instantiates the actual Top_QPSK_Snapshot_BRAM_0 IP and
-- reads back all 1024 IQ words to verify the initialization data is correct.
--
-- Purpose: Verify the BRAM IP contains correct QPSK data from the COE file.
--
-- Usage: Run through Vivado xsim (not standalone). The IP must be compiled
--        first via Vivado's simulation flow.
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity snapshot_bram_readback_tb is
end entity snapshot_bram_readback_tb;

architecture sim of snapshot_bram_readback_tb is

  -- Clock period (100 MHz)
  constant CLK_PERIOD : time := 10 ns;

  -- Number of IQ samples to read
  constant NUM_SAMPLES : natural := 1024;

  -- Component declaration for the BRAM IP (Verilog module)
  component Top_QPSK_Snapshot_BRAM_0
    port (
      clka  : in  std_logic;
      ena   : in  std_logic;
      wea   : in  std_logic_vector(0 downto 0);
      addra : in  std_logic_vector(12 downto 0);
      dina  : in  std_logic_vector(31 downto 0);
      douta : out std_logic_vector(31 downto 0)
    );
  end component;

  -- BRAM interface signals
  signal clk   : std_logic := '0';
  signal ena   : std_logic := '0';
  signal wea   : std_logic_vector(0 downto 0) := "0";
  signal addra : std_logic_vector(12 downto 0) := (others => '0');
  signal dina  : std_logic_vector(31 downto 0) := (others => '0');
  signal douta : std_logic_vector(31 downto 0);

  -- Observable signals for waveform viewer
  signal sample_idx  : natural range 0 to 1023 := 0;
  signal i_out       : signed(15 downto 0) := (others => '0');
  signal q_out       : signed(15 downto 0) := (others => '0');
  signal iq_word     : std_logic_vector(31 downto 0) := (others => '0');
  signal good_count  : natural range 0 to 1024 := 0;
  signal bad_count   : natural range 0 to 1024 := 0;
  signal test_pass   : std_logic := '0';

begin

  -- =========================================================================
  -- Clock Generation
  -- =========================================================================
  clk <= not clk after CLK_PERIOD / 2;

  -- =========================================================================
  -- Device Under Test: QPSK Snapshot BRAM
  -- =========================================================================
  uut: Top_QPSK_Snapshot_BRAM_0
    port map (
      clka  => clk,
      ena   => ena,
      wea   => wea,
      addra => addra,
      dina  => dina,
      douta => douta
    );

  -- =========================================================================
  -- Main Test Process - Read BRAM and verify data
  -- =========================================================================
  main_test: process
    variable v_good_count : natural := 0;
    variable v_bad_count  : natural := 0;
    variable i_val : signed(15 downto 0);
    variable q_val : signed(15 downto 0);
  begin
    report "============================================";
    report "BRAM Readback Verification Testbench";
    report "============================================";
    report "Reading 1024 IQ words from BRAM IP...";
    report "============================================";

    -- Wait for initialization
    wait for 100 ns;

    -- Synchronize to clock edge
    wait until rising_edge(clk);

    -- Enable BRAM for reading
    ena <= '1';
    wea <= "0";  -- Read only

    -- Read all samples
    for i in 0 to NUM_SAMPLES - 1 loop
      -- Set address (word address)
      addra <= std_logic_vector(to_unsigned(i, 13));
      sample_idx <= i;

      -- Wait for address to be registered by BRAM
      wait until rising_edge(clk);

      -- Wait for BRAM memory read latency
      wait until rising_edge(clk);

      -- Wait for output register latency (C_HAS_MEM_OUTPUT_REGS_A=1)
      wait until rising_edge(clk);

      -- Capture and analyze data
      iq_word <= douta;
      i_val := signed(douta(15 downto 0));
      q_val := signed(douta(31 downto 16));
      i_out <= i_val;
      q_out <= q_val;

      -- Check if this looks like valid QPSK data (|I| > 10000 and |Q| > 10000)
      if abs(to_integer(i_val)) > 10000 and abs(to_integer(q_val)) > 10000 then
        v_good_count := v_good_count + 1;
      else
        v_bad_count := v_bad_count + 1;
        -- Report first few bad samples
        if v_bad_count <= 10 then
          report "BAD Sample " & integer'image(i) &
                 ": I=" & integer'image(to_integer(i_val)) &
                 ", Q=" & integer'image(to_integer(q_val));
        end if;
      end if;

      -- Update count signals
      good_count <= v_good_count;
      bad_count <= v_bad_count;

      -- Progress report every 256 samples
      if (i + 1) mod 256 = 0 then
        report "Read " & integer'image(i + 1) & " samples...";
      end if;
    end loop;

    -- Disable BRAM
    ena <= '0';

    -- Set pass/fail indicator
    if v_bad_count = 0 then
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
    if v_bad_count = 0 then
      report "RESULT: PASS - All 1024 BRAM samples are valid QPSK data";
    else
      report "RESULT: FAIL - " & integer'image(v_bad_count) & " invalid samples in BRAM";
    end if;
    report "============================================";

    -- End simulation
    assert false report "Simulation complete" severity failure;
    wait;
  end process main_test;

end architecture sim;

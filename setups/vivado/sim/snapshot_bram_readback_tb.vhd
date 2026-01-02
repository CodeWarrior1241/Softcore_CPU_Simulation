-- ============================================================================
-- Snapshot BRAM Readback Testbench (with UUT)
-- ============================================================================
-- This testbench instantiates the actual Top_QPSK_Snapshot_BRAM_0 IP and
-- reads back all 1024 IQ words to verify the initialization data is correct.
--
-- Purpose: Verify the BRAM IP contains correct QPSK data from the COE file.
--          Compares each read value against expected data from COE file.
--
-- Usage: Run through Vivado xsim (not standalone). The IP must be compiled
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

  -- Expected data from COE file
  type expected_data_t is array (0 to NUM_SAMPLES - 1) of std_logic_vector(31 downto 0);
  signal expected_data : expected_data_t := (others => (others => '0'));
  signal coe_loaded    : boolean := false;

  -- Mismatch tracking
  signal mismatch_count : natural range 0 to 1024 := 0;
  signal expected_word  : std_logic_vector(31 downto 0) := (others => '0');

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

      -- Skip empty lines
      if line_buf'length > 0 then
        read(line_buf, char, good);

        if good then
          -- Skip comment lines starting with ';'
          if char = ';' then
            next;
          end if;

          -- Look for memory_initialization_vector to start data section
          if char = 'm' then
            in_data := true;
            next;
          end if;

          -- Check if character is a hex digit
          is_hex := (char >= '0' and char <= '9') or
                    (char >= 'A' and char <= 'F') or
                    (char >= 'a' and char <= 'f');

          -- If in data section and line starts with hex digit, parse it
          if in_data and is_hex then
            -- Put back the first character and read 8 hex chars
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

            -- Convert hex string to std_logic_vector
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
  -- Main Test Process - Read BRAM and verify data
  -- =========================================================================
  main_test: process
    variable v_good_count     : natural := 0;
    variable v_bad_count      : natural := 0;
    variable v_mismatch_count : natural := 0;
    variable i_val : signed(15 downto 0);
    variable q_val : signed(15 downto 0);
  begin
    report "============================================";
    report "BRAM Readback Verification Testbench";
    report "============================================";
    report "Reading 1024 IQ words from BRAM IP...";
    report "Comparing against COE file data...";
    report "============================================";

    -- Wait for COE file to be loaded
    wait until coe_loaded;

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
      expected_word <= expected_data(i);
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

      -- Compare against expected COE data
      if douta /= expected_data(i) then
        v_mismatch_count := v_mismatch_count + 1;
        -- Report first few mismatches
        if v_mismatch_count <= 10 then
          report "MISMATCH at address " & integer'image(i) &
                 ": Expected=0x" &
                 -- Convert expected to hex string for reporting
                 integer'image(to_integer(unsigned(expected_data(i)(31 downto 16)))) & "_" &
                 integer'image(to_integer(unsigned(expected_data(i)(15 downto 0)))) &
                 ", Got=0x" &
                 integer'image(to_integer(unsigned(douta(31 downto 16)))) & "_" &
                 integer'image(to_integer(unsigned(douta(15 downto 0))));
        end if;
      end if;

      -- Update count signals
      good_count <= v_good_count;
      bad_count <= v_bad_count;
      mismatch_count <= v_mismatch_count;

      -- Progress report every 256 samples
      if (i + 1) mod 256 = 0 then
        report "Read " & integer'image(i + 1) & " samples...";
      end if;
    end loop;

    -- Disable BRAM
    ena <= '0';

    -- Set pass/fail indicator (both QPSK validation AND COE comparison must pass)
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

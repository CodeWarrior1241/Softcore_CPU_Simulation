-- ================================================================================ --
-- IQ Sample BRAM - Simulates dual-port BRAM connected via AXI switch              --
-- -------------------------------------------------------------------------------- --
-- This module simulates the IQ sample BRAM that in the real design is:            --
--   - Connected to NEORV32 AXI port via an AXI switch                             --
--   - Dual-port BRAM with one port for CPU access, one for ADC data capture       --
--   - Address range: 0xC0000000 - 0xC0001FFF (8KB, 2048 x 32-bit words)           --
--                                                                                  --
-- Memory layout:                                                                   --
--   - First 1024 words (4KB): IQ samples, each 32-bit word = {Q[15:0], I[15:0]}   --
--   - Remaining 1024 words: Reserved/unused                                        --
--                                                                                  --
-- IQ data format (matches AD9361/AD9364 output):                                  --
--   - I: bits [15:0], signed 16-bit                                               --
--   - Q: bits [31:16], signed 16-bit                                              --
--   - Pre-initialized with synthetic QPSK constellation data + noise              --
-- -------------------------------------------------------------------------------- --
-- Part of the QPSK Triple Comparison Project                                      --
-- Licensed under the BSD-3-Clause license                                         --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity iq_bram is
  generic (
    MEM_SIZE : natural := 8192;  -- memory size in bytes (8KB = 2048 x 32-bit words)
    MEM_LATE : natural := 1      -- access latency cycles (min 1)
  );
  port (
    clk_i      : in  std_ulogic;
    rstn_i     : in  std_ulogic;
    xbus_req_i : in  xbus_req_t;
    xbus_rsp_o : out xbus_rsp_t
  );
end iq_bram;

architecture iq_bram_rtl of iq_bram is

  -- Memory parameters
  constant NUM_WORDS : natural := MEM_SIZE / 4;  -- 2048 words
  constant ADDR_BITS : natural := 11;            -- log2(2048) = 11 bits

  -- Memory type
  type mem_t is array (0 to NUM_WORDS-1) of std_ulogic_vector(31 downto 0);

  -- 32-bit LFSR for pseudo-random noise generation (compile-time)
  -- Uses maximal-length polynomial: x^32 + x^22 + x^2 + x + 1
  function lfsr_next(lfsr : unsigned) return unsigned is
    variable fb : std_ulogic;
  begin
    fb := lfsr(31) xor lfsr(21) xor lfsr(1) xor lfsr(0);
    return lfsr(30 downto 0) & fb;
  end function;

  -- Initialize memory with synthetic QPSK data
  -- Simulates AD9361/AD9364 12-bit ADC scaled to 16-bit
  -- QPSK constellation at +/- 16384 (50% of full scale)
  function init_iq_memory return mem_t is
    variable mem      : mem_t;
    variable lfsr     : unsigned(31 downto 0) := x"DEADBEEF";
    variable symbol   : integer;
    variable i_val    : signed(15 downto 0);
    variable q_val    : signed(15 downto 0);
    variable noise_i  : signed(15 downto 0);
    variable noise_q  : signed(15 downto 0);
    variable iq_word  : std_ulogic_vector(31 downto 0);
  begin
    -- Initialize all memory to zero
    mem := (others => (others => '0'));

    -- Fill first 1024 entries with QPSK samples
    for idx in 0 to 1023 loop
      -- Generate pseudo-random symbol (0-3 for QPSK)
      lfsr := lfsr_next(lfsr);
      symbol := to_integer(lfsr(1 downto 0));

      -- QPSK constellation points (Gray-coded)
      -- Symbol 00 -> +I, +Q (45 degrees)
      -- Symbol 01 -> -I, +Q (135 degrees)
      -- Symbol 11 -> -I, -Q (225 degrees)
      -- Symbol 10 -> +I, -Q (315 degrees)
      case symbol is
        when 0 => i_val := to_signed( 16384, 16); q_val := to_signed( 16384, 16);
        when 1 => i_val := to_signed(-16384, 16); q_val := to_signed( 16384, 16);
        when 2 => i_val := to_signed( 16384, 16); q_val := to_signed(-16384, 16);
        when 3 => i_val := to_signed(-16384, 16); q_val := to_signed(-16384, 16);
        when others => i_val := to_signed(0, 16); q_val := to_signed(0, 16);
      end case;

      -- Add AWGN-like noise (+/- 256, ~1.5% of signal amplitude)
      -- Use different bit ranges from 32-bit LFSR for I and Q to decorrelate
      lfsr := lfsr_next(lfsr);
      noise_i := to_signed(to_integer(unsigned(lfsr(8 downto 0))) - 256, 16);
      noise_q := to_signed(to_integer(unsigned(lfsr(24 downto 16))) - 256, 16);

      i_val := i_val + noise_i;
      q_val := q_val + noise_q;

      -- Pack into 32-bit word: I in lower 16 bits, Q in upper 16 bits
      -- This matches the AD9361 data format and MATLAB GUI expectations
      iq_word(15 downto 0)  := std_ulogic_vector(i_val);
      iq_word(31 downto 16) := std_ulogic_vector(q_val);

      mem(idx) := iq_word;
    end loop;

    report "IQ_BRAM: Initialized with 1024 synthetic QPSK samples" severity note;
    return mem;
  end function;

  -- Memory array (initialized with QPSK data at elaboration)
  signal memory : mem_t := init_iq_memory;

  -- Memory access signals
  signal addr  : unsigned(ADDR_BITS-1 downto 0);
  signal rdata : std_ulogic_vector(31 downto 0);
  signal ack   : std_ulogic;

  -- Latency pipeline
  type late_data_t is array (MEM_LATE downto 0) of std_ulogic_vector(31 downto 0);
  signal late_data : late_data_t;
  signal late_ack  : std_ulogic_vector(MEM_LATE downto 0);

begin

  -- Address extraction (word-aligned, bits [12:2] for 2048 words)
  addr <= unsigned(xbus_req_i.addr(ADDR_BITS+1 downto 2));

  -- Memory read/write process
  mem_access: process(clk_i)
  begin
    if rising_edge(clk_i) then
      if (xbus_req_i.cyc = '1') and (xbus_req_i.stb = '1') then
        if (xbus_req_i.we = '1') then
          -- Write access (byte-enabled)
          if (xbus_req_i.sel(0) = '1') then
            memory(to_integer(addr))(7 downto 0) <= xbus_req_i.data(7 downto 0);
          end if;
          if (xbus_req_i.sel(1) = '1') then
            memory(to_integer(addr))(15 downto 8) <= xbus_req_i.data(15 downto 8);
          end if;
          if (xbus_req_i.sel(2) = '1') then
            memory(to_integer(addr))(23 downto 16) <= xbus_req_i.data(23 downto 16);
          end if;
          if (xbus_req_i.sel(3) = '1') then
            memory(to_integer(addr))(31 downto 24) <= xbus_req_i.data(31 downto 24);
          end if;
        else
          -- Read access
          rdata <= memory(to_integer(addr));
        end if;
      end if;
    end if;
  end process mem_access;

  -- Acknowledge generation
  ack_gen: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      ack <= '0';
    elsif rising_edge(clk_i) then
      ack <= xbus_req_i.cyc and xbus_req_i.stb;
    end if;
  end process ack_gen;

  -- Latency pipeline (simulates AXI switch latency)
  latency_gen: process(rstn_i, clk_i)
  begin
    if (rstn_i = '0') then
      late_data <= (others => (others => '0'));
      late_ack  <= (others => '0');
    elsif rising_edge(clk_i) then
      late_data(0) <= rdata;
      late_ack(0)  <= ack;
      for i in 0 to MEM_LATE-1 loop
        late_data(i+1) <= late_data(i);
        late_ack(i+1)  <= late_ack(i);
      end loop;
    end if;
  end process latency_gen;

  -- Bus response
  xbus_rsp_o.data <= late_data(MEM_LATE-1) when (late_ack(MEM_LATE-1) = '1') else (others => '0');
  xbus_rsp_o.ack  <= late_ack(MEM_LATE-1);
  xbus_rsp_o.err  <= '0';

end iq_bram_rtl;

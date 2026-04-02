//------------------------------------------------------------------------------
// Vivado Testbench for NEORV32 + AD9361 Datapath Simulation
//------------------------------------------------------------------------------
//
// This testbench instantiates the Top_wrapper block design and provides:
//   - Clock generation (300MHz differential input for PLL)
//   - Reset sequencing (1ms reset period for PLL lock and initialization)
//   - AD9361 LVDS stimulus from COE file data (looped continuously)
//   - TX to RX loopback for datapath verification
//   - UART monitoring
//
//------------------------------------------------------------------------------
// Architecture Block Diagram
//------------------------------------------------------------------------------
//
//  +------------------------------------------------------------------------+
//  |           DUT (Top_wrapper / FPGA Design)                              |
//  |                                                                        |
//  |  300MHz ECS     +-------------+                                        |
//  |  diff clk ----->| clk_wiz     |---> 100 MHz (AXI bus, CPU)            |
//  |                 +-------------+---> 300 MHz (IODELAY ref)              |
//  |                                                                        |
//  |  LVDS RX        +-------------+         +-------------+    LVDS TX     |
//  |  ------+------->| axi_ad9361  |         | axi_ad9361  |-----+------>   |
//  |  clk   |        | ADC Section |         | DAC Section |     |          |
//  |  frame |        +------+------+         +------+------+     | clk      |
//  |  data  |           l_clk|                      ^            | frame    |
//  |                  (125   |MHz)                   |            | data     |
//  |                        v                       |                       |
//  |                 +-------------------------------+------+               |
//  |                 |      axi_ad9361_adapter (HLS, v4.0)  |               |
//  |                 |      ap_clk = l_clk (125 MHz)        |               |
//  |                 |      ctrl/status = ap_none wires     |               |
//  |                 |      tx/rx_stream = AXI-Stream       |               |
//  |                 +--------+-----------------------+-----+               |
//  |                    tx_stream                rx_stream                   |
//  |                        |                       ^                       |
//  |                 +------v------+         +------+------+                |
//  |                 | TX CDC FIFO |         | RX CDC FIFO |                |
//  |                 | 100->125MHz |         | 125->100MHz |                |
//  |                 +------+------+         +------+------+                |
//  |                        ^                       |                       |
//  |                 +------+-----------------------+------+                |
//  |                 |  axi_streaming_adapter (HLS, v1.0)  |                |
//  |                 |  ap_clk = 100 MHz (AXI)             |                |
//  |                 |  s_axi_ctrl = AXI-Lite (CPU)        |                |
//  |                 |  tx_data[1024], rx_data[1024]        |                |
//  |                 +-------------------------------------+                |
//  |                        ^                                               |
//  |                        | AXI-Lite (100 MHz)                            |
//  |  +-------------+------+                                                |
//  |  | NEORV32 CPU |---> UART TX (status + verification)                   |
//  |  | (100 MHz)   |---> GPIO (up_enable, up_txnrx)                        |
//  |  +-------------+---> AXI (BRAM, axi_ad9361, streaming_adapter)         |
//  |                                                                        |
//  +------------------------------------------------------------------------+
//
//------------------------------------------------------------------------------
// Test Sequence
//------------------------------------------------------------------------------
//
// Testbench (runs independently):
//  1. Reset held for 1ms (PLL lock and initialization)
//  2. PLL locks, 100 MHz and 300 MHz clocks stable
//  3. Testbench feeds COE data into LVDS RX at 125 MHz (looped)
//  4. After 2 full COE loops (2048 samples), switches to TX->RX loopback
//  5. Simulation runs for 50ms total
//
// CPU firmware (runs in parallel after reset):
//  1. Boot, init UART, start streaming adapter bridge (ap_ctrl_chain)
//  2. Configure adapter: all channels enabled, loopback on
//  3. Enable AD9361 via GPIO (up_enable=1, up_txnrx=1)
//  4. Write 1024 known samples to TX buffer, trigger TX burst
//  5. Wait for RX_READY, read back 1024 samples, verify, release slot
//  6. Repeat RX readback for 3 cycles, report PASS/FAIL via UART
//
// Datapath (hardware):
//  COE/loopback -> LVDS RX -> axi_ad9361 ADC -> axi_ad9361_adapter (125 MHz)
//  -> RX CDC FIFO -> streaming adapter rx_data[] (100 MHz, CPU reads)
//  CPU writes tx_data[] -> streaming adapter -> TX CDC FIFO
//  -> axi_ad9361_adapter -> axi_ad9361 DAC -> LVDS TX
//
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module vivado_tb;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------

    // Clock periods
    parameter real ECS_CLK_PERIOD_NS = 3.333;    // 300 MHz input clock
    parameter real AD9361_CLK_PERIOD_NS = 8.0;    // 125 MHz AD9361 data clock

    // Simulation timing
    parameter RESET_HOLD_NS = 1_000_000;         // 1ms reset hold for PLL lock

    // COE data parameters
    parameter NUM_COE_SAMPLES = 1024;            // Number of IQ samples in COE file

    //--------------------------------------------------------------------------
    // Testbench Signals
    //--------------------------------------------------------------------------

    // ECS 300MHz differential clock input
    reg ecs_clk_in_p;
    reg ecs_clk_in_n;

    // System reset (directly active low for the design)
    reg system_resetn;

    // UART signals
    wire uart0_txd;
    reg  uart0_rxd;

    // AD9361 LVDS RX interface (directly connect to TX loopback after initial stimulus)
    wire       rx_clk_in_p;
    wire       rx_clk_in_n;
    wire       rx_frame_in_p;
    wire       rx_frame_in_n;
    wire [5:0] rx_data_in_p;
    wire [5:0] rx_data_in_n;

    // AD9361 LVDS TX interface (from DUT to testbench)
    wire        tx_clk_out_p;
    wire        tx_clk_out_n;
    wire        tx_frame_out_p;
    wire        tx_frame_out_n;
    wire  [5:0] tx_data_out_p;
    wire  [5:0] tx_data_out_n;

    // AD9361 control signals
    wire enable;
    wire txnrx;

    // Clock locked indicator (directly from PLL via external port)
    wire sim_clock_100MHz_locked;
    wire sim_clock_100MHz;

    //--------------------------------------------------------------------------
    // COE Data Storage and Stimulus Generation
    //--------------------------------------------------------------------------

    // Memory to hold COE data (32-bit words: {Q[31:16], I[15:0]})
    reg [31:0] coe_data [0:NUM_COE_SAMPLES-1];

    // Stimulus generation signals
    reg        stim_clk;
    reg        stim_frame_p;
    reg        stim_frame_n;
    reg  [5:0] stim_data_p;
    reg  [5:0] stim_data_n;

    // COE playback control
    reg [9:0]  coe_index;
    reg [15:0] current_i;
    reg [15:0] current_q;
    reg        phase;           // 0 = I sample, 1 = Q sample
    reg        half_cycle;      // 0 = first 6 bits, 1 = last 6 bits

    // Loopback enable (after initial COE data has been sent)
    reg        loopback_mode;
    integer    samples_sent;

    //--------------------------------------------------------------------------
    // RX MUX: Select between stimulus and loopback
    //--------------------------------------------------------------------------

    // Use stimulus clock initially, then switch to TX loopback
    assign rx_clk_in_p   = loopback_mode ? tx_clk_out_p   : stim_clk;
    assign rx_clk_in_n   = loopback_mode ? tx_clk_out_n   : ~stim_clk;
    assign rx_frame_in_p = loopback_mode ? tx_frame_out_p : stim_frame_p;
    assign rx_frame_in_n = loopback_mode ? tx_frame_out_n : stim_frame_n;
    assign rx_data_in_p  = loopback_mode ? tx_data_out_p  : stim_data_p;
    assign rx_data_in_n  = loopback_mode ? tx_data_out_n  : stim_data_n;

    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------

    Top_wrapper dut (
        // Clock and reset
        .ecs_clk_in_clk_p       (ecs_clk_in_p),
        .ecs_clk_in_clk_n       (ecs_clk_in_n),
        .system_resetn          (system_resetn),
        .sim_clock_100MHz_locked(sim_clock_100MHz_locked),
        .sim_clock_100MHz       (sim_clock_100MHz),

        // UART
        .uart0_txd              (uart0_txd),
        .uart0_rxd              (uart0_rxd),

        // AD9361 LVDS RX
        .rx_clk_in_p            (rx_clk_in_p),
        .rx_clk_in_n            (rx_clk_in_n),
        .rx_frame_in_p          (rx_frame_in_p),
        .rx_frame_in_n          (rx_frame_in_n),
        .rx_data_in_p           (rx_data_in_p),
        .rx_data_in_n           (rx_data_in_n),

        // AD9361 LVDS TX
        .tx_clk_out_p           (tx_clk_out_p),
        .tx_clk_out_n           (tx_clk_out_n),
        .tx_frame_out_p         (tx_frame_out_p),
        .tx_frame_out_n         (tx_frame_out_n),
        .tx_data_out_p          (tx_data_out_p),
        .tx_data_out_n          (tx_data_out_n),

        // AD9361 control
        .enable                 (enable),
        .txnrx                  (txnrx)
    );

    //--------------------------------------------------------------------------
    // Clock Generation: ECS 300MHz Differential
    //--------------------------------------------------------------------------

    initial begin
        ecs_clk_in_p = 1'b0;
        ecs_clk_in_n = 1'b1;
    end

    always begin
        #(ECS_CLK_PERIOD_NS / 2.0);
        ecs_clk_in_p = ~ecs_clk_in_p;
        ecs_clk_in_n = ~ecs_clk_in_n;
    end

    //--------------------------------------------------------------------------
    // Load COE Data at Startup
    //--------------------------------------------------------------------------

    initial begin
        // Load COE file data
        // Note: $readmemh expects hex values without the header
        $readmemh("qpsk_bram_data.hex", coe_data);

        // Check if data was loaded (first sample should not be X)
        if (coe_data[0] === 32'bx) begin
            $error("Failed to load qpsk_bram_data.hex! Generate it with: python convert_coe_to_hex.py qpsk_bram_init.coe qpsk_bram_data.hex");
            $fatal;
        end
        $display("[%0t] Loaded %0d samples from COE data", $time, NUM_COE_SAMPLES);
    end

    //--------------------------------------------------------------------------
    // Reset Sequence
    //--------------------------------------------------------------------------

    initial begin
        // Start with reset asserted
        system_resetn = 1'b0;

        // Hold reset for 1ms to allow PLL lock
        #RESET_HOLD_NS;
        system_resetn = 1'b1;

        $display("[%0t] Reset released after 1ms", $time);
    end

    //--------------------------------------------------------------------------
    // UART Initialization
    //--------------------------------------------------------------------------

    initial begin
        uart0_rxd = 1'b1;  // Idle high
    end

    //--------------------------------------------------------------------------
    // AD9361 RX Data Generation from COE File
    //--------------------------------------------------------------------------
    //
    // In DDR LVDS 1R1T mode, the AD9361 sends:
    //   - 6 data bits per clock edge (12 bits per clock cycle)
    //   - Frame signal: high during I sample, low during Q sample
    //   - Data order: I sample (12 bits), then Q sample (12 bits)
    //
    // Each 32-bit COE word contains: {Q[31:16], I[15:0]}
    // We extract the upper 12 bits of each 16-bit sample (12-bit precision)
    //
    //--------------------------------------------------------------------------

    initial begin
        stim_clk = 1'b0;
        stim_frame_p = 1'b0;
        stim_frame_n = 1'b1;
        stim_data_p = 6'h00;
        stim_data_n = 6'h3F;
        coe_index = 0;
        current_i = 16'h0000;
        current_q = 16'h0000;
        phase = 1'b0;
        half_cycle = 1'b0;
        loopback_mode = 1'b0;
        samples_sent = 0;
    end

    // Generate stimulus clock and data from COE file
    always begin
        // Wait for reset release and PLL lock
        wait(system_resetn && sim_clock_100MHz_locked);

        // Small delay after reset
        #1000;

        $display("[%0t] Starting COE data stimulus", $time);

        // Loop through COE data continuously
        forever begin
            // Load next sample from COE data
            current_i = coe_data[coe_index][15:0];
            current_q = coe_data[coe_index][31:16];

            // Send I sample (frame high)
            // First half: upper 6 bits of I on rising edge
            stim_frame_p = 1'b1;
            stim_frame_n = 1'b0;
            stim_data_p = current_i[15:10];  // Upper 6 bits
            stim_data_n = ~current_i[15:10];
            #(AD9361_CLK_PERIOD_NS / 2.0);
            stim_clk = 1'b1;

            // Second half: lower 6 bits of I on falling edge
            stim_data_p = current_i[9:4];    // Middle 6 bits (skip lower 4)
            stim_data_n = ~current_i[9:4];
            #(AD9361_CLK_PERIOD_NS / 2.0);
            stim_clk = 1'b0;

            // Send Q sample (frame low)
            // First half: upper 6 bits of Q on rising edge
            stim_frame_p = 1'b0;
            stim_frame_n = 1'b1;
            stim_data_p = current_q[15:10];  // Upper 6 bits
            stim_data_n = ~current_q[15:10];
            #(AD9361_CLK_PERIOD_NS / 2.0);
            stim_clk = 1'b1;

            // Second half: lower 6 bits of Q on falling edge
            stim_data_p = current_q[9:4];    // Middle 6 bits
            stim_data_n = ~current_q[9:4];
            #(AD9361_CLK_PERIOD_NS / 2.0);
            stim_clk = 1'b0;

            // Move to next sample
            samples_sent = samples_sent + 1;
            coe_index = coe_index + 1;
            if (coe_index >= NUM_COE_SAMPLES) begin
                coe_index = 0;  // Loop back to start
                $display("[%0t] COE data loop completed (%0d samples sent), restarting", $time, samples_sent);
            end

            // After sending initial data, enable loopback mode
            // This allows TX->RX loopback to take over
            if (samples_sent == NUM_COE_SAMPLES * 2) begin
                $display("[%0t] Switching to TX->RX loopback mode", $time);
                loopback_mode = 1'b1;
                // In loopback mode, this process continues but RX mux uses TX signals
            end
        end
    end

    //--------------------------------------------------------------------------
    // Hardware Milestone Monitors
    // These fire on signal edges and print immediately — no UART delay.
    //--------------------------------------------------------------------------

    // PLL lock
    reg pll_locked_prev;
    always @(posedge sim_clock_100MHz) begin
        pll_locked_prev <= sim_clock_100MHz_locked;
        if (sim_clock_100MHz_locked && !pll_locked_prev)
            $display("[%0t] MILESTONE: PLL locked", $time);
    end

    // AD9361 enable/txnrx (GPIO-driven)
    reg enable_prev, txnrx_prev;
    always @(posedge sim_clock_100MHz) begin
        enable_prev <= enable;
        txnrx_prev  <= txnrx;
        if (enable && !enable_prev)
            $display("[%0t] MILESTONE: AD9361 enable asserted", $time);
        if (txnrx && !txnrx_prev)
            $display("[%0t] MILESTONE: AD9361 txnrx asserted", $time);
    end

    // First ADC valid from axi_ad9361 (sampled on l_clk, gated on GPIO[2] = AD9361 configured)
    reg first_adc_valid_seen;
    initial first_adc_valid_seen = 0;
    always @(posedge dut.Top_i.axi_ad9361.l_clk) begin
        if (!first_adc_valid_seen && dut.Top_i.NEORV32_RISC_V.gpio_o[2]) begin
            if (dut.Top_i.axi_ad9361_adapter.adc_valid_i0) begin
                first_adc_valid_seen <= 1;
                $display("[%0t] MILESTONE: First ADC valid detected at adapter (post-config)", $time);
            end
        end
    end

    // Ctrl CDC FIFO activity
    reg first_ctrl_out_valid_seen;
    initial first_ctrl_out_valid_seen = 0;
    always @(posedge sim_clock_100MHz) begin
        if (!first_ctrl_out_valid_seen) begin
            if (dut.Top_i.ad9361_cdc_ctrl_fifo.Out_Valid) begin
                first_ctrl_out_valid_seen <= 1;
                $display("[%0t] MILESTONE: First ctrl word delivered to adapter (FIFO Out_Valid)", $time);
            end
        end
    end

    // Status CDC FIFO activity
    reg first_status_out_valid_seen;
    initial first_status_out_valid_seen = 0;
    always @(posedge sim_clock_100MHz) begin
        if (!first_status_out_valid_seen) begin
            if (dut.Top_i.ad9361_cdc_status_fifo.Out_Valid) begin
                first_status_out_valid_seen <= 1;
                $display("[%0t] MILESTONE: First status word delivered to bridge (FIFO Out_Valid)", $time);
            end
        end
    end

    // TX stream: bridge side (into CDC FIFO)
    reg first_tx_bridge_seen;
    initial first_tx_bridge_seen = 0;
    always @(posedge sim_clock_100MHz) begin
        if (!first_tx_bridge_seen) begin
            if (dut.Top_i.ad9361_cdc_tx_streaming_fifo.s_axis_tvalid) begin
                first_tx_bridge_seen <= 1;
                $display("[%0t] MILESTONE: First TX TVALID at CDC FIFO input (bridge side)", $time);
            end
        end
    end

    // TX stream: adapter side (out of CDC FIFO)
    reg first_tx_stream_seen;
    initial first_tx_stream_seen = 0;
    always @(posedge sim_clock_100MHz) begin
        if (!first_tx_stream_seen) begin
            if (dut.Top_i.axi_ad9361_adapter.tx_stream_TVALID) begin
                first_tx_stream_seen <= 1;
                $display("[%0t] MILESTONE: First TX TVALID at adapter (CDC FIFO output)", $time);
            end
        end
    end

    // RX stream: adapter side (into CDC FIFO)
    reg first_rx_adapter_seen;
    initial first_rx_adapter_seen = 0;
    always @(posedge sim_clock_100MHz) begin
        if (!first_rx_adapter_seen) begin
            if (dut.Top_i.axi_ad9361_adapter.rx_stream_TVALID) begin
                first_rx_adapter_seen <= 1;
                $display("[%0t] MILESTONE: First RX TVALID at adapter (into CDC FIFO)", $time);
            end
        end
    end

    // RX stream: bridge side (out of CDC FIFO)
    reg first_rx_bridge_seen;
    initial first_rx_bridge_seen = 0;
    always @(posedge sim_clock_100MHz) begin
        if (!first_rx_bridge_seen) begin
            if (dut.Top_i.ad9361_cdc_rx_streaming_fifo.m_axis_tvalid) begin
                first_rx_bridge_seen <= 1;
                $display("[%0t] MILESTONE: First RX TVALID at bridge (CDC FIFO output)", $time);
            end
        end
    end

    // Adapter ctrl_valid_in — is the adapter actually receiving control words?
    reg first_adapter_ctrl_seen;
    initial first_adapter_ctrl_seen = 0;
    always @(posedge sim_clock_100MHz) begin
        if (!first_adapter_ctrl_seen) begin
            if (dut.Top_i.axi_ad9361_adapter.ctrl_valid_in) begin
                first_adapter_ctrl_seen <= 1;
                $display("[%0t] MILESTONE: First ctrl_valid_in at adapter (ctrl accepted)", $time);
            end
        end
    end

    // l_clk activity check (gated on reset released to avoid pre-reset transients)
    reg first_lclk_seen;
    integer lclk_edge_count;
    initial begin first_lclk_seen = 0; lclk_edge_count = 0; end
    always @(posedge dut.Top_i.axi_ad9361.l_clk) begin
        if (system_resetn) begin
            lclk_edge_count <= lclk_edge_count + 1;
            if (!first_lclk_seen) begin
                first_lclk_seen <= 1;
                $display("[%0t] MILESTONE: First l_clk edge detected (post-reset)", $time);
            end
        end
    end

    // l_clk death detector — if no edge for 1us, report it
    reg [31:0] lclk_last_count;
    initial lclk_last_count = 0;
    always begin
        #1_000_000; // check every 1ms
        if (lclk_edge_count == lclk_last_count && first_lclk_seen)
            $display("[%0t] WARNING: l_clk appears stopped (no edges in last 1ms, count=%0d)", $time, lclk_edge_count);
        lclk_last_count = lclk_edge_count;
    end

    // TX CDC FIFO m_axis_tready — is the adapter accepting data?
    reg first_tx_fifo_ready_seen;
    initial first_tx_fifo_ready_seen = 0;
    always @(posedge sim_clock_100MHz) begin
        if (!first_tx_fifo_ready_seen) begin
            if (dut.Top_i.ad9361_cdc_tx_streaming_fifo.m_axis_tready) begin
                first_tx_fifo_ready_seen <= 1;
                $display("[%0t] MILESTONE: TX CDC FIFO m_axis_tready asserted (adapter accepting)", $time);
            end
        end
    end

    //--------------------------------------------------------------------------
    // GPIO Result Monitor — auto-terminate on CPU PASS/FAIL
    //--------------------------------------------------------------------------
    // GPIO[6] = result_valid, GPIO[5] = result (1=PASS, 0=FAIL)
    // CPU asserts GPIO[6] after test completes.  Testbench reads GPIO[5]
    // and calls $finish immediately — no waiting for timeout.

    reg result_valid_prev;
    always @(posedge sim_clock_100MHz) begin
        result_valid_prev <= dut.Top_i.NEORV32_RISC_V.gpio_o[6];
        if (dut.Top_i.NEORV32_RISC_V.gpio_o[6] && !result_valid_prev) begin
            if (dut.Top_i.NEORV32_RISC_V.gpio_o[5]) begin
                $display("[%0t] TEST PASSED (GPIO result)", $time);
            end else begin
                $display("[%0t] TEST FAILED (GPIO result)", $time);
            end
            $display("  Total samples sent: %0d", samples_sent);
            #100;  // Let final signals settle
            $finish;
        end
    end

    // GPIO milestone monitors
    reg [7:0] gpio_prev;
    always @(posedge sim_clock_100MHz) begin
        gpio_prev <= dut.Top_i.NEORV32_RISC_V.gpio_o[7:0];
        if (dut.Top_i.NEORV32_RISC_V.gpio_o[2] && !gpio_prev[2])
            $display("[%0t] MILESTONE: AD9361 core configured (GPIO[2])", $time);
        if (dut.Top_i.NEORV32_RISC_V.gpio_o[3] && !gpio_prev[3])
            $display("[%0t] MILESTONE: TX burst complete (GPIO[3])", $time);
        if (dut.Top_i.NEORV32_RISC_V.gpio_o[4] && !gpio_prev[4])
            $display("[%0t] MILESTONE: RX readback done (GPIO[4])", $time);
    end

    //--------------------------------------------------------------------------
    // TX Data Monitoring
    //--------------------------------------------------------------------------

    always @(posedge tx_clk_out_p) begin
        if (system_resetn && sim_clock_100MHz_locked) begin
            // Monitor TX data (uncomment for debug)
            // $display("[%0t] TX Data: %h, Frame: %b", $time, tx_data_out_p, tx_frame_out_p);
        end
    end

    //--------------------------------------------------------------------------
    // UART TX Monitoring (simple character capture)
    //--------------------------------------------------------------------------

    // UART parameters (115200 baud at 100MHz clock)
    parameter UART_BIT_PERIOD_NS = 8680;  // 1/115200 = 8.68us

    reg [7:0] uart_rx_byte;
    reg [3:0] uart_rx_bit_count;
    reg       uart_rx_active;

    initial begin
        uart_rx_active = 1'b0;
        uart_rx_bit_count = 0;
        uart_rx_byte = 8'h00;
    end

    // Simple UART receiver for monitoring
    always @(negedge uart0_txd) begin
        if (!uart_rx_active && system_resetn) begin
            // Start bit detected
            uart_rx_active <= 1'b1;
            uart_rx_bit_count <= 0;
            #(UART_BIT_PERIOD_NS * 1.5);  // Move to middle of first data bit

            // Sample 8 data bits
            repeat (8) begin
                uart_rx_byte[uart_rx_bit_count] <= uart0_txd;
                uart_rx_bit_count <= uart_rx_bit_count + 1;
                #UART_BIT_PERIOD_NS;
            end

            // Wait for stop bit
            #(UART_BIT_PERIOD_NS / 2);

            // Print received character
            if (uart_rx_byte >= 8'h20 && uart_rx_byte <= 8'h7E) begin
                $write("%c", uart_rx_byte);
            end else if (uart_rx_byte == 8'h0A) begin
                $write("\n");
            end else if (uart_rx_byte == 8'h0D) begin
                // Ignore CR
            end else begin
                $write("[0x%02X]", uart_rx_byte);
            end

            uart_rx_active <= 1'b0;
        end
    end

    //--------------------------------------------------------------------------
    // Simulation Control
    //--------------------------------------------------------------------------

    initial begin
        $display("==============================================");
        $display("  NEORV32 + AD9361 Datapath Loopback Test");
        $display("==============================================");
        $display("  ECS Clock Period:    %0.3f ns (%.0f MHz)", ECS_CLK_PERIOD_NS, 1000.0/ECS_CLK_PERIOD_NS);
        $display("  AD9361 Clock Period: %0.3f ns (%.0f MHz)", AD9361_CLK_PERIOD_NS, 1000.0/AD9361_CLK_PERIOD_NS);
        $display("  COE Samples:         %0d", NUM_COE_SAMPLES);
        $display("  Reset Period:        1ms");
        $display("==============================================");

        // Wait for simulation to complete or timeout
        // Normal completion via GPIO auto-terminate (~2ms post-reset).
        // This timeout is a safety net only.
        #10_000_000;  // 10ms timeout

        $display("");
        $display("==============================================");
        $display("  Simulation timeout reached (10ms)");
        $display("  Total samples sent: %0d", samples_sent);
        $display("  WARNING: CPU did not signal PASS/FAIL via GPIO");
        $display("==============================================");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Optional: VCD Waveform Dump
    //--------------------------------------------------------------------------

    initial begin
        // Uncomment to enable VCD dump
        // $dumpfile("vivado_tb.vcd");
        // $dumpvars(0, vivado_tb);
    end

endmodule

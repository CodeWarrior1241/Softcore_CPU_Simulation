//------------------------------------------------------------------------------
// Vivado Testbench for NEORV32 + AD9361 Datapath Simulation
//------------------------------------------------------------------------------
//
// This testbench instantiates the Top_wrapper block design and provides:
//   - Clock generation (300MHz differential input for PLL)
//   - Reset sequencing (10ms reset period for CPU initialization)
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
//  |  LVDS RX        +-------------+         +-------------+    LVDS TX     |
//  |  ------+------->| axi_ad9361  |         | axi_ad9361  |-----+------>   |
//  |  clk   |        | ADC Section |         | DAC Section |     |          |
//  |  frame |        +------+------+         +------+------+     | clk      |
//  |  data  |               |                       ^            | frame    |
//  |                        v                       |            | data     |
//  |                 +-------------+         +-------------+                |
//  |                 | util_wfifo  |         | util_rfifo  |                |
//  |                 | (ADC FIFO)  |         | (DAC FIFO)  |                |
//  |                 +------+------+         +------+------+                |
//  |                        |                       ^                       |
//  |                        v                       |                       |
//  |                 +-------------+         +-------------+                |
//  |                 | util_cpack2 |-------->| util_upack2 |                |
//  |                 | (pack 4ch)  | 64-bit  | (unpack 4ch)|                |
//  |                 +-------------+ data    +-------------+                |
//  |                                                                        |
//  |  +-------------+                                                       |
//  |  | NEORV32 CPU |---> UART TX (status monitoring)                       |
//  |  | (control)   |---> GPIO (up_enable, up_txnrx)                        |
//  |  +-------------+                                                       |
//  |                                                                        |
//  +------------------------------------------------------------------------+
//
//------------------------------------------------------------------------------
// Test Sequence
//------------------------------------------------------------------------------
//
//  1. Reset held for 10ms (CPU initialization)
//  2. PLL locks, clocks stable
//  3. CPU enables AD9361 via GPIO (up_enable=1, up_txnrx=1)
//  4. Testbench feeds COE data into LVDS RX (looped)
//  5. Data flows: RX -> ADC FIFO -> cpack2 -> upack2 -> DAC FIFO -> TX
//  6. After 2 full COE loops, testbench switches to TX->RX loopback mode
//  7. Data now circulates: TX -> loopback -> RX -> ... -> TX
//  8. Simulation runs for 50ms total
//
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module vivado_tb;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------

    // Clock periods
    parameter real ECS_CLK_PERIOD_NS = 3.333;    // 300 MHz input clock
    parameter real AD9361_CLK_PERIOD_NS = 8.0;   // 125 MHz AD9361 data clock

    // Simulation timing
    parameter RESET_HOLD_NS = 10_000_000;        // 10ms reset hold for CPU init

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

    // Delay clock (300MHz for IODELAY calibration)
    reg delay_clk;

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
        .txnrx                  (txnrx),

        // Delay clock
        .delay_clk              (delay_clk)
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
    // Clock Generation: Delay Clock (300MHz)
    //--------------------------------------------------------------------------

    initial begin
        delay_clk = 1'b0;
    end

    always begin
        #(ECS_CLK_PERIOD_NS / 2.0);
        delay_clk = ~delay_clk;
    end

    //--------------------------------------------------------------------------
    // Load COE Data at Startup
    //--------------------------------------------------------------------------

    initial begin
        // Load COE file data
        // Note: $readmemh expects hex values without the header
        $readmemh("qpsk_bram_data.hex", coe_data);
        $display("[%0t] Loaded %0d samples from COE data", $time, NUM_COE_SAMPLES);
    end

    //--------------------------------------------------------------------------
    // Reset Sequence
    //--------------------------------------------------------------------------

    initial begin
        // Start with reset asserted
        system_resetn = 1'b0;

        // Hold reset for 10ms to allow CPU initialization
        #RESET_HOLD_NS;
        system_resetn = 1'b1;

        $display("[%0t] Reset released after 10ms", $time);
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
        $display("  Reset Period:        10ms");
        $display("==============================================");

        // Wait for simulation to complete or timeout
        // 50ms should be enough for multiple loops of 1024 samples
        #50_000_000;  // 50ms timeout

        $display("");
        $display("==============================================");
        $display("  Simulation timeout reached (50ms)");
        $display("  Total samples sent: %0d", samples_sent);
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

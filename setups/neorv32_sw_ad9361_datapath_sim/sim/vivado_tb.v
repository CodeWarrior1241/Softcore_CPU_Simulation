//------------------------------------------------------------------------------
// Vivado Testbench for NEORV32 + AD9361 Datapath Simulation
//------------------------------------------------------------------------------
//
// This testbench instantiates the Top_wrapper block design and provides:
//   - Clock generation (300MHz differential input for PLL)
//   - Reset sequencing
//   - AD9361 LVDS stimulus (RX path) and monitoring (TX path)
//   - UART monitoring
//
// The testbench generates a simple LVDS clock and data pattern to exercise
// the AD9361 receive path. The transmit path outputs can be monitored.
//
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module vivado_tb;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------

    // Clock periods
    parameter real ECS_CLK_PERIOD_NS = 3.333;    // 300 MHz input clock
    parameter real AD9361_CLK_PERIOD_NS = 8.0;   // 125 MHz AD9361 data clock (example)

    // Simulation timing
    parameter RESET_HOLD_NS = 100;
    parameter RESET_RELEASE_NS = 500;

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

    // AD9361 LVDS RX interface (from testbench to DUT)
    reg        rx_clk_in_p;
    reg        rx_clk_in_n;
    reg        rx_frame_in_p;
    reg        rx_frame_in_n;
    reg  [5:0] rx_data_in_p;
    reg  [5:0] rx_data_in_n;

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
        #(ECS_CLK_PERIOD_NS / 2.0);  // Same as ECS clock (300MHz)
        delay_clk = ~delay_clk;
    end

    //--------------------------------------------------------------------------
    // Clock Generation: AD9361 LVDS RX Clock
    //--------------------------------------------------------------------------

    initial begin
        rx_clk_in_p = 1'b0;
        rx_clk_in_n = 1'b1;
    end

    always begin
        #(AD9361_CLK_PERIOD_NS / 2.0);
        rx_clk_in_p = ~rx_clk_in_p;
        rx_clk_in_n = ~rx_clk_in_n;
    end

    //--------------------------------------------------------------------------
    // Reset Sequence
    //--------------------------------------------------------------------------

    initial begin
        // Start with reset asserted
        system_resetn = 1'b0;

        // Hold reset for specified time
        #RESET_HOLD_NS;

        // Release reset
        #(RESET_RELEASE_NS - RESET_HOLD_NS);
        system_resetn = 1'b1;

        $display("[%0t] Reset released", $time);
    end

    //--------------------------------------------------------------------------
    // UART Initialization
    //--------------------------------------------------------------------------

    initial begin
        uart0_rxd = 1'b1;  // Idle high
    end

    //--------------------------------------------------------------------------
    // AD9361 RX Data Generation
    //--------------------------------------------------------------------------
    //
    // In DDR LVDS mode, the AD9361 sends:
    //   - 6 data bits per clock edge (12 bits per clock cycle)
    //   - Frame signal indicates I/Q boundaries
    //
    // For simplicity, this testbench generates a simple incrementing pattern.
    // The actual data format depends on AD9361 configuration (1R1T vs 2R2T mode).
    //
    //--------------------------------------------------------------------------

    reg [11:0] rx_sample_counter;
    reg        rx_frame_state;

    initial begin
        rx_data_in_p  = 6'h00;
        rx_data_in_n  = 6'h3F;
        rx_frame_in_p = 1'b0;
        rx_frame_in_n = 1'b1;
        rx_sample_counter = 12'h000;
        rx_frame_state = 1'b0;
    end

    // Generate RX data on both edges of rx_clk_in_p
    always @(posedge rx_clk_in_p or negedge rx_clk_in_p) begin
        if (system_resetn) begin
            // Simple incrementing pattern
            rx_sample_counter <= rx_sample_counter + 1;

            // Toggle frame every clock cycle (simplified)
            rx_frame_state <= ~rx_frame_state;
            rx_frame_in_p <= rx_frame_state;
            rx_frame_in_n <= ~rx_frame_state;

            // Output lower 6 bits of counter as data
            rx_data_in_p <= rx_sample_counter[5:0];
            rx_data_in_n <= ~rx_sample_counter[5:0];
        end
    end

    //--------------------------------------------------------------------------
    // TX Data Monitoring
    //--------------------------------------------------------------------------

    always @(posedge tx_clk_out_p) begin
        if (system_resetn && sim_clock_100MHz_locked) begin
            // Monitor TX data (optional - for debug)
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
        $display("  NEORV32 + AD9361 Datapath Simulation");
        $display("==============================================");
        $display("  ECS Clock Period:    %0.3f ns (%.0f MHz)", ECS_CLK_PERIOD_NS, 1000.0/ECS_CLK_PERIOD_NS);
        $display("  AD9361 Clock Period: %0.3f ns (%.0f MHz)", AD9361_CLK_PERIOD_NS, 1000.0/AD9361_CLK_PERIOD_NS);
        $display("==============================================");

        // Wait for simulation to complete or timeout
        // Adjust timeout based on your test requirements
        #10000000;  // 10ms default timeout

        $display("");
        $display("==============================================");
        $display("  Simulation timeout reached");
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

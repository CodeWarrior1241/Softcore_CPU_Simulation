//------------------------------------------------------------------------------
// Questa Testbench for NEORV32 + AD9361 Datapath Simulation — Microchip
// PolarFire (mpf300) variant of ../neorv32_sw_ad9361_datapath_sim/sim/vivado_tb.v.
//
// Same test as the Xilinx 5.7 simulation — the DUT is the mpf300 FMCOMMS2
// system (mpf300_sim_top: NEORV32 + PULP axi_lite_xbar interconnect +
// axi_ad9361 PolarFire LVDS + SmartHLS adapters + open-logic CDC FIFOs /
// resets), booted with the ad9361_loopback firmware built for the SmartHLS
// bridge register map (make SMARTHLS_BRIDGE_MAP=1 MARCH=rv32im_zicsr_zifencei)
// and the PR #1603 pipelined fast multiplier enabled in the CPU.
//
// Testbench provides (as on Xilinx):
//   - Clock generation (50 MHz board oscillator for the PF_CCC)
//   - Reset sequencing (1 ms reset hold)
//   - AD9361 LVDS stimulus from COE file data (looped continuously)
//   - TX to RX loopback after 2 full COE passes
//   - gpio_o[9] SLEEP lever emulation (parks stim_clk, killing l_clk)
//   - UART monitoring, GPIO milestone/result monitoring, auto-terminate
//
// Deltas from the Xilinx TB (all platform-driven):
//   - refclk: 50 MHz single-ended (PF_CCC reference) instead of the 300 MHz
//     ECS differential pair; CPU/fabric clock is 125 MHz instead of 150 MHz
//     (UART timing is baud-derived and unchanged).
//   - GPIO observed via the sim-only sim_gpio_o port instead of hierarchical
//     references into the Vivado block design.
//   - dac_sync_enable force path: dut.axi_ad9361_0 (flat sim top) instead of
//     dut.Top_i.axi_ad9361.inst.
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module mpf300_tb;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------

    parameter real REF_CLK_PERIOD_NS = 20.0;      // 50 MHz board oscillator
    parameter real AD9361_CLK_PERIOD_NS = 8.0;    // 125 MHz AD9361 data clock

    parameter RESET_HOLD_NS = 1_000_000;          // 1ms reset hold

    parameter NUM_COE_SAMPLES = 1024;

    //--------------------------------------------------------------------------
    // Testbench Signals
    //--------------------------------------------------------------------------

    reg  ref_clk_50mhz;
    reg  system_resetn;

    wire uart0_txd;
    reg  uart0_rxd;

    // AD9361 LVDS RX interface
    wire       rx_clk_in_p, rx_clk_in_n;
    wire       rx_frame_in_p, rx_frame_in_n;
    wire [5:0] rx_data_in_p, rx_data_in_n;

    // AD9361 LVDS TX interface
    wire        tx_clk_out_p, tx_clk_out_n;
    wire        tx_frame_out_p, tx_frame_out_n;
    wire  [5:0] tx_data_out_p, tx_data_out_n;

    wire enable, txnrx;

    // sim observation ports
    wire        sim_clk_125mhz_locked;
    wire        sim_clk_125mhz;
    wire [15:0] sim_gpio_o;

    //--------------------------------------------------------------------------
    // COE Data Storage and Stimulus Generation
    //--------------------------------------------------------------------------

    reg [31:0] coe_data [0:NUM_COE_SAMPLES-1];

    reg        stim_clk;
    reg        stim_frame_p, stim_frame_n;
    reg  [5:0] stim_data_p, stim_data_n;

    reg [9:0]  coe_index;
    reg [15:0] current_i, current_q;

    reg        loopback_mode;
    integer    samples_sent;

    //--------------------------------------------------------------------------
    // RX MUX: Select between stimulus and loopback
    //--------------------------------------------------------------------------
    // RX clock always from the free-running stimulus clock (external SSI
    // clock); only frame and data are muxed for loopback (see the Xilinx TB
    // for the closed-loop bootstrap rationale).

    assign rx_clk_in_p   = stim_clk;
    assign rx_clk_in_n   = ~stim_clk;
    assign rx_frame_in_p = loopback_mode ? tx_frame_out_p : stim_frame_p;
    assign rx_frame_in_n = loopback_mode ? tx_frame_out_n : stim_frame_n;
    assign rx_data_in_p  = loopback_mode ? tx_data_out_p  : stim_data_p;
    assign rx_data_in_n  = loopback_mode ? tx_data_out_n  : stim_data_n;

    //--------------------------------------------------------------------------
    // DUT Instantiation
    //--------------------------------------------------------------------------

    mpf300_sim_top dut (
        .ref_clk_50mhz   (ref_clk_50mhz),
        .sys_resetn      (system_resetn),
        .sys_uart_rx     (uart0_rxd),
        .sys_uart_tx     (uart0_txd),
        .spi_clk         (),
        .spi_mosi        (),
        .spi_miso        (1'b0),
        .spi_csn_0       (),
        .gpio_resetb     (),
        .gpio_sync       (),
        .gpio_en_agc     (),
        .gpio_ctl        (),
        .gpio_status     (8'h00),
        .rx_clk_in_p     (rx_clk_in_p),
        .rx_clk_in_n     (rx_clk_in_n),
        .rx_frame_in_p   (rx_frame_in_p),
        .rx_frame_in_n   (rx_frame_in_n),
        .rx_data_in_p    (rx_data_in_p),
        .rx_data_in_n    (rx_data_in_n),
        .tx_clk_out_p    (tx_clk_out_p),
        .tx_clk_out_n    (tx_clk_out_n),
        .tx_frame_out_p  (tx_frame_out_p),
        .tx_frame_out_n  (tx_frame_out_n),
        .tx_data_out_p   (tx_data_out_p),
        .tx_data_out_n   (tx_data_out_n),
        .enable          (enable),
        .txnrx           (txnrx),
        .sim_gpio_o      (sim_gpio_o),
        .sim_clk_125mhz  (sim_clk_125mhz),
        .sim_clk_125mhz_locked (sim_clk_125mhz_locked)
    );

    //--------------------------------------------------------------------------
    // Clock Generation: 50 MHz board oscillator
    //--------------------------------------------------------------------------

    initial ref_clk_50mhz = 1'b0;
    always #(REF_CLK_PERIOD_NS / 2.0) ref_clk_50mhz = ~ref_clk_50mhz;

    //--------------------------------------------------------------------------
    // Load COE Data at Startup
    //--------------------------------------------------------------------------

    initial begin
        $readmemh("qpsk_bram_data.hex", coe_data);
        if (coe_data[0] === 32'bx) begin
            $error("Failed to load qpsk_bram_data.hex! Copy it from ../neorv32_sw_ad9361_datapath_sim/sim/");
            $fatal;
        end
        $display("[%0t] Loaded %0d samples from COE data", $time, NUM_COE_SAMPLES);
    end

    //--------------------------------------------------------------------------
    // Reset Sequence
    //--------------------------------------------------------------------------

    initial begin
        system_resetn = 1'b0;
        #RESET_HOLD_NS;
        system_resetn = 1'b1;
        $display("[%0t] Reset released after 1ms", $time);
    end

    //--------------------------------------------------------------------------
    // DAC Sync Enable Force (same rationale as the Xilinx TB / ADI ref TB)
    //--------------------------------------------------------------------------

    initial begin
        wait(system_resetn && sim_clk_125mhz_locked);
        #100;
        force dut.axi_ad9361_0.dac_sync_enable = 1'b1;
        $display("[%0t] Forced dac_sync_enable=1 for loopback mode", $time);
    end

    //--------------------------------------------------------------------------
    // UART Initialization
    //--------------------------------------------------------------------------

    initial uart0_rxd = 1'b1;  // Idle high

    //--------------------------------------------------------------------------
    // AD9361 RX Data Generation from COE File (DDR LVDS 1R1T framing)
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
        loopback_mode = 1'b0;
        samples_sent = 0;
    end

    always begin
        wait(system_resetn && sim_clk_125mhz_locked);
        #1000;

        forever begin
            // SLEEP model: gpio_o[9] is the firmware's TB-only "chip clock
            // stopped" lever (see the Xilinx TB for the full rationale) —
            // park stim_clk (= rx_clk_in = DATA_CLK) until the firmware
            // brings the clock back.
            if (sim_gpio_o[9]) begin
                stim_clk = 1'b0;
                wait (!sim_gpio_o[9]);
            end

            current_i = coe_data[coe_index][15:0];
            current_q = coe_data[coe_index][31:16];

            // I sample (frame high): upper 6 bits on rising edge
            stim_frame_p = 1'b1;
            stim_frame_n = 1'b0;
            stim_data_p = current_i[15:10];
            stim_data_n = ~current_i[15:10];
            #(AD9361_CLK_PERIOD_NS / 2.0);
            stim_clk = 1'b1;

            // lower 6 bits of I on falling edge
            stim_data_p = current_i[9:4];
            stim_data_n = ~current_i[9:4];
            #(AD9361_CLK_PERIOD_NS / 2.0);
            stim_clk = 1'b0;

            // Q sample (frame low): upper 6 bits on rising edge
            stim_frame_p = 1'b0;
            stim_frame_n = 1'b1;
            stim_data_p = current_q[15:10];
            stim_data_n = ~current_q[15:10];
            #(AD9361_CLK_PERIOD_NS / 2.0);
            stim_clk = 1'b1;

            // lower 6 bits of Q on falling edge
            stim_data_p = current_q[9:4];
            stim_data_n = ~current_q[9:4];
            #(AD9361_CLK_PERIOD_NS / 2.0);
            stim_clk = 1'b0;

            samples_sent = samples_sent + 1;
            coe_index = coe_index + 1;
            if (coe_index >= NUM_COE_SAMPLES)
                coe_index = 0;

            if (samples_sent == NUM_COE_SAMPLES * 2) begin
                $display("[%0t] Switching to TX->RX loopback mode", $time);
                loopback_mode = 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Status Monitors
    //--------------------------------------------------------------------------

    reg pll_locked_prev;
    always @(posedge sim_clk_125mhz) begin
        pll_locked_prev <= sim_clk_125mhz_locked;
        if (sim_clk_125mhz_locked && !pll_locked_prev)
            $display("[%0t] PLL locked", $time);
    end

    // l_clk recovery
    reg first_lclk_seen;
    integer lclk_edge_count;
    initial begin first_lclk_seen = 0; lclk_edge_count = 0; end
    always @(posedge dut.axi_ad9361_0.l_clk) begin
        if (system_resetn) begin
            lclk_edge_count <= lclk_edge_count + 1;
            if (!first_lclk_seen) begin
                first_lclk_seen <= 1;
                $display("[%0t] l_clk recovered (125 MHz)", $time);
            end
        end
    end

    // l_clk death detector — the WARNING is EXPECTED once during the directed
    // power-gate window (see the Xilinx TB)
    reg [31:0] lclk_last_count;
    initial lclk_last_count = 0;
    always begin
        #1_000_000;
        if (lclk_edge_count == lclk_last_count && first_lclk_seen)
            $display("[%0t] WARNING: l_clk stopped (no edges in last 1ms)", $time);
        lclk_last_count = lclk_edge_count;
    end

    //--------------------------------------------------------------------------
    // GPIO Result Monitor — auto-terminate on CPU PASS/FAIL
    //--------------------------------------------------------------------------

    reg result_valid_prev;
    always @(posedge sim_clk_125mhz) begin
        result_valid_prev <= sim_gpio_o[6];
        if (sim_gpio_o[6] && !result_valid_prev) begin
            if (sim_gpio_o[5]) begin
                $display("[%0t] TEST PASSED (GPIO result)", $time);
            end else begin
                $display("[%0t] TEST FAILED (GPIO result)", $time);
            end
            $display("  Total samples sent: %0d", samples_sent);
            #100;
            $finish;
        end
    end

    // GPIO milestone monitors
    reg [7:0] gpio_prev;
    always @(posedge sim_clk_125mhz) begin
        gpio_prev <= sim_gpio_o[7:0];
        if (sim_gpio_o[2] && !gpio_prev[2])
            $display("[%0t] MILESTONE: AD9361 core configured (GPIO[2])", $time);
        if (sim_gpio_o[3] && !gpio_prev[3])
            $display("[%0t] MILESTONE: TX burst complete (GPIO[3])", $time);
        if (sim_gpio_o[4] && !gpio_prev[4])
            $display("[%0t] MILESTONE: RX readback done (GPIO[4])", $time);
    end

    //--------------------------------------------------------------------------
    // UART TX Monitoring (115200 baud, clock-independent bit timing)
    //--------------------------------------------------------------------------

    parameter UART_BIT_PERIOD_NS = 8680;

    reg [7:0] uart_rx_byte;
    reg [3:0] uart_rx_bit_count;
    reg       uart_rx_active;

    initial begin
        uart_rx_active = 1'b0;
        uart_rx_bit_count = 0;
        uart_rx_byte = 8'h00;
    end

    always @(negedge uart0_txd) begin
        if (!uart_rx_active && system_resetn) begin
            uart_rx_active <= 1'b1;
            uart_rx_bit_count <= 0;
            #(UART_BIT_PERIOD_NS * 1.5);
            repeat (8) begin
                uart_rx_byte[uart_rx_bit_count] <= uart0_txd;
                uart_rx_bit_count <= uart_rx_bit_count + 1;
                #UART_BIT_PERIOD_NS;
            end
            #(UART_BIT_PERIOD_NS / 2);
            if (uart_rx_byte >= 8'h20 && uart_rx_byte <= 8'h7E) begin
                $write("%c", uart_rx_byte);
            end else if (uart_rx_byte == 8'h0A) begin
                $write("\n");
            end else if (uart_rx_byte == 8'h0D) begin
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
        $display("  Microchip PolarFire (mpf300) system");
        $display("==============================================");
        $display("  Ref Clock Period:    %0.3f ns (%.0f MHz)", REF_CLK_PERIOD_NS, 1000.0/REF_CLK_PERIOD_NS);
        $display("  AD9361 Clock Period: %0.3f ns (%.0f MHz)", AD9361_CLK_PERIOD_NS, 1000.0/AD9361_CLK_PERIOD_NS);
        $display("  COE Samples:         %0d", NUM_COE_SAMPLES);
        $display("  Reset Period:        1ms");
        $display("==============================================");

        // Safety-net timeout only — normal completion is the GPIO
        // auto-terminate.  The 125 MHz CPU makes the calibrated firmware
        // busy-loops ~20%% longer than on the 150 MHz Xilinx system, still
        // well inside 20 ms.
        #20_000_000;

        $display("");
        $display("==============================================");
        $display("  Simulation timeout reached (20ms)");
        $display("  Total samples sent: %0d", samples_sent);
        $display("  WARNING: CPU did not signal PASS/FAIL via GPIO");
        $display("==============================================");
        $finish;
    end

endmodule

//==============================================================================
// tb_top.sv
//
// Testbench for AD9361 datapath simulation (Verilator --timing).
//
//==============================================================================
// Scope: Datapath-only, no axi_ad9361 LVDS transceiver, no CPU
//==============================================================================
//
// This testbench exercises the STREAMING DATAPATH chain:
//   axi_ad9361_adapter -> CDC FIFOs -> axi_lite_to_streaming_adapter
// and its reverse TX path. The testbench acts as both the "CPU" (driving
// AXI-Lite) and the "AD9361 transceiver" (driving ADC / reading DAC).
//
//------------------------------------------------------------------------------
// What IS NOT simulated (and why)
//------------------------------------------------------------------------------
//
//   NEORV32 CPU + smartconnect + BRAM:
//     smartconnect fabric is encrypted (pragma protected). Use Questa.
//
//   axi_ad9361 (ADI LVDS transceiver):
//     Uses UNISIM primitives (IDELAYE3, IDDRE1, IDELAYCTRL, ISERDESE3)
//     whose always @(*) latch behavioral models cause infinite zero-delay
//     re-evaluation in Verilator's event engine, hanging the simulation.
//     The LVDS interface is covered by the Questa flow instead.
//
//   clk_wiz (PLLE4_ADV):
//     PLLE4_ADV behavioral model #delay lock timing does not work in
//     open-source simulators. Replaced with clk_wiz_behavioral.sv.
//
//   util_ad9361_lclk_reset (proc_sys_reset):
//     VHDL origin; sim_netlist includes duplicate glbl module.
//     Replaced with behavioral reset synchronizer in datapath_top.sv.
//
//------------------------------------------------------------------------------
// What IS simulated
//------------------------------------------------------------------------------
//
//   axi_ad9361_adapter    (HLS v5.0, behavioral RTL from impl/verilog)
//   TX CDC FIFO           (Xilinx axis_data_fifo, behavioral via XPM)
//   RX CDC FIFO           (Xilinx axis_data_fifo, behavioral via XPM)
//   axi_lite_to_streaming_adapter (HLS v3.0, behavioral RTL from impl/verilog)
//   clk_wiz               (behavioral replacement, clk_wiz_behavioral.sv)
//   150 MHz / 125 MHz reset synchronizers (behavioral, in datapath_top.sv)
//
//------------------------------------------------------------------------------
// Architecture
//------------------------------------------------------------------------------
//
//   TB (acts as CPU)               TB (acts as AD9361)
//     |                              |
//     | AXI-Lite (14-bit)            | ADC I/Q + valid/enable (125 MHz)
//     v                              v
//   +-----------------------------+  +-------------------+
//   | axi_lite_to_streaming_      |  | axi_ad9361_       |
//   | adapter (HLS, 150 MHz)      |  | adapter (HLS,     |
//   |   tx_stream -> TX CDC FIFO -+->|   125 MHz)        |
//   |   rx_stream <- RX CDC FIFO -+<-|                   |-> DAC I/Q to TB
//   +-----------------------------+  +-------------------+
//
//------------------------------------------------------------------------------
// Test sequence (mirrors sw/ad9361_loopback/main.c, minus AD9361 reg config)
//------------------------------------------------------------------------------
//
//   1. Release reset, wait for clk_150 PLL lock.
//   2. Enable ADC stimulus (drive adc_valid/enable + I/Q data from COE file).
//   3. Enable DAC requests (drive dac_valid/enable).
//   4. Load 1024 TX samples into bridge tx_data[] via AXI-Lite.
//   5. Pulse bridge enable, wait for state == RECEIVE.
//   6. For N cycles: poll rx_sample_count, read rx_data[], pulse rx_read_done.
//   7. Report PASS/FAIL.
//
//==============================================================================

`timescale 1ns / 1ps

module tb_top;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------
    parameter real CLK150_PERIOD_NS     = 6.667;   // 150 MHz
    parameter real L_CLK_PERIOD_NS      = 8.0;     // 125 MHz
    parameter real ECS_CLK_PERIOD_NS    = 3.333;   // 300 MHz (for clk_wiz input)
    parameter NUM_COE_SAMPLES       = 1024;
    parameter NUM_READBACK_CYCLES   = 3;

    // Bridge register offsets (14-bit addr, from axi_streaming_adapter_ctrl.h)
    parameter [13:0] BRIDGE_REG_ENABLE       = 14'h0010;
    parameter [13:0] BRIDGE_REG_RX_READ_DONE = 14'h0014;
    parameter [13:0] BRIDGE_REG_STATE        = 14'h0020;
    parameter [13:0] BRIDGE_REG_RX_COUNT     = 14'h0028;
    parameter [13:0] BRIDGE_TX_DATA_BASE     = 14'h1000;
    parameter [13:0] BRIDGE_RX_DATA_BASE     = 14'h2000;
    parameter [31:0] BRIDGE_STATE_RECEIVE    = 32'd3;

    //--------------------------------------------------------------------------
    // Clocks and reset
    //--------------------------------------------------------------------------
    reg ecs_clk_p = 0, ecs_clk_n = 1;
    always #(ECS_CLK_PERIOD_NS / 2.0) begin ecs_clk_p = ~ecs_clk_p; ecs_clk_n = ~ecs_clk_n; end

    reg l_clk = 0;
    always #(L_CLK_PERIOD_NS / 2.0) l_clk = ~l_clk;

    reg system_resetn = 0;

    // clk_wiz: 300 MHz diff in -> 150 MHz + locked
    wire clk_150, clk_300, clk_locked;
    Top_ECS_Clock_300MHz_0 clk_wiz (
        .clk_in1_p(ecs_clk_p), .clk_in1_n(ecs_clk_n),
        .resetn(system_resetn),
        .clk_out1(clk_150), .clk_out2(clk_300), .locked(clk_locked)
    );

    //--------------------------------------------------------------------------
    // ADC stimulus (TB acts as AD9361 transceiver)
    //--------------------------------------------------------------------------
    reg [15:0] adc_data_i0 = 0, adc_data_q0 = 0;
    reg [15:0] adc_data_i1 = 0, adc_data_q1 = 0;
    reg        adc_valid_i0 = 0, adc_valid_q0 = 0;
    reg        adc_valid_i1 = 0, adc_valid_q1 = 0;
    reg        adc_enable_i0 = 0, adc_enable_q0 = 0;
    reg        adc_enable_i1 = 0, adc_enable_q1 = 0;

    // DAC outputs (from adapter, TB reads)
    wire [15:0] dac_data_i0, dac_data_q0, dac_data_i1, dac_data_q1;
    wire        dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;
    wire        dac_enable_i0, dac_enable_q0, dac_enable_i1, dac_enable_q1;

    //--------------------------------------------------------------------------
    // AXI-Lite to streaming adapter (14-bit addr)
    //--------------------------------------------------------------------------
    reg  [13:0] bridge_awaddr = 0;
    reg         bridge_awvalid = 0;
    wire        bridge_awready;
    reg  [31:0] bridge_wdata = 0;
    reg   [3:0] bridge_wstrb = 4'hF;
    reg         bridge_wvalid = 0;
    wire        bridge_wready;
    wire  [1:0] bridge_bresp;
    wire        bridge_bvalid;
    reg         bridge_bready = 0;
    reg  [13:0] bridge_araddr = 0;
    reg         bridge_arvalid = 0;
    wire        bridge_arready;
    wire [31:0] bridge_rdata;
    wire  [1:0] bridge_rresp;
    wire        bridge_rvalid;
    reg         bridge_rready = 0;

    //--------------------------------------------------------------------------
    // COE data
    //--------------------------------------------------------------------------
    reg [31:0] coe_data [0:NUM_COE_SAMPLES-1];

    //--------------------------------------------------------------------------
    // DUT
    //--------------------------------------------------------------------------
    datapath_top dut (
        .clk_150        (clk_150),
        .clk_150_locked (clk_locked),
        .l_clk          (l_clk),
        .system_resetn  (system_resetn),

        .adc_data_i0    (adc_data_i0),
        .adc_data_q0    (adc_data_q0),
        .adc_data_i1    (adc_data_i1),
        .adc_data_q1    (adc_data_q1),
        .adc_valid_i0   (adc_valid_i0),
        .adc_valid_q0   (adc_valid_q0),
        .adc_valid_i1   (adc_valid_i1),
        .adc_valid_q1   (adc_valid_q1),
        .adc_enable_i0  (adc_enable_i0),
        .adc_enable_q0  (adc_enable_q0),
        .adc_enable_i1  (adc_enable_i1),
        .adc_enable_q1  (adc_enable_q1),

        .dac_data_i0    (dac_data_i0),
        .dac_data_q0    (dac_data_q0),
        .dac_data_i1    (dac_data_i1),
        .dac_data_q1    (dac_data_q1),
        .dac_valid_i0   (dac_valid_i0),
        .dac_valid_q0   (dac_valid_q0),
        .dac_valid_i1   (dac_valid_i1),
        .dac_valid_q1   (dac_valid_q1),
        .dac_enable_i0  (dac_enable_i0),
        .dac_enable_q0  (dac_enable_q0),
        .dac_enable_i1  (dac_enable_i1),
        .dac_enable_q1  (dac_enable_q1),

        .bridge_awaddr  (bridge_awaddr),
        .bridge_awvalid (bridge_awvalid),
        .bridge_awready (bridge_awready),
        .bridge_wdata   (bridge_wdata),
        .bridge_wstrb   (bridge_wstrb),
        .bridge_wvalid  (bridge_wvalid),
        .bridge_wready  (bridge_wready),
        .bridge_bresp   (bridge_bresp),
        .bridge_bvalid  (bridge_bvalid),
        .bridge_bready  (bridge_bready),
        .bridge_araddr  (bridge_araddr),
        .bridge_arvalid (bridge_arvalid),
        .bridge_arready (bridge_arready),
        .bridge_rdata   (bridge_rdata),
        .bridge_rresp   (bridge_rresp),
        .bridge_rvalid  (bridge_rvalid),
        .bridge_rready  (bridge_rready)
    );

    //--------------------------------------------------------------------------
    // Load COE data
    //--------------------------------------------------------------------------
    initial begin
        $readmemh("qpsk_bram_data.hex", coe_data);
        if (coe_data[0] === 32'bx) begin
            $display("ERROR: Failed to load qpsk_bram_data.hex");
            $finish;
        end
        $display("[%0t] Loaded %0d COE samples", $time, NUM_COE_SAMPLES);
    end

    //--------------------------------------------------------------------------
    // Reset
    //--------------------------------------------------------------------------
    initial begin
        system_resetn = 0;
        #200;  // 200 ns — behavioral clk_wiz locks in 16 cycles (~53 ns)
        system_resetn = 1;
        $display("[%0t] Reset released", $time);
    end

    //--------------------------------------------------------------------------
    // ADC stimulus: continuously feed COE data on l_clk (125 MHz)
    // Starts after reset + PLL lock, loops forever (same as axi_ad9361 would)
    //--------------------------------------------------------------------------
    integer coe_index;
    integer adc_samples_sent;
    always begin
        wait(system_resetn && clk_locked);
        @(posedge l_clk);

        adc_enable_i0 = 1; adc_enable_q0 = 1;
        adc_valid_i0  = 1; adc_valid_q0  = 1;
        coe_index = 0;
        adc_samples_sent = 0;

        $display("[%0t] ADC stimulus started (COE data on l_clk)", $time);

        forever begin
            adc_data_i0 = coe_data[coe_index][15:0];
            adc_data_q0 = coe_data[coe_index][31:16];
            @(posedge l_clk);

            adc_samples_sent = adc_samples_sent + 1;
            coe_index = coe_index + 1;
            if (coe_index >= NUM_COE_SAMPLES)
                coe_index = 0;
        end
    end

    //--------------------------------------------------------------------------
    // AXI-Lite helper tasks
    //--------------------------------------------------------------------------
    int axi_timeout;

    task bridge_write(input [13:0] addr, input [31:0] data);
        @(posedge clk_150);
        bridge_awaddr  = addr;
        bridge_awvalid = 1;
        bridge_wdata   = data;
        bridge_wstrb   = 4'hF;
        bridge_wvalid  = 1;
        bridge_bready  = 1;
        axi_timeout = 0;
        while (axi_timeout < 200) begin
            @(posedge clk_150);
            if (bridge_awready) bridge_awvalid = 0;
            if (bridge_wready)  bridge_wvalid  = 0;
            if (!bridge_awvalid && !bridge_wvalid) break;
            axi_timeout++;
        end
        axi_timeout = 0;
        while (!bridge_bvalid && axi_timeout < 200) begin
            @(posedge clk_150);
            axi_timeout++;
        end
        @(posedge clk_150);
        bridge_bready = 0;
    endtask

    task bridge_read(input [13:0] addr, output [31:0] data);
        @(posedge clk_150);
        bridge_araddr  = addr;
        bridge_arvalid = 1;
        bridge_rready  = 1;
        axi_timeout = 0;
        while (!bridge_arready && axi_timeout < 200) begin
            @(posedge clk_150);
            axi_timeout++;
        end
        @(posedge clk_150);
        bridge_arvalid = 0;
        axi_timeout = 0;
        while (!bridge_rvalid && axi_timeout < 200) begin
            @(posedge clk_150);
            axi_timeout++;
        end
        data = bridge_rdata;
        @(posedge clk_150);
        bridge_rready = 0;
    endtask

    task bridge_pulse(input [13:0] addr);
        bridge_write(addr, 32'h1);
        bridge_write(addr, 32'h0);
        repeat (5) @(posedge clk_150);
    endtask

    //--------------------------------------------------------------------------
    // Main test sequence (mirrors ad9361_loopback/main.c)
    //--------------------------------------------------------------------------
    int pass_count = 0;
    reg [31:0] rdata;

    initial begin
        $display("==============================================");
        $display("  AD9361 Datapath -- Verilator TB");
        $display("  No axi_ad9361, no CPU (see header)");
        $display("==============================================");

        // Wait for reset + PLL lock
        wait(system_resetn && clk_locked);
        repeat (20) @(posedge clk_150);
        $display("[%0t] PLL locked, resets released", $time);

        // ================================================================
        // Load 1024 TX samples
        // ================================================================
        $display("[%0t] Loading %0d TX samples ...", $time, NUM_COE_SAMPLES);
        for (int i = 0; i < NUM_COE_SAMPLES; i++) begin
            bridge_write(BRIDGE_TX_DATA_BASE + 14'(i * 4),
                         {16'(i + 16'h1000), 16'(i)});
        end

        // ================================================================
        // Pulse bridge enable, wait for RECEIVE state
        // ================================================================
        $display("[%0t] Pulsing bridge enable ...", $time);
        bridge_pulse(BRIDGE_REG_ENABLE);

        axi_timeout = 0;
        while (axi_timeout < 100000) begin
            bridge_read(BRIDGE_REG_STATE, rdata);
            if (rdata == BRIDGE_STATE_RECEIVE) break;
            axi_timeout++;
        end
        $display("[%0t] Bridge reached RECEIVE (after %0d polls)", $time, axi_timeout);

        // ================================================================
        // RX readback cycles
        // ================================================================
        $display("[%0t] Starting RX readback ...", $time);

        for (int cycle = 0; cycle < NUM_READBACK_CYCLES; cycle++) begin
            int nonzero, rx_ok;

            // Wait for RX buffer full
            rx_ok = 0;
            for (int j = 0; j < 500000; j++) begin
                bridge_read(BRIDGE_REG_RX_COUNT, rdata);
                if (rdata >= (NUM_COE_SAMPLES - 1)) begin
                    rx_ok = 1;
                    break;
                end
            end

            if (!rx_ok) begin
                $display("[%0t] cycle %0d: TIMEOUT", $time, cycle);
                continue;
            end

            nonzero = 0;
            for (int k = 0; k < NUM_COE_SAMPLES; k++) begin
                bridge_read(BRIDGE_RX_DATA_BASE + 14'(k * 4), rdata);
                if (rdata != 32'h0) nonzero++;
            end

            $display("[%0t] cycle %0d: nonzero=%0d / %0d",
                     $time, cycle, nonzero, NUM_COE_SAMPLES);

            if (nonzero > 0) pass_count++;
            bridge_pulse(BRIDGE_REG_RX_READ_DONE);
        end

        // ================================================================
        // Result
        // ================================================================
        $display("");
        $display("==============================================");
        if (pass_count == NUM_READBACK_CYCLES)
            $display("  TEST PASSED");
        else
            $display("  TEST FAILED (pass_count = %0d / %0d)",
                     pass_count, NUM_READBACK_CYCLES);
        $display("  ADC samples sent: %0d", adc_samples_sent);
        $display("==============================================");
        #1000;
        $finish;
    end

    //--------------------------------------------------------------------------
    // Watchdog
    //--------------------------------------------------------------------------
    initial begin
        #5_000_000;  // 5 ms
        $display("WATCHDOG: timeout (5 ms)");
        $display("  pass_count = %0d / %0d", pass_count, NUM_READBACK_CYCLES);
        $finish;
    end

endmodule

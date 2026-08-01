//==============================================================================
// datapath_top.sv
//
// Datapath-only top-level for Verilator simulation — Microchip PolarFire
// (mpf300) variant. Same module name and port list as the Xilinx variant in
// ../verilator_sim/datapath_top.sv, so tb_top.sv instantiates it
// unchanged; the internals are the mpf300 FMCOMMS2 components
// (deps/hdl/projects/fmcomms2/mpf300):
//
//   axi_lite_to_streaming_adapter_top   SmartHLS RTL
//                                       (src/axi_lite_to_streaming_adapter_microchip)
//   axi_ad9361_adapter_top              SmartHLS RTL
//                                       (src/axi_ad9361_adapter_microchip)
//   axis_async_fifo x2                  mpf300 CDC FIFO (open-logic
//                                       olo_base_fifo_async; behavioral SV
//                                       model in this directory)
//   dac_hold                            mpf300 DAC holding registers
//
// Instantiates the streaming chain WITHOUT axi_ad9361 (the PolarFire LVDS
// transceiver is covered by the QuestaSim flow in
// deps/hdl/library/axi_ad9361/sim/microchip); the testbench drives the
// adapter's ADC ports directly and reads the DAC holding registers,
// bypassing the LVDS layer entirely — the same scope as the Xilinx variant.
//
//------------------------------------------------------------------------------
// Differences from the Xilinx variant (all driven by the SmartHLS port
// conventions and mpf300 topology; the TB-facing ports are unchanged)
//------------------------------------------------------------------------------
//
//   * "clk_150" is the mpf300 CPU/AXI fabric clock, which runs at 125 MHz
//     (PF_CCC OUT0_FABCLK_0); the port keeps its Xilinx-era name so the TB
//     diff stays minimal. The TB sets CLK150_PERIOD_NS = 8.0.
//
//   * The SmartHLS bridge exposes a 32-bit-address AXI4 subset
//     (axi_aw_*/axi_w_*/axi_b_*/axi_ar_*/axi_r_*) instead of the Vitis
//     s_axi_ctrl AXI4-Lite port. The TB's 14-bit-offset AXI-Lite master is
//     adapted here: address zero-extended, single-beat burst fields tied
//     (len=0, size=4-byte, INCR), WLAST tied high, RLAST consumed.
//
//   * The SmartHLS adapters use start/ready/finish handshakes — start is
//     tied high, as in the mpf300 SmartDesign (free-running II=1).
//
//   * The SmartHLS ad9361 adapter's dac_valid_*/dac_enable_* are INPUTS
//     (driven by axi_ad9361 in the real system). This wrapper generates
//     them — enable held high, valid pulsed at 1/1 duty (one sample every
//     two l_clk cycles, the 1R1T DDR LVDS cadence) — and mirrors them on
//     the TB-facing output ports, which the Vitis adapter drove itself.
//
//   * DAC samples leave the SmartHLS adapter as write_en/write_data pulse
//     pairs; the mpf300 dac_hold block converts them to the level-held
//     dac_data_* buses the TB port list expects.
//
//   * The reset blocks are the REAL project RTL: sys_ctrl and
//     lclk_reset_sync, pure SystemVerilog since the Bedrock-RTL migration
//     (mpf300_reset_gen + br_cdc_bit_toggle; see doc/MPF300-Splash-Kit/
//     bedrock_migration_design.md). Earlier revisions modeled them
//     behaviorally here because their open-logic internals were VHDL,
//     which Verilator cannot compile.
//==============================================================================

`timescale 1ns / 1ps

module datapath_top (
    // CPU/AXI fabric clock domain (from behavioral PF_CCC; 125 MHz on mpf300)
    input  wire        clk_150,
    input  wire        clk_150_locked,

    // 125 MHz clock domain (TB provides this directly, replacing axi_ad9361 l_clk)
    input  wire        l_clk,
    input  wire        system_resetn,

    // ADC interface (TB drives, replacing axi_ad9361 ADC outputs)
    input  wire [15:0] adc_data_i0,
    input  wire [15:0] adc_data_q0,
    input  wire [15:0] adc_data_i1,
    input  wire [15:0] adc_data_q1,
    input  wire        adc_valid_i0,
    input  wire        adc_valid_q0,
    input  wire        adc_valid_i1,
    input  wire        adc_valid_q1,
    input  wire        adc_enable_i0,
    input  wire        adc_enable_q0,
    input  wire        adc_enable_i1,
    input  wire        adc_enable_q1,

    // DAC interface (TB reads; data is level-held by dac_hold, valid/enable
    // are generated here and mirrored out)
    output wire [15:0] dac_data_i0,
    output wire [15:0] dac_data_q0,
    output wire [15:0] dac_data_i1,
    output wire [15:0] dac_data_q1,
    output wire        dac_valid_i0,
    output wire        dac_valid_q0,
    output wire        dac_valid_i1,
    output wire        dac_valid_q1,
    output wire        dac_enable_i0,
    output wire        dac_enable_q0,
    output wire        dac_enable_i1,
    output wire        dac_enable_q1,

    // AXI-Lite to streaming adapter (14-bit addr, adapted to the SmartHLS
    // AXI4-subset port below)
    input  wire [13:0] bridge_awaddr,
    input  wire        bridge_awvalid,
    output wire        bridge_awready,
    input  wire [31:0] bridge_wdata,
    input  wire  [3:0] bridge_wstrb,
    input  wire        bridge_wvalid,
    output wire        bridge_wready,
    output wire  [1:0] bridge_bresp,
    output wire        bridge_bvalid,
    input  wire        bridge_bready,
    input  wire [13:0] bridge_araddr,
    input  wire        bridge_arvalid,
    output wire        bridge_arready,
    output wire [31:0] bridge_rdata,
    output wire  [1:0] bridge_rresp,
    output wire        bridge_rvalid,
    input  wire        bridge_rready
);

    //--------------------------------------------------------------------------
    // Reset generation — the REAL mpf300 blocks (sys_ctrl + lclk_reset_sync,
    // pure SV since the Bedrock-RTL migration; previously modeled
    // behaviorally here because their open-logic internals were VHDL).
    // Tie-offs mirror mpf300_sim_top.v with no CPU present: init flags true,
    // gpio_o all-zero (pwr_dn = 0, so aresetn_gated == sys_resetn).
    //--------------------------------------------------------------------------
    wire sys_resetn, sys_reset, aresetn_gated, pwr_dn;

    sys_ctrl sys_ctrl_0 (
        .clk            (clk_150),
        .pll_lock       (clk_150_locked),
        .init_done      (1'b1),
        .sram_init_done (1'b1),
        .ext_resetn     (system_resetn),
        .gpio_o         (16'h0000),
        .spi_csn_i      (8'hFF),
        .sys_resetn     (sys_resetn),
        .sys_reset      (sys_reset),
        .aresetn_gated  (aresetn_gated),
        .pwr_dn         (pwr_dn),
        .up_enable      (),
        .up_txnrx       (),
        .gpio_resetb    (),
        .gpio_sync      (),
        .gpio_en_agc    (),
        .gpio_ctl       (),
        .spi_csn_0      ()
    );

    wire lclk_resetn, lclk_reset;

    lclk_reset_sync lclk_reset_sync_0 (
        .l_clk       (l_clk),
        .clk_125     (clk_150),
        .ext_resetn  (sys_resetn),
        .pwr_dn      (pwr_dn),
        .lclk_resetn (lclk_resetn),
        .lclk_reset  (lclk_reset)
    );

    // Domain resets under the names the rest of this file (and the Xilinx
    // variant) uses. pwr_dn = 0 makes aresetn_gated == sys_resetn, so the
    // FIFO reset wiring below matches mpf300_sim_top.v for both FIFOs.
    wire cpu_aresetn  = aresetn_gated;
    wire lclk_aresetn = lclk_resetn;

    //--------------------------------------------------------------------------
    // DAC valid/enable generation (axi_ad9361 stand-in, l_clk domain)
    //--------------------------------------------------------------------------
    // The SmartHLS adapter samples its dac_valid_* inputs the way the real
    // axi_ad9361 core drives them: one request every two l_clk cycles in
    // 1R1T DDR LVDS mode. The Vitis adapter drove these as outputs, so the
    // TB only observes them.
    reg dac_valid_r = 1'b0;
    always @(posedge l_clk) begin
        if (!lclk_aresetn)
            dac_valid_r <= 1'b0;
        else
            dac_valid_r <= ~dac_valid_r;
    end

    assign dac_valid_i0 = dac_valid_r;
    assign dac_valid_q0 = dac_valid_r;
    assign dac_valid_i1 = dac_valid_r;
    assign dac_valid_q1 = dac_valid_r;

    assign dac_enable_i0 = lclk_aresetn;
    assign dac_enable_q0 = lclk_aresetn;
    assign dac_enable_i1 = lclk_aresetn;
    assign dac_enable_q1 = lclk_aresetn;

    //--------------------------------------------------------------------------
    // AXI-Stream wires
    //--------------------------------------------------------------------------
    // streaming_adapter tx_stream (fabric clk) -> TX CDC FIFO S_AXIS
    wire [31:0] sa_tx_tdata;
    wire  [3:0] sa_tx_tkeep, sa_tx_tstrb;
    wire        sa_tx_tlast, sa_tx_tvalid, sa_tx_tready;

    // TX CDC FIFO M_AXIS (l_clk) -> ad9361_adapter tx_stream
    wire [31:0] adp_tx_tdata;
    wire  [3:0] adp_tx_tkeep, adp_tx_tstrb;
    wire        adp_tx_tlast, adp_tx_tvalid, adp_tx_tready;

    // ad9361_adapter rx_stream (l_clk) -> RX CDC FIFO S_AXIS
    wire [31:0] adp_rx_tdata;
    wire  [3:0] adp_rx_tkeep, adp_rx_tstrb;
    wire        adp_rx_tlast, adp_rx_tvalid, adp_rx_tready;

    // RX CDC FIFO M_AXIS (fabric clk) -> streaming_adapter rx_stream
    wire [31:0] sa_rx_tdata;
    wire  [3:0] sa_rx_tkeep, sa_rx_tstrb;
    wire        sa_rx_tlast, sa_rx_tvalid, sa_rx_tready;

    //--------------------------------------------------------------------------
    // axi_lite_to_streaming_adapter (SmartHLS, fabric clock)
    //--------------------------------------------------------------------------
    // TB AXI-Lite -> SmartHLS AXI4 subset: zero-extended address,
    // single-beat burst fields, WLAST high, RLAST consumed (the SmartHLS
    // core decodes its full address, so it must be given window offsets;
    // the map itself is identical to the Vitis layout — proven by
    // the unit TB in src/axi_lite_to_streaming_adapter_microchip/verilator_sim).
    wire sa_ready, sa_finish;
    wire sa_r_last;

    axi_lite_to_streaming_adapter_top streaming_adapter_inst (
        .clk              (clk_150),
        .reset            (~cpu_aresetn),      // SmartHLS: sync, active high
        .start            (1'b1),              // free-running, as in SmartDesign
        .ready            (sa_ready),
        .finish           (sa_finish),
        .axi_aw_addr      ({18'b0, bridge_awaddr}),
        .axi_aw_ready     (bridge_awready),
        .axi_aw_valid     (bridge_awvalid),
        .axi_aw_burst     (2'b01),             // INCR
        .axi_aw_size      (3'd2),              // 4 bytes
        .axi_aw_len       (8'd0),              // single-beat
        .axi_ar_addr      ({18'b0, bridge_araddr}),
        .axi_ar_ready     (bridge_arready),
        .axi_ar_valid     (bridge_arvalid),
        .axi_ar_burst     (2'b01),
        .axi_ar_size      (3'd2),
        .axi_ar_len       (8'd0),
        .tx_stream_data   (sa_tx_tdata),
        .tx_stream_ready  (sa_tx_tready),
        .tx_stream_valid  (sa_tx_tvalid),
        .tx_stream_keep   (sa_tx_tkeep),
        .tx_stream_strb   (sa_tx_tstrb),
        .tx_stream_last   (sa_tx_tlast),
        .axi_w_data       (bridge_wdata),
        .axi_w_ready      (bridge_wready),
        .axi_w_valid      (bridge_wvalid),
        .axi_w_strb       (bridge_wstrb),
        .axi_w_last       (1'b1),
        .axi_b_resp       (bridge_bresp),
        .axi_b_resp_ready (bridge_bready),
        .axi_b_resp_valid (bridge_bvalid),
        .rx_stream_data   (sa_rx_tdata),
        .rx_stream_ready  (sa_rx_tready),
        .rx_stream_valid  (sa_rx_tvalid),
        .rx_stream_keep   (sa_rx_tkeep),
        .rx_stream_strb   (sa_rx_tstrb),
        .rx_stream_last   (sa_rx_tlast),
        .axi_r_data       (bridge_rdata),
        .axi_r_ready      (bridge_rready),
        .axi_r_valid      (bridge_rvalid),
        .axi_r_resp       (bridge_rresp),
        .axi_r_last       (sa_r_last)
    );

    wire unused_sa = &{1'b0, sa_ready, sa_finish, sa_r_last};

    //--------------------------------------------------------------------------
    // TX CDC FIFO: fabric clk -> l_clk (mpf300 axis_async_fifo, open-logic
    // olo_base_fifo_async inside — behavioral SV model in this directory)
    //--------------------------------------------------------------------------
    axis_async_fifo tx_cdc_fifo_inst (
        .s_axis_aclk    (clk_150),
        .s_axis_aresetn (cpu_aresetn),
        .s_axis_tvalid  (sa_tx_tvalid),
        .s_axis_tready  (sa_tx_tready),
        .s_axis_tdata   (sa_tx_tdata),
        .s_axis_tstrb   (sa_tx_tstrb),
        .s_axis_tkeep   (sa_tx_tkeep),
        .s_axis_tlast   (sa_tx_tlast),
        .m_axis_aclk    (l_clk),
        .m_axis_aresetn (lclk_aresetn),
        .m_axis_tvalid  (adp_tx_tvalid),
        .m_axis_tready  (adp_tx_tready),
        .m_axis_tdata   (adp_tx_tdata),
        .m_axis_tstrb   (adp_tx_tstrb),
        .m_axis_tkeep   (adp_tx_tkeep),
        .m_axis_tlast   (adp_tx_tlast)
    );

    //--------------------------------------------------------------------------
    // RX CDC FIFO: l_clk -> fabric clk
    //--------------------------------------------------------------------------
    axis_async_fifo rx_cdc_fifo_inst (
        .s_axis_aclk    (l_clk),
        .s_axis_aresetn (lclk_aresetn),
        .s_axis_tvalid  (adp_rx_tvalid),
        .s_axis_tready  (adp_rx_tready),
        .s_axis_tdata   (adp_rx_tdata),
        .s_axis_tstrb   (adp_rx_tstrb),
        .s_axis_tkeep   (adp_rx_tkeep),
        .s_axis_tlast   (adp_rx_tlast),
        .m_axis_aclk    (clk_150),
        .m_axis_aresetn (cpu_aresetn),
        .m_axis_tvalid  (sa_rx_tvalid),
        .m_axis_tready  (sa_rx_tready),
        .m_axis_tdata   (sa_rx_tdata),
        .m_axis_tstrb   (sa_rx_tstrb),
        .m_axis_tkeep   (sa_rx_tkeep),
        .m_axis_tlast   (sa_rx_tlast)
    );

    //--------------------------------------------------------------------------
    // axi_ad9361_adapter (SmartHLS, l_clk domain)
    //--------------------------------------------------------------------------
    wire adp_ready, adp_finish;

    wire        dac_i0_we,  dac_q0_we,  dac_i1_we,  dac_q1_we,  dac_dunf_we;
    wire [15:0] dac_i0_wd,  dac_q0_wd,  dac_i1_wd,  dac_q1_wd;
    wire        dac_dunf_wd;

    axi_ad9361_adapter_top ad9361_adapter_inst (
        .clk                    (l_clk),
        .reset                  (~lclk_aresetn),   // SmartHLS: sync, active high
        .start                  (1'b1),
        .ready                  (adp_ready),
        .finish                 (adp_finish),
        .adc_data_i0            (adc_data_i0),
        .adc_data_q0            (adc_data_q0),
        .adc_data_i1            (adc_data_i1),
        .adc_data_q1            (adc_data_q1),
        .adc_valid_i0           (adc_valid_i0),
        .adc_valid_q0           (adc_valid_q0),
        .adc_valid_i1           (adc_valid_i1),
        .adc_valid_q1           (adc_valid_q1),
        .adc_enable_i0          (adc_enable_i0),
        .adc_enable_q0          (adc_enable_q0),
        .adc_enable_i1          (adc_enable_i1),
        .adc_enable_q1          (adc_enable_q1),
        .dac_valid_i0           (dac_valid_i0),
        .dac_valid_q0           (dac_valid_q0),
        .dac_valid_i1           (dac_valid_i1),
        .dac_valid_q1           (dac_valid_q1),
        .dac_enable_i0          (dac_enable_i0),
        .dac_enable_q0          (dac_enable_q0),
        .dac_enable_i1          (dac_enable_i1),
        .dac_enable_q1          (dac_enable_q1),
        .adc_dovf               (1'b0),
        .tx_stream_data         (adp_tx_tdata),
        .tx_stream_ready        (adp_tx_tready),
        .tx_stream_valid        (adp_tx_tvalid),
        .tx_stream_keep         (adp_tx_tkeep),
        .tx_stream_strb         (adp_tx_tstrb),
        .tx_stream_last         (adp_tx_tlast),
        .dac_data_i0_write_en   (dac_i0_we),
        .dac_data_i0_write_data (dac_i0_wd),
        .dac_data_q0_write_en   (dac_q0_we),
        .dac_data_q0_write_data (dac_q0_wd),
        .dac_data_i1_write_en   (dac_i1_we),
        .dac_data_i1_write_data (dac_i1_wd),
        .dac_data_q1_write_en   (dac_q1_we),
        .dac_data_q1_write_data (dac_q1_wd),
        .dac_dunf_write_en      (dac_dunf_we),
        .dac_dunf_write_data    (dac_dunf_wd),
        .rx_stream_data         (adp_rx_tdata),
        .rx_stream_ready        (adp_rx_tready),
        .rx_stream_valid        (adp_rx_tvalid),
        .rx_stream_keep         (adp_rx_tkeep),
        .rx_stream_strb         (adp_rx_tstrb),
        .rx_stream_last         (adp_rx_tlast)
    );

    wire unused_adp = &{1'b0, adp_ready, adp_finish};

    //--------------------------------------------------------------------------
    // DAC holding registers (mpf300 dac_hold): write_en/write_data pulses ->
    // level-held dac_data buses for the TB
    //--------------------------------------------------------------------------
    wire dac_dunf_held;

    dac_hold dac_hold_inst (
        .clk                    (l_clk),
        .dac_data_i0_write_en   (dac_i0_we),
        .dac_data_i0_write_data (dac_i0_wd),
        .dac_data_q0_write_en   (dac_q0_we),
        .dac_data_q0_write_data (dac_q0_wd),
        .dac_data_i1_write_en   (dac_i1_we),
        .dac_data_i1_write_data (dac_i1_wd),
        .dac_data_q1_write_en   (dac_q1_we),
        .dac_data_q1_write_data (dac_q1_wd),
        .dac_dunf_write_en      (dac_dunf_we),
        .dac_dunf_write_data    (dac_dunf_wd),
        .dac_data_i0            (dac_data_i0),
        .dac_data_q0            (dac_data_q0),
        .dac_data_i1            (dac_data_i1),
        .dac_data_q1            (dac_data_q1),
        .dac_dunf               (dac_dunf_held)
    );

    wire unused_dunf = dac_dunf_held;

endmodule

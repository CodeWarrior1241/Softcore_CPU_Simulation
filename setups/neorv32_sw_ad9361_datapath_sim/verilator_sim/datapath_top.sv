//==============================================================================
// datapath_top.sv
//
// Datapath-only top-level for Verilator simulation.
//
// Instantiates the streaming chain WITHOUT axi_ad9361 (the LVDS transceiver
// uses UNISIM primitives — IDELAYE3, IDDRE1, IDELAYCTRL — that have
// always @(*) behavioral models incompatible with Verilator's event engine).
//
// Instead, the testbench drives the axi_ad9361_adapter's ADC ports directly
// and reads DAC output ports directly, bypassing the LVDS layer entirely.
// This is the same approach used in src/axiad9361_adapter/verilator_sim/.
//
//------------------------------------------------------------------------------
// Clocks
//------------------------------------------------------------------------------
//   ecs_clk_in (300 MHz diff) -> clk_wiz_behavioral -> clk_150 + clk_300
//   l_clk (125 MHz)           -> provided by testbench (replaces axi_ad9361)
//
//------------------------------------------------------------------------------
// Datapath (all behavioral RTL, zero sim_netlists, zero UNISIM)
//------------------------------------------------------------------------------
//   TB ADC ports -> axi_ad9361_adapter (125 MHz)
//                -> RX CDC FIFO (125->150 MHz)
//                -> axi_lite_to_streaming_adapter (150 MHz)
//                -> [TB reads via AXI-Lite]
//
//   [TB writes via AXI-Lite] -> axi_lite_to_streaming_adapter
//                             -> TX CDC FIFO (150->125 MHz)
//                             -> axi_ad9361_adapter
//                             -> TB DAC ports
//==============================================================================

`timescale 1ns / 1ps

module datapath_top (
    // 150 MHz clock domain (from behavioral clk_wiz)
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

    // DAC interface (TB reads, replacing axi_ad9361 DAC inputs)
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

    // AXI-Lite to streaming adapter s_axi_ctrl (14-bit addr)
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
    // 150 MHz reset synchronizer
    //--------------------------------------------------------------------------
    reg [3:0] rst150_sync = 4'b0;
    always @(posedge clk_150 or negedge system_resetn) begin
        if (!system_resetn)
            rst150_sync <= 4'b0;
        else if (!clk_150_locked)
            rst150_sync <= 4'b0;
        else
            rst150_sync <= {rst150_sync[2:0], 1'b1};
    end
    wire cpu_aresetn = rst150_sync[3];

    //--------------------------------------------------------------------------
    // 125 MHz reset synchronizer
    //--------------------------------------------------------------------------
    reg [3:0] rst125_sync = 4'b0;
    always @(posedge l_clk or negedge system_resetn) begin
        if (!system_resetn)
            rst125_sync <= 4'b0;
        else if (!clk_150_locked)
            rst125_sync <= 4'b0;
        else
            rst125_sync <= {rst125_sync[2:0], 1'b1};
    end
    wire lclk_aresetn = rst125_sync[3];

    //--------------------------------------------------------------------------
    // AXI-Stream wires
    //--------------------------------------------------------------------------
    // streaming_adapter tx_stream (150 MHz) -> TX CDC FIFO S_AXIS
    wire [31:0] sa_tx_tdata;
    wire  [3:0] sa_tx_tkeep, sa_tx_tstrb;
    wire        sa_tx_tlast, sa_tx_tvalid, sa_tx_tready;

    // TX CDC FIFO M_AXIS (125 MHz) -> ad9361_adapter tx_stream
    wire [31:0] adp_tx_tdata;
    wire  [3:0] adp_tx_tkeep, adp_tx_tstrb;
    wire        adp_tx_tlast, adp_tx_tvalid, adp_tx_tready;

    // ad9361_adapter rx_stream (125 MHz) -> RX CDC FIFO S_AXIS
    wire [31:0] adp_rx_tdata;
    wire  [3:0] adp_rx_tkeep, adp_rx_tstrb;
    wire        adp_rx_tlast, adp_rx_tvalid, adp_rx_tready;

    // RX CDC FIFO M_AXIS (150 MHz) -> streaming_adapter rx_stream
    wire [31:0] sa_rx_tdata;
    wire  [3:0] sa_rx_tkeep, sa_rx_tstrb;
    wire        sa_rx_tlast, sa_rx_tvalid, sa_rx_tready;

    //--------------------------------------------------------------------------
    // axi_lite_to_streaming_adapter (150 MHz)
    //--------------------------------------------------------------------------
    axi_lite_to_streaming_adapter streaming_adapter_inst (
        .ap_clk            (clk_150),
        .ap_rst_n          (cpu_aresetn),
        .s_axi_ctrl_AWADDR (bridge_awaddr),
        .s_axi_ctrl_AWVALID(bridge_awvalid),
        .s_axi_ctrl_AWREADY(bridge_awready),
        .s_axi_ctrl_WDATA  (bridge_wdata),
        .s_axi_ctrl_WSTRB  (bridge_wstrb),
        .s_axi_ctrl_WVALID (bridge_wvalid),
        .s_axi_ctrl_WREADY (bridge_wready),
        .s_axi_ctrl_BRESP  (bridge_bresp),
        .s_axi_ctrl_BVALID (bridge_bvalid),
        .s_axi_ctrl_BREADY (bridge_bready),
        .s_axi_ctrl_ARADDR (bridge_araddr),
        .s_axi_ctrl_ARVALID(bridge_arvalid),
        .s_axi_ctrl_ARREADY(bridge_arready),
        .s_axi_ctrl_RDATA  (bridge_rdata),
        .s_axi_ctrl_RRESP  (bridge_rresp),
        .s_axi_ctrl_RVALID (bridge_rvalid),
        .s_axi_ctrl_RREADY (bridge_rready),
        .tx_stream_TDATA   (sa_tx_tdata),
        .tx_stream_TKEEP   (sa_tx_tkeep),
        .tx_stream_TSTRB   (sa_tx_tstrb),
        .tx_stream_TLAST   (sa_tx_tlast),
        .tx_stream_TVALID  (sa_tx_tvalid),
        .tx_stream_TREADY  (sa_tx_tready),
        .rx_stream_TDATA   (sa_rx_tdata),
        .rx_stream_TKEEP   (sa_rx_tkeep),
        .rx_stream_TSTRB   (sa_rx_tstrb),
        .rx_stream_TLAST   (sa_rx_tlast),
        .rx_stream_TVALID  (sa_rx_tvalid),
        .rx_stream_TREADY  (sa_rx_tready)
    );

    //--------------------------------------------------------------------------
    // TX CDC FIFO: 150 MHz -> 125 MHz (Xilinx axis_data_fifo, behavioral)
    //--------------------------------------------------------------------------
    Top_ad9361_cdc_tx_streaming_fifo_0 tx_cdc_fifo_inst (
        .s_axis_aclk    (clk_150),
        .s_axis_aresetn (cpu_aresetn),
        .s_axis_tvalid  (sa_tx_tvalid),
        .s_axis_tready  (sa_tx_tready),
        .s_axis_tdata   (sa_tx_tdata),
        .s_axis_tstrb   (sa_tx_tstrb),
        .s_axis_tkeep   (sa_tx_tkeep),
        .s_axis_tlast   (sa_tx_tlast),
        .m_axis_aclk    (l_clk),
        .m_axis_tvalid  (adp_tx_tvalid),
        .m_axis_tready  (adp_tx_tready),
        .m_axis_tdata   (adp_tx_tdata),
        .m_axis_tstrb   (adp_tx_tstrb),
        .m_axis_tkeep   (adp_tx_tkeep),
        .m_axis_tlast   (adp_tx_tlast)
    );

    //--------------------------------------------------------------------------
    // RX CDC FIFO: 125 MHz -> 150 MHz (Xilinx axis_data_fifo, behavioral)
    //--------------------------------------------------------------------------
    Top_ad9361_cdc_rx_streaming_fifo_0 rx_cdc_fifo_inst (
        .s_axis_aclk    (l_clk),
        .s_axis_aresetn (lclk_aresetn),
        .s_axis_tvalid  (adp_rx_tvalid),
        .s_axis_tready  (adp_rx_tready),
        .s_axis_tdata   (adp_rx_tdata),
        .s_axis_tstrb   (adp_rx_tstrb),
        .s_axis_tkeep   (adp_rx_tkeep),
        .s_axis_tlast   (adp_rx_tlast),
        .m_axis_aclk    (clk_150),
        .m_axis_tvalid  (sa_rx_tvalid),
        .m_axis_tready  (sa_rx_tready),
        .m_axis_tdata   (sa_rx_tdata),
        .m_axis_tstrb   (sa_rx_tstrb),
        .m_axis_tkeep   (sa_rx_tkeep),
        .m_axis_tlast   (sa_rx_tlast)
    );

    //--------------------------------------------------------------------------
    // axi_ad9361_adapter (125 MHz l_clk datapath, HLS behavioral RTL)
    //--------------------------------------------------------------------------
    axi_ad9361_adapter ad9361_adapter_inst (
        .ap_clk           (l_clk),
        .ap_rst_n         (lclk_aresetn),
        .tx_stream_TDATA  (adp_tx_tdata),
        .tx_stream_TKEEP  (adp_tx_tkeep),
        .tx_stream_TSTRB  (adp_tx_tstrb),
        .tx_stream_TLAST  (adp_tx_tlast),
        .tx_stream_TVALID (adp_tx_tvalid),
        .tx_stream_TREADY (adp_tx_tready),
        .rx_stream_TDATA  (adp_rx_tdata),
        .rx_stream_TKEEP  (adp_rx_tkeep),
        .rx_stream_TSTRB  (adp_rx_tstrb),
        .rx_stream_TLAST  (adp_rx_tlast),
        .rx_stream_TVALID (adp_rx_tvalid),
        .rx_stream_TREADY (adp_rx_tready),
        .adc_data_i0      (adc_data_i0),
        .adc_data_q0      (adc_data_q0),
        .adc_data_i1      (adc_data_i1),
        .adc_data_q1      (adc_data_q1),
        .adc_valid_i0     (adc_valid_i0),
        .adc_valid_q0     (adc_valid_q0),
        .adc_valid_i1     (adc_valid_i1),
        .adc_valid_q1     (adc_valid_q1),
        .adc_enable_i0    (adc_enable_i0),
        .adc_enable_q0    (adc_enable_q0),
        .adc_enable_i1    (adc_enable_i1),
        .adc_enable_q1    (adc_enable_q1),
        .dac_data_i0      (dac_data_i0),
        .dac_data_q0      (dac_data_q0),
        .dac_data_i1      (dac_data_i1),
        .dac_data_q1      (dac_data_q1),
        .dac_valid_i0     (dac_valid_i0),
        .dac_valid_q0     (dac_valid_q0),
        .dac_valid_i1     (dac_valid_i1),
        .dac_valid_q1     (dac_valid_q1),
        .dac_enable_i0    (dac_enable_i0),
        .dac_enable_q0    (dac_enable_q0),
        .dac_enable_i1    (dac_enable_i1),
        .dac_enable_q1    (dac_enable_q1),
        .adc_dovf         (1'b0),
        .dac_dunf         ()
    );

endmodule

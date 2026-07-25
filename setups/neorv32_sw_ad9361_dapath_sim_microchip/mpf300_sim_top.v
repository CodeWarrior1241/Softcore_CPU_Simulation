//------------------------------------------------------------------------------
// mpf300_sim_top.v — full-system simulation top for the Microchip (mpf300)
// FMCOMMS2 design.
//
// Hand-written HDL transcription of the Libero SmartDesign "Top" built by
// deps/hdl/projects/fmcomms2/mpf300/build_all.tcl: every instance and net
// below mirrors an sd_instantiate / sd_wire / sd_tie call in that script, so
// this file simulates the same system the Libero flow synthesizes.
// Kept as a sim-local file because the SmartDesign netlist itself lives in
// the disposable proj/ directory.
//
// Instances (SmartDesign instance names kept):
//   refclk_ibuf_0        INBUF + CLKINT_PRESERVE       (real RTL, polarfire lib)
//   clk_gen              PF_CCC 50->125 MHz            (behavioral: pf_ccc_sim)
//   init_monitor         PF_INIT_MONITOR               (behavioral: pf_init_monitor_sim)
//   sys_ctrl_0           reset gen + GPIO fanout       (real RTL, open-logic inside)
//   lclk_reset_sync_0    l_clk reset + pwr_dn CDC      (real RTL, open-logic inside)
//   NEORV32_RISC_V       neorv32_mpf300_top            (real RTL; sim copy enables
//                                                       CPU_FAST_MUL_PIPELINE, PR #1603)
//   axi_cpu_interconnect axi_1to3_decoder              (real RTL, PULP axi_lite_xbar)
//   qpsk_snapshot_bram   axi_bram_32k                  (real RTL)
//   axi_ad9361_0         ADI axi_ad9361, PolarFire LVDS interface (real RTL)
//   axi_ad9361_adapter_0 SmartHLS adapter              (generated RTL)
//   axi_streaming_adapter_0 SmartHLS bridge            (generated RTL)
//   dac_hold_0           DAC holding registers         (real RTL)
//   ad9361_cdc_tx_fifo / ad9361_cdc_rx_fifo  axis_async_fifo (real RTL,
//                                                       open-logic FIFO inside)
//
// Extra sim-only ports (not on the SmartDesign): sim_gpio_o (full 16-bit
// NEORV32 GPIO for testbench milestone/result monitoring — hardware only
// pins slices of it), sim_clk_125mhz + sim_clk_125mhz_locked (mirrors the
// Xilinx sim's sim_clock_150MHz/locked observation ports).
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module mpf300_sim_top (
    // board
    input  wire        ref_clk_50mhz,
    input  wire        sys_resetn,       // PF_USER_RESET push-button, active low
    input  wire        sys_uart_rx,
    output wire        sys_uart_tx,
    output wire        spi_clk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_csn_0,
    output wire        gpio_resetb,
    output wire        gpio_sync,
    output wire        gpio_en_agc,
    output wire [3:0]  gpio_ctl,
    input  wire [7:0]  gpio_status,

    // AD9361 LVDS
    input  wire        rx_clk_in_p,
    input  wire        rx_clk_in_n,
    input  wire        rx_frame_in_p,
    input  wire        rx_frame_in_n,
    input  wire [5:0]  rx_data_in_p,
    input  wire [5:0]  rx_data_in_n,
    output wire        tx_clk_out_p,
    output wire        tx_clk_out_n,
    output wire        tx_frame_out_p,
    output wire        tx_frame_out_n,
    output wire [5:0]  tx_data_out_p,
    output wire [5:0]  tx_data_out_n,
    output wire        enable,
    output wire        txnrx,

    // sim-only observation
    output wire [15:0] sim_gpio_o,
    output wire        sim_clk_125mhz,
    output wire        sim_clk_125mhz_locked
);

    //--------------------------------------------------------------------------
    // clocking / init
    //--------------------------------------------------------------------------

    wire refclk_fab, clk_125, pll_lock, init_done;

    refclk_ibuf refclk_ibuf_0 (
        .pad (ref_clk_50mhz),
        .clk (refclk_fab)
    );

    pf_ccc_sim clk_gen (
        .REF_CLK_0         (refclk_fab),
        .PLL_POWERDOWN_N_0 (1'b1),
        .OUT0_FABCLK_0     (clk_125),
        .PLL_LOCK_0        (pll_lock)
    );

    pf_init_monitor_sim init_monitor (
        .DEVICE_INIT_DONE (init_done)
    );

    assign sim_clk_125mhz        = clk_125;
    assign sim_clk_125mhz_locked = pll_lock;

    //--------------------------------------------------------------------------
    // system control / resets
    //--------------------------------------------------------------------------

    wire [15:0] gpio_o;
    wire [7:0]  spi_csn;
    wire        sys_rstn_s, sys_rst_s, aresetn_gated, pwr_dn;
    wire        up_enable_s, up_txnrx_s;
    wire        l_clk, lclk_resetn, lclk_reset;

    sys_ctrl sys_ctrl_0 (
        .clk         (clk_125),
        .pll_lock    (pll_lock),
        .init_done   (init_done),
        .ext_resetn  (sys_resetn),
        .gpio_o      (gpio_o),
        .spi_csn_i   (spi_csn),
        .sys_resetn  (sys_rstn_s),
        .sys_reset   (sys_rst_s),
        .aresetn_gated (aresetn_gated),
        .pwr_dn      (pwr_dn),
        .up_enable   (up_enable_s),
        .up_txnrx    (up_txnrx_s),
        .gpio_resetb (gpio_resetb),
        .gpio_sync   (gpio_sync),
        .gpio_en_agc (gpio_en_agc),
        .gpio_ctl    (gpio_ctl),
        .spi_csn_0   (spi_csn_0)
    );

    lclk_reset_sync lclk_reset_sync_0 (
        .l_clk       (l_clk),
        .clk_125     (clk_125),
        .ext_resetn  (sys_rstn_s),
        .pwr_dn      (pwr_dn),
        .lclk_resetn (lclk_resetn),
        .lclk_reset  (lclk_reset)
    );

    assign sim_gpio_o = gpio_o;

    //--------------------------------------------------------------------------
    // NEORV32 (sim wrapper: CPU_FAST_MUL_PIPELINE enabled)
    //--------------------------------------------------------------------------

    wire [31:0] cpu_awaddr, cpu_wdata, cpu_araddr, cpu_rdata;
    wire [7:0]  cpu_awlen, cpu_arlen;
    wire [2:0]  cpu_awsize, cpu_arsize, cpu_awprot, cpu_arprot;
    wire [1:0]  cpu_awburst, cpu_arburst, cpu_bresp, cpu_rresp;
    wire [3:0]  cpu_wstrb;
    wire        cpu_awvalid, cpu_awready, cpu_wlast, cpu_wvalid, cpu_wready;
    wire        cpu_bvalid, cpu_bready, cpu_arvalid, cpu_arready;
    wire        cpu_rlast, cpu_rvalid, cpu_rready;

    neorv32_mpf300_top NEORV32_RISC_V (
        .clk           (clk_125),
        .resetn        (sys_rstn_s),
        .m_axi_awaddr  (cpu_awaddr),
        .m_axi_awlen   (cpu_awlen),
        .m_axi_awsize  (cpu_awsize),
        .m_axi_awburst (cpu_awburst),
        .m_axi_awprot  (cpu_awprot),
        .m_axi_awvalid (cpu_awvalid),
        .m_axi_awready (cpu_awready),
        .m_axi_wdata   (cpu_wdata),
        .m_axi_wstrb   (cpu_wstrb),
        .m_axi_wlast   (cpu_wlast),
        .m_axi_wvalid  (cpu_wvalid),
        .m_axi_wready  (cpu_wready),
        .m_axi_bresp   (cpu_bresp),
        .m_axi_bvalid  (cpu_bvalid),
        .m_axi_bready  (cpu_bready),
        .m_axi_araddr  (cpu_araddr),
        .m_axi_arlen   (cpu_arlen),
        .m_axi_arsize  (cpu_arsize),
        .m_axi_arburst (cpu_arburst),
        .m_axi_arprot  (cpu_arprot),
        .m_axi_arvalid (cpu_arvalid),
        .m_axi_arready (cpu_arready),
        .m_axi_rdata   (cpu_rdata),
        .m_axi_rresp   (cpu_rresp),
        .m_axi_rlast   (cpu_rlast),
        .m_axi_rvalid  (cpu_rvalid),
        .m_axi_rready  (cpu_rready),
        .gpio_o        (gpio_o),
        .gpio_i        (gpio_status),
        .uart0_txd_o   (sys_uart_tx),
        .uart0_rxd_i   (sys_uart_rx),
        .spi_clk_o     (spi_clk),
        .spi_dat_o     (spi_mosi),
        .spi_dat_i     (spi_miso),
        .spi_csn_o     (spi_csn)
    );

    //--------------------------------------------------------------------------
    // AXI fabric + BRAM
    //--------------------------------------------------------------------------

    wire [31:0] m0_awaddr, m0_wdata, m0_araddr, m0_rdata;
    wire [3:0]  m0_wstrb;
    wire [1:0]  m0_bresp, m0_rresp;
    wire        m0_awvalid, m0_awready, m0_wvalid, m0_wready;
    wire        m0_bvalid, m0_bready, m0_arvalid, m0_arready, m0_rvalid, m0_rready;

    wire [15:0] m1_awaddr, m1_araddr;
    wire [31:0] m1_wdata, m1_rdata;
    wire [2:0]  m1_awprot, m1_arprot;
    wire [3:0]  m1_wstrb;
    wire [1:0]  m1_bresp, m1_rresp;
    wire        m1_awvalid, m1_awready, m1_wvalid, m1_wready;
    wire        m1_bvalid, m1_bready, m1_arvalid, m1_arready, m1_rvalid, m1_rready;

    wire [31:0] m2_awaddr, m2_wdata, m2_araddr, m2_rdata;
    wire [7:0]  m2_awlen, m2_arlen;
    wire [2:0]  m2_awsize, m2_arsize;
    wire [1:0]  m2_awburst, m2_arburst, m2_bresp, m2_rresp;
    wire [3:0]  m2_wstrb;
    wire        m2_awvalid, m2_awready, m2_wlast, m2_wvalid, m2_wready;
    wire        m2_bvalid, m2_bready, m2_arvalid, m2_arready;
    wire        m2_rlast, m2_rvalid, m2_rready;

    axi_1to3_decoder axi_cpu_interconnect (
        .aclk      (clk_125),
        .aresetn   (sys_rstn_s),
        .s_awaddr  (cpu_awaddr),
        .s_awlen   (cpu_awlen),
        .s_awsize  (cpu_awsize),
        .s_awburst (cpu_awburst),
        .s_awprot  (cpu_awprot),
        .s_awvalid (cpu_awvalid),
        .s_awready (cpu_awready),
        .s_wdata   (cpu_wdata),
        .s_wstrb   (cpu_wstrb),
        .s_wlast   (cpu_wlast),
        .s_wvalid  (cpu_wvalid),
        .s_wready  (cpu_wready),
        .s_bresp   (cpu_bresp),
        .s_bvalid  (cpu_bvalid),
        .s_bready  (cpu_bready),
        .s_araddr  (cpu_araddr),
        .s_arlen   (cpu_arlen),
        .s_arsize  (cpu_arsize),
        .s_arburst (cpu_arburst),
        .s_arprot  (cpu_arprot),
        .s_arvalid (cpu_arvalid),
        .s_arready (cpu_arready),
        .s_rdata   (cpu_rdata),
        .s_rresp   (cpu_rresp),
        .s_rlast   (cpu_rlast),
        .s_rvalid  (cpu_rvalid),
        .s_rready  (cpu_rready),
        .m0_awaddr (m0_awaddr),
        .m0_awvalid(m0_awvalid),
        .m0_awready(m0_awready),
        .m0_wdata  (m0_wdata),
        .m0_wstrb  (m0_wstrb),
        .m0_wvalid (m0_wvalid),
        .m0_wready (m0_wready),
        .m0_bresp  (m0_bresp),
        .m0_bvalid (m0_bvalid),
        .m0_bready (m0_bready),
        .m0_araddr (m0_araddr),
        .m0_arvalid(m0_arvalid),
        .m0_arready(m0_arready),
        .m0_rdata  (m0_rdata),
        .m0_rresp  (m0_rresp),
        .m0_rvalid (m0_rvalid),
        .m0_rready (m0_rready),
        .m1_awaddr (m1_awaddr),
        .m1_awprot (m1_awprot),
        .m1_awvalid(m1_awvalid),
        .m1_awready(m1_awready),
        .m1_wdata  (m1_wdata),
        .m1_wstrb  (m1_wstrb),
        .m1_wvalid (m1_wvalid),
        .m1_wready (m1_wready),
        .m1_bresp  (m1_bresp),
        .m1_bvalid (m1_bvalid),
        .m1_bready (m1_bready),
        .m1_araddr (m1_araddr),
        .m1_arprot (m1_arprot),
        .m1_arvalid(m1_arvalid),
        .m1_arready(m1_arready),
        .m1_rdata  (m1_rdata),
        .m1_rresp  (m1_rresp),
        .m1_rvalid (m1_rvalid),
        .m1_rready (m1_rready),
        .m2_awaddr (m2_awaddr),
        .m2_awlen  (m2_awlen),
        .m2_awsize (m2_awsize),
        .m2_awburst(m2_awburst),
        .m2_awvalid(m2_awvalid),
        .m2_awready(m2_awready),
        .m2_wdata  (m2_wdata),
        .m2_wstrb  (m2_wstrb),
        .m2_wlast  (m2_wlast),
        .m2_wvalid (m2_wvalid),
        .m2_wready (m2_wready),
        .m2_bresp  (m2_bresp),
        .m2_bvalid (m2_bvalid),
        .m2_bready (m2_bready),
        .m2_araddr (m2_araddr),
        .m2_arlen  (m2_arlen),
        .m2_arsize (m2_arsize),
        .m2_arburst(m2_arburst),
        .m2_arvalid(m2_arvalid),
        .m2_arready(m2_arready),
        .m2_rdata  (m2_rdata),
        .m2_rresp  (m2_rresp),
        .m2_rlast  (m2_rlast),
        .m2_rvalid (m2_rvalid),
        .m2_rready (m2_rready)
    );

    axi_bram_32k qpsk_snapshot_bram (
        .aclk    (clk_125),
        .aresetn (sys_rstn_s),
        .awaddr  (m0_awaddr),
        .awvalid (m0_awvalid),
        .awready (m0_awready),
        .wdata   (m0_wdata),
        .wstrb   (m0_wstrb),
        .wvalid  (m0_wvalid),
        .wready  (m0_wready),
        .bresp   (m0_bresp),
        .bvalid  (m0_bvalid),
        .bready  (m0_bready),
        .araddr  (m0_araddr),
        .arvalid (m0_arvalid),
        .arready (m0_arready),
        .rdata   (m0_rdata),
        .rresp   (m0_rresp),
        .rvalid  (m0_rvalid),
        .rready  (m0_rready)
    );

    //--------------------------------------------------------------------------
    // AD9361 core (PolarFire LVDS interface), axau15 parameter set
    //--------------------------------------------------------------------------

    wire [15:0] adc_data_i0, adc_data_q0, adc_data_i1, adc_data_q1;
    wire        adc_valid_i0, adc_valid_q0, adc_valid_i1, adc_valid_q1;
    wire        adc_enable_i0, adc_enable_q0, adc_enable_i1, adc_enable_q1;
    wire [15:0] dac_data_i0, dac_data_q0, dac_data_i1, dac_data_q1;
    wire        dac_valid_i0, dac_valid_q0, dac_valid_i1, dac_valid_q1;
    wire        dac_enable_i0, dac_enable_q0, dac_enable_i1, dac_enable_q1;
    wire        dac_dunf_held, dac_sync_s;

    axi_ad9361 #(
        .ID                 (0),
        .CMOS_OR_LVDS_N     (0),
        .TDD_DISABLE        (1),
        .DAC_DDS_TYPE       (1),
        .DAC_DDS_CORDIC_DW  (14),
        .ADC_INIT_DELAY     (11)
    ) axi_ad9361_0 (
        .rx_clk_in_p   (rx_clk_in_p),
        .rx_clk_in_n   (rx_clk_in_n),
        .rx_frame_in_p (rx_frame_in_p),
        .rx_frame_in_n (rx_frame_in_n),
        .rx_data_in_p  (rx_data_in_p),
        .rx_data_in_n  (rx_data_in_n),
        .rx_clk_in     (1'b0),
        .rx_frame_in   (1'b0),
        .rx_data_in    (12'b0),
        .tx_clk_out_p  (tx_clk_out_p),
        .tx_clk_out_n  (tx_clk_out_n),
        .tx_frame_out_p(tx_frame_out_p),
        .tx_frame_out_n(tx_frame_out_n),
        .tx_data_out_p (tx_data_out_p),
        .tx_data_out_n (tx_data_out_n),
        .tx_clk_out    (),
        .tx_frame_out  (),
        .tx_data_out   (),
        .enable        (enable),
        .txnrx         (txnrx),
        .dac_sync_in   (dac_sync_s),
        .dac_sync_out  (dac_sync_s),
        .tdd_sync      (1'b0),
        .tdd_sync_cntr (),
        .gps_pps       (1'b0),
        .gps_pps_irq   (),
        .delay_clk     (clk_125),
        .l_clk         (l_clk),
        .clk           (l_clk),
        .rst           (),
        .adc_enable_i0 (adc_enable_i0),
        .adc_valid_i0  (adc_valid_i0),
        .adc_data_i0   (adc_data_i0),
        .adc_enable_q0 (adc_enable_q0),
        .adc_valid_q0  (adc_valid_q0),
        .adc_data_q0   (adc_data_q0),
        .adc_enable_i1 (adc_enable_i1),
        .adc_valid_i1  (adc_valid_i1),
        .adc_data_i1   (adc_data_i1),
        .adc_enable_q1 (adc_enable_q1),
        .adc_valid_q1  (adc_valid_q1),
        .adc_data_q1   (adc_data_q1),
        .adc_dovf      (1'b0),
        .adc_r1_mode   (),
        .dac_enable_i0 (dac_enable_i0),
        .dac_valid_i0  (dac_valid_i0),
        .dac_data_i0   (dac_data_i0),
        .dac_enable_q0 (dac_enable_q0),
        .dac_valid_q0  (dac_valid_q0),
        .dac_data_q0   (dac_data_q0),
        .dac_enable_i1 (dac_enable_i1),
        .dac_valid_i1  (dac_valid_i1),
        .dac_data_i1   (dac_data_i1),
        .dac_enable_q1 (dac_enable_q1),
        .dac_valid_q1  (dac_valid_q1),
        .dac_data_q1   (dac_data_q1),
        .dac_dunf      (dac_dunf_held),
        .dac_r1_mode   (),
        .s_axi_aclk    (clk_125),
        .s_axi_aresetn (aresetn_gated),
        .s_axi_awvalid (m1_awvalid),
        .s_axi_awaddr  (m1_awaddr),
        .s_axi_awprot  (m1_awprot),
        .s_axi_awready (m1_awready),
        .s_axi_wvalid  (m1_wvalid),
        .s_axi_wdata   (m1_wdata),
        .s_axi_wstrb   (m1_wstrb),
        .s_axi_wready  (m1_wready),
        .s_axi_bvalid  (m1_bvalid),
        .s_axi_bresp   (m1_bresp),
        .s_axi_bready  (m1_bready),
        .s_axi_arvalid (m1_arvalid),
        .s_axi_araddr  (m1_araddr),
        .s_axi_arprot  (m1_arprot),
        .s_axi_arready (m1_arready),
        .s_axi_rvalid  (m1_rvalid),
        .s_axi_rdata   (m1_rdata),
        .s_axi_rresp   (m1_rresp),
        .s_axi_rready  (m1_rready),
        .up_enable     (up_enable_s),
        .up_txnrx      (up_txnrx_s),
        .up_dac_gpio_in  (32'b0),
        .up_dac_gpio_out (),
        .up_adc_gpio_in  (32'b0),
        .up_adc_gpio_out ()
    );

    //--------------------------------------------------------------------------
    // SmartHLS adapters + DAC holding registers (l_clk domain)
    //--------------------------------------------------------------------------

    wire        dac_i0_we,  dac_q0_we,  dac_i1_we,  dac_q1_we,  dac_dunf_we;
    wire [15:0] dac_i0_wd,  dac_q0_wd,  dac_i1_wd,  dac_q1_wd;
    wire        dac_dunf_wd;

    // AXI-Stream nets
    wire [31:0] sa_tx_tdata,  adp_tx_tdata,  adp_rx_tdata,  sa_rx_tdata;
    wire [3:0]  sa_tx_tkeep,  adp_tx_tkeep,  adp_rx_tkeep,  sa_rx_tkeep;
    wire [3:0]  sa_tx_tstrb,  adp_tx_tstrb,  adp_rx_tstrb,  sa_rx_tstrb;
    wire        sa_tx_tlast,  adp_tx_tlast,  adp_rx_tlast,  sa_rx_tlast;
    wire        sa_tx_tvalid, adp_tx_tvalid, adp_rx_tvalid, sa_rx_tvalid;
    wire        sa_tx_tready, adp_tx_tready, adp_rx_tready, sa_rx_tready;

    axi_ad9361_adapter_top axi_ad9361_adapter_0 (
        .clk    (l_clk),
        .reset  (lclk_reset),
        .start  (1'b1),
        .ready  (),
        .finish (),
        .adc_data_i0   (adc_data_i0),
        .adc_data_q0   (adc_data_q0),
        .adc_data_i1   (adc_data_i1),
        .adc_data_q1   (adc_data_q1),
        .adc_valid_i0  (adc_valid_i0),
        .adc_valid_q0  (adc_valid_q0),
        .adc_valid_i1  (adc_valid_i1),
        .adc_valid_q1  (adc_valid_q1),
        .adc_enable_i0 (adc_enable_i0),
        .adc_enable_q0 (adc_enable_q0),
        .adc_enable_i1 (adc_enable_i1),
        .adc_enable_q1 (adc_enable_q1),
        .dac_valid_i0  (dac_valid_i0),
        .dac_valid_q0  (dac_valid_q0),
        .dac_valid_i1  (dac_valid_i1),
        .dac_valid_q1  (dac_valid_q1),
        .dac_enable_i0 (dac_enable_i0),
        .dac_enable_q0 (dac_enable_q0),
        .dac_enable_i1 (dac_enable_i1),
        .dac_enable_q1 (dac_enable_q1),
        .adc_dovf      (1'b0),
        .tx_stream_data  (adp_tx_tdata),
        .tx_stream_ready (adp_tx_tready),
        .tx_stream_valid (adp_tx_tvalid),
        .tx_stream_keep  (adp_tx_tkeep),
        .tx_stream_strb  (adp_tx_tstrb),
        .tx_stream_last  (adp_tx_tlast),
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
        .rx_stream_data  (adp_rx_tdata),
        .rx_stream_ready (adp_rx_tready),
        .rx_stream_valid (adp_rx_tvalid),
        .rx_stream_keep  (adp_rx_tkeep),
        .rx_stream_strb  (adp_rx_tstrb),
        .rx_stream_last  (adp_rx_tlast)
    );

    dac_hold dac_hold_0 (
        .clk (l_clk),
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
        .dac_data_i0 (dac_data_i0),
        .dac_data_q0 (dac_data_q0),
        .dac_data_i1 (dac_data_i1),
        .dac_data_q1 (dac_data_q1),
        .dac_dunf    (dac_dunf_held)
    );

    axi_lite_to_streaming_adapter_top axi_streaming_adapter_0 (
        .clk    (clk_125),
        .reset  (sys_rst_s),
        .start  (1'b1),
        .ready  (),
        .finish (),
        .axi_aw_addr      (m2_awaddr),
        .axi_aw_ready     (m2_awready),
        .axi_aw_valid     (m2_awvalid),
        .axi_aw_burst     (m2_awburst),
        .axi_aw_size      (m2_awsize),
        .axi_aw_len       (m2_awlen),
        .axi_ar_addr      (m2_araddr),
        .axi_ar_ready     (m2_arready),
        .axi_ar_valid     (m2_arvalid),
        .axi_ar_burst     (m2_arburst),
        .axi_ar_size      (m2_arsize),
        .axi_ar_len       (m2_arlen),
        .tx_stream_data   (sa_tx_tdata),
        .tx_stream_ready  (sa_tx_tready),
        .tx_stream_valid  (sa_tx_tvalid),
        .tx_stream_keep   (sa_tx_tkeep),
        .tx_stream_strb   (sa_tx_tstrb),
        .tx_stream_last   (sa_tx_tlast),
        .axi_w_data       (m2_wdata),
        .axi_w_ready      (m2_wready),
        .axi_w_valid      (m2_wvalid),
        .axi_w_strb       (m2_wstrb),
        .axi_w_last       (m2_wlast),
        .axi_b_resp       (m2_bresp),
        .axi_b_resp_ready (m2_bready),
        .axi_b_resp_valid (m2_bvalid),
        .rx_stream_data   (sa_rx_tdata),
        .rx_stream_ready  (sa_rx_tready),
        .rx_stream_valid  (sa_rx_tvalid),
        .rx_stream_keep   (sa_rx_tkeep),
        .rx_stream_strb   (sa_rx_tstrb),
        .rx_stream_last   (sa_rx_tlast),
        .axi_r_data       (m2_rdata),
        .axi_r_ready      (m2_rready),
        .axi_r_valid      (m2_rvalid),
        .axi_r_resp       (m2_rresp),
        .axi_r_last       (m2_rlast)
    );

    //--------------------------------------------------------------------------
    // CDC FIFOs (open-logic olo_base_fifo_async inside)
    //   TX: streaming adapter (125 MHz) -> HLS adapter (l_clk)
    //   RX: HLS adapter (l_clk) -> streaming adapter (125 MHz)
    //--------------------------------------------------------------------------

    axis_async_fifo ad9361_cdc_tx_fifo (
        .s_axis_aclk    (clk_125),
        .s_axis_aresetn (aresetn_gated),
        .s_axis_tdata   (sa_tx_tdata),
        .s_axis_tkeep   (sa_tx_tkeep),
        .s_axis_tstrb   (sa_tx_tstrb),
        .s_axis_tlast   (sa_tx_tlast),
        .s_axis_tvalid  (sa_tx_tvalid),
        .s_axis_tready  (sa_tx_tready),
        .m_axis_aclk    (l_clk),
        .m_axis_aresetn (lclk_resetn),
        .m_axis_tdata   (adp_tx_tdata),
        .m_axis_tkeep   (adp_tx_tkeep),
        .m_axis_tstrb   (adp_tx_tstrb),
        .m_axis_tlast   (adp_tx_tlast),
        .m_axis_tvalid  (adp_tx_tvalid),
        .m_axis_tready  (adp_tx_tready)
    );

    axis_async_fifo ad9361_cdc_rx_fifo (
        .s_axis_aclk    (l_clk),
        .s_axis_aresetn (lclk_resetn),
        .s_axis_tdata   (adp_rx_tdata),
        .s_axis_tkeep   (adp_rx_tkeep),
        .s_axis_tstrb   (adp_rx_tstrb),
        .s_axis_tlast   (adp_rx_tlast),
        .s_axis_tvalid  (adp_rx_tvalid),
        .s_axis_tready  (adp_rx_tready),
        .m_axis_aclk    (clk_125),
        .m_axis_aresetn (sys_rstn_s),
        .m_axis_tdata   (sa_rx_tdata),
        .m_axis_tkeep   (sa_rx_tkeep),
        .m_axis_tstrb   (sa_rx_tstrb),
        .m_axis_tlast   (sa_rx_tlast),
        .m_axis_tvalid  (sa_rx_tvalid),
        .m_axis_tready  (sa_rx_tready)
    );

endmodule

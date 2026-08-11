//------------------------------------------------------------------------------
// system_top_shim.v — core-side shim between the Efinix-generated periphery
// simulation netlist and the real project top.
//
// The Interface Designer export (gen_interface.py ->
// outflow/ti375c529_pt_interface.v) produces a pad-level chip wrapper
// (\system_top_shim~chip) that instantiates Efinix's OFFICIAL periphery
// models (EFX_FPLL_V1 / EFX_LVDS_RX_V2 / EFX_LVDS_TX_V2 / EFX_GPIO_V3)
// around a core module of exactly this name. Its core boundary is
// system_top's port list PLUS a few pins the synthesis top does not use:
//
//   l_clk_90, osc1_25mhz   periphery clocks also offered to the core
//                          (no core loads in this design) — ignored
//   <lane>_RX_ENA          LVDS input-buffer enables (optional at P&R,
//                          weak-pull-high in the models) — tied 1 so the
//                          receivers are always on, matching hardware
//
// Everything else passes straight through to the real system_top.
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module system_top_shim (
    input           clk_125mhz,
    input           sys_pll_CLKOUT1,  // 25 MHz sys_pll feedback clock -- exists
                                      // only for the x5 feedback loop, unused
    input           sys_pll_locked,
    input           osc1_25mhz,       // unused in the core
    input           rx_clk,
    input           l_clk,
    input           l_clk_90,         // unused in the core (FB_CLK lane clock)
    input           lvds_pll_locked,

    input           sys_resetn_pin,
    input           sys_uart_rx,
    output          sys_uart_tx,

    output          spi_clk,
    output          spi_mosi,
    input           spi_miso,
    output          spi_csn_0,
    output          gpio_resetb,
    output          gpio_sync,
    output          gpio_en_agc,
    output  [ 3:0]  gpio_ctl,
    input   [ 7:0]  gpio_status,
    output          enable,
    output          txnrx,

    input   [ 1:0]  rx_frame,
    input   [ 1:0]  rx_data_0,
    input   [ 1:0]  rx_data_1,
    input   [ 1:0]  rx_data_2,
    input   [ 1:0]  rx_data_3,
    input   [ 1:0]  rx_data_4,
    input   [ 1:0]  rx_data_5,
    output  [ 1:0]  tx_frame,
    output  [ 1:0]  tx_data_0,
    output  [ 1:0]  tx_data_1,
    output  [ 1:0]  tx_data_2,
    output  [ 1:0]  tx_data_3,
    output  [ 1:0]  tx_data_4,
    output  [ 1:0]  tx_data_5,

    output          rx_clk_in_RX_ENA,
    output          rx_frame_lane_RX_ENA,
    output          rx_data_0_lane_RX_ENA,
    output          rx_data_1_lane_RX_ENA,
    output          rx_data_2_lane_RX_ENA,
    output          rx_data_3_lane_RX_ENA,
    output          rx_data_4_lane_RX_ENA,
    output          rx_data_5_lane_RX_ENA,

    output          rx_frame_lane_RX_RST,
    output          rx_data_0_lane_RX_RST,
    output          rx_data_1_lane_RX_RST,
    output          rx_data_2_lane_RX_RST,
    output          rx_data_3_lane_RX_RST,
    output          rx_data_4_lane_RX_RST,
    output          rx_data_5_lane_RX_RST,
    output          tx_frame_lane_TX_RST,
    output          tx_data_0_lane_TX_RST,
    output          tx_data_1_lane_TX_RST,
    output          tx_data_2_lane_TX_RST,
    output          tx_data_3_lane_TX_RST,
    output          tx_data_4_lane_TX_RST,
    output          tx_data_5_lane_TX_RST,
    output          tx_clk_out_lane_TX_RST,
    output          tx_frame_lane_TX_OE,
    output          tx_data_0_lane_TX_OE,
    output          tx_data_1_lane_TX_OE,
    output          tx_data_2_lane_TX_OE,
    output          tx_data_3_lane_TX_OE,
    output          tx_data_4_lane_TX_OE,
    output          tx_data_5_lane_TX_OE,
    output          tx_clk_out_lane_TX_OE
);

    // LVDS input buffers always enabled (as on hardware)
    assign rx_clk_in_RX_ENA      = 1'b1;
    assign rx_frame_lane_RX_ENA  = 1'b1;
    assign rx_data_0_lane_RX_ENA = 1'b1;
    assign rx_data_1_lane_RX_ENA = 1'b1;
    assign rx_data_2_lane_RX_ENA = 1'b1;
    assign rx_data_3_lane_RX_ENA = 1'b1;
    assign rx_data_4_lane_RX_ENA = 1'b1;
    assign rx_data_5_lane_RX_ENA = 1'b1;

    system_top u_system_top (
        .clk_125mhz      (clk_125mhz),
        .sys_pll_locked  (sys_pll_locked),
        .rx_clk          (rx_clk),
        .l_clk           (l_clk),
        .lvds_pll_locked (lvds_pll_locked),
        .sys_resetn_pin  (sys_resetn_pin),
        .sys_uart_rx     (sys_uart_rx),
        .sys_uart_tx     (sys_uart_tx),
        .spi_clk         (spi_clk),
        .spi_mosi        (spi_mosi),
        .spi_miso        (spi_miso),
        .spi_csn_0       (spi_csn_0),
        .gpio_resetb     (gpio_resetb),
        .gpio_sync       (gpio_sync),
        .gpio_en_agc     (gpio_en_agc),
        .gpio_ctl        (gpio_ctl),
        .gpio_status     (gpio_status),
        .enable          (enable),
        .txnrx           (txnrx),
        .rx_frame        (rx_frame),
        .rx_data_0       (rx_data_0),
        .rx_data_1       (rx_data_1),
        .rx_data_2       (rx_data_2),
        .rx_data_3       (rx_data_3),
        .rx_data_4       (rx_data_4),
        .rx_data_5       (rx_data_5),
        .tx_frame        (tx_frame),
        .tx_data_0       (tx_data_0),
        .tx_data_1       (tx_data_1),
        .tx_data_2       (tx_data_2),
        .tx_data_3       (tx_data_3),
        .tx_data_4       (tx_data_4),
        .tx_data_5       (tx_data_5),
        .rx_frame_lane_RX_RST   (rx_frame_lane_RX_RST),
        .rx_data_0_lane_RX_RST  (rx_data_0_lane_RX_RST),
        .rx_data_1_lane_RX_RST  (rx_data_1_lane_RX_RST),
        .rx_data_2_lane_RX_RST  (rx_data_2_lane_RX_RST),
        .rx_data_3_lane_RX_RST  (rx_data_3_lane_RX_RST),
        .rx_data_4_lane_RX_RST  (rx_data_4_lane_RX_RST),
        .rx_data_5_lane_RX_RST  (rx_data_5_lane_RX_RST),
        .tx_frame_lane_TX_RST   (tx_frame_lane_TX_RST),
        .tx_data_0_lane_TX_RST  (tx_data_0_lane_TX_RST),
        .tx_data_1_lane_TX_RST  (tx_data_1_lane_TX_RST),
        .tx_data_2_lane_TX_RST  (tx_data_2_lane_TX_RST),
        .tx_data_3_lane_TX_RST  (tx_data_3_lane_TX_RST),
        .tx_data_4_lane_TX_RST  (tx_data_4_lane_TX_RST),
        .tx_data_5_lane_TX_RST  (tx_data_5_lane_TX_RST),
        .tx_clk_out_lane_TX_RST (tx_clk_out_lane_TX_RST),
        .tx_frame_lane_TX_OE    (tx_frame_lane_TX_OE),
        .tx_data_0_lane_TX_OE   (tx_data_0_lane_TX_OE),
        .tx_data_1_lane_TX_OE   (tx_data_1_lane_TX_OE),
        .tx_data_2_lane_TX_OE   (tx_data_2_lane_TX_OE),
        .tx_data_3_lane_TX_OE   (tx_data_3_lane_TX_OE),
        .tx_data_4_lane_TX_OE   (tx_data_4_lane_TX_OE),
        .tx_data_5_lane_TX_OE   (tx_data_5_lane_TX_OE),
        .tx_clk_out_lane_TX_OE  (tx_clk_out_lane_TX_OE));

endmodule

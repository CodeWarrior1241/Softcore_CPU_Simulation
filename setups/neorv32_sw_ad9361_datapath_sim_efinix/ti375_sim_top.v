//------------------------------------------------------------------------------
// ti375_sim_top.v — Efinix Titanium (ti375) full-system simulation top.
//
// Counterpart of the mpf300 sim's mpf300_sim_top.v. The DUT is built from
// OFFICIAL Efinix pieces wherever they exist:
//
//   \system_top_shim~chip     the pad-level periphery simulation netlist
//                             exported by the project's gen_interface.py
//                             (outflow/ti375c529_pt_interface.v). It
//                             instantiates Efinix's shipped periphery
//                             models — EFX_FPLL_V1 (both PLLs),
//                             EFX_LVDS_RX_V2 / EFX_LVDS_TX_V2 (all 16
//                             lanes + FB_CLK lane), EFX_GPIO_V3 — from
//                             $EFINITY_HOME/pt/sim_models/verilog, exactly
//                             as configured in ti375c529.peri.xml.
//   system_top_shim           sim-local core shim: the REAL synthesis top
//                             (deps/hdl/projects/fmcomms2/ti375/hdl/
//                             system_top.v, unmodified) plus ties for the
//                             optional RX_ENA pins (see system_top_shim.v).
//
// This wrapper only adapts pad names to the TB's historic differential-pin
// interface (shared with the Xilinx/Microchip TBs) and taps the sim-only
// observation signals hierarchically.
//
// Behavior note vs. the retired hand-written models: EFX_FPLL_V1 measures
// its reference period once and then free-runs, so l_clk keeps toggling
// through the TB's power-gate window (the real PLL would lose its
// reference); the firmware's power-gate test still passes — it gates on
// datapath/relock status, not on l_clk stopping — and the TB's
// "l_clk stopped" warning simply does not appear.
//------------------------------------------------------------------------------

`timescale 1ns / 1ps

module ti375_sim_top (
    // board
    input  wire        ref_clk_25mhz,
    input  wire        sys_resetn,       // SW3 push-button, active low
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

    // AD9361 LVDS (pad view, true/complement)
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

    \system_top_shim~chip u_chip (
        .osc1_25mhz          (ref_clk_25mhz),
        .sys_resetn_pin      (sys_resetn),
        .sys_uart_rx         (sys_uart_rx),
        .sys_uart_tx         (sys_uart_tx),
        .spi_clk             (spi_clk),
        .spi_mosi            (spi_mosi),
        .spi_miso            (spi_miso),
        .spi_csn_0           (spi_csn_0),
        .gpio_resetb         (gpio_resetb),
        .gpio_sync           (gpio_sync),
        .gpio_en_agc         (gpio_en_agc),
        .gpio_ctl            (gpio_ctl),
        .gpio_status         (gpio_status),
        .enable              (enable),
        .txnrx               (txnrx),
        .rx_clk_in_RXP       (rx_clk_in_p),
        .rx_clk_in_RXN       (rx_clk_in_n),
        .rx_frame_lane_RXP   (rx_frame_in_p),
        .rx_frame_lane_RXN   (rx_frame_in_n),
        .rx_data_0_lane_RXP  (rx_data_in_p[0]),
        .rx_data_0_lane_RXN  (rx_data_in_n[0]),
        .rx_data_1_lane_RXP  (rx_data_in_p[1]),
        .rx_data_1_lane_RXN  (rx_data_in_n[1]),
        .rx_data_2_lane_RXP  (rx_data_in_p[2]),
        .rx_data_2_lane_RXN  (rx_data_in_n[2]),
        .rx_data_3_lane_RXP  (rx_data_in_p[3]),
        .rx_data_3_lane_RXN  (rx_data_in_n[3]),
        .rx_data_4_lane_RXP  (rx_data_in_p[4]),
        .rx_data_4_lane_RXN  (rx_data_in_n[4]),
        .rx_data_5_lane_RXP  (rx_data_in_p[5]),
        .rx_data_5_lane_RXN  (rx_data_in_n[5]),
        .tx_clk_out_lane_TXP (tx_clk_out_p),
        .tx_clk_out_lane_TXN (tx_clk_out_n),
        .tx_frame_lane_TXP   (tx_frame_out_p),
        .tx_frame_lane_TXN   (tx_frame_out_n),
        .tx_data_0_lane_TXP  (tx_data_out_p[0]),
        .tx_data_0_lane_TXN  (tx_data_out_n[0]),
        .tx_data_1_lane_TXP  (tx_data_out_p[1]),
        .tx_data_1_lane_TXN  (tx_data_out_n[1]),
        .tx_data_2_lane_TXP  (tx_data_out_p[2]),
        .tx_data_2_lane_TXN  (tx_data_out_n[2]),
        .tx_data_3_lane_TXP  (tx_data_out_p[3]),
        .tx_data_3_lane_TXN  (tx_data_out_n[3]),
        .tx_data_4_lane_TXP  (tx_data_out_p[4]),
        .tx_data_4_lane_TXN  (tx_data_out_n[4]),
        .tx_data_5_lane_TXP  (tx_data_out_p[5]),
        .tx_data_5_lane_TXN  (tx_data_out_n[5]));

    //--------------------------------------------------------------------------
    // Sim-only observation (hierarchical taps; the chip wrapper's internal
    // core instance carries the netlist-fixed escaped name ~inst)
    //--------------------------------------------------------------------------

    // l_clk as generated by the official EFX_FPLL_V1 lvds_pll (wrapper-level
    // net); referenced by the TB's l_clk monitors as dut.l_clk
    wire l_clk = u_chip.l_clk;

    assign sim_gpio_o = u_chip.\system_top_shim~inst .u_system_top.gpio_o_s;
    assign sim_clk_125mhz = u_chip.clk_125mhz;
    assign sim_clk_125mhz_locked = u_chip.\system_top_shim~inst .sys_pll_locked;

endmodule

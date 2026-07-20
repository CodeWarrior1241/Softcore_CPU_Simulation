//==============================================================================
// olo_base_fifo_async.sv — behavioral SystemVerilog model of the open-logic
// olo_base_fifo_async VHDL entity (deps/open-logic/src/base/vhdl), used only
// by this simulation (no VHDL support in the simulator — same reason
// datapath_top models the olo reset blocks behaviorally).
//
// Matches the entity's generics/ports as instantiated by the mpf300
// axis_async_fifo wrapper (deps/hdl/projects/fmcomms2/mpf300/hdl):
//   * gray-code pointer dual-clock FIFO, Depth_g a power of two
//   * valid/ready handshake on both sides, first-word-fall-through read
//   * reset distributed across BOTH domains (models olo_base_cc_reset:
//     asserting either side's reset flushes the whole FIFO)
// Status/level ports and the RamStyle_g/RamBehavior_g generics exist only
// for interface compatibility — storage here is a plain simulation array
// (in synthesis RamStyle_g "block" pins it to a PolarFire LSRAM).
// Read latency is idealized (data visible as soon as the synchronized
// pointers allow); the VHDL core adds RAM pipeline cycles, which the
// handshake absorbs.
//==============================================================================

`timescale 1ns / 1ps

module olo_base_fifo_async #(
    parameter int unsigned Width_g       = 16,
    parameter int unsigned Depth_g       = 32,      // power of two
    parameter              RamStyle_g    = "auto",  // interface compat only
    parameter              RamBehavior_g = "RBW",   // interface compat only
    parameter int unsigned SyncStages_g  = 2
) (
    // input (write) side
    input  logic               In_Clk,
    input  logic               In_Rst,     // active high, like the VHDL core
    input  logic [Width_g-1:0] In_Data,
    input  logic               In_Valid,
    output logic               In_Ready,

    // output (read) side
    input  logic               Out_Clk,
    input  logic               Out_Rst,    // active high
    output logic [Width_g-1:0] Out_Data,
    output logic               Out_Valid,
    input  logic               Out_Ready
);

    localparam int unsigned AW = $clog2(Depth_g);

    function automatic logic [AW:0] bin2gray(input logic [AW:0] b);
        return b ^ (b >> 1);
    endfunction

    //--------------------------------------------------------------------------
    // Cross-domain reset distribution (olo_base_cc_reset behavior: either
    // side's reset resets both pointer domains; assert promptly, release
    // synchronized to each domain's clock)
    //--------------------------------------------------------------------------
    logic rst_any;
    assign rst_any = In_Rst | Out_Rst;

    logic [SyncStages_g-1:0] rst_sync_wr = '1;
    logic [SyncStages_g-1:0] rst_sync_rd = '1;

    always_ff @(posedge In_Clk)  rst_sync_wr <= {rst_sync_wr[SyncStages_g-2:0], rst_any};
    always_ff @(posedge Out_Clk) rst_sync_rd <= {rst_sync_rd[SyncStages_g-2:0], rst_any};

    logic wr_rst, rd_rst;
    assign wr_rst = rst_any | rst_sync_wr[SyncStages_g-1];
    assign rd_rst = rst_any | rst_sync_rd[SyncStages_g-1];

    //--------------------------------------------------------------------------
    // Storage and pointers
    //--------------------------------------------------------------------------
    logic [Width_g-1:0] mem [Depth_g];

    logic [AW:0] wptr_bin  = '0, wptr_gray = '0;   // write domain
    logic [AW:0] rptr_bin  = '0, rptr_gray = '0;   // read domain

    // pointer synchronizers (SyncStages_g flops each way)
    logic [AW:0] rptr_gray_wsync [SyncStages_g];   // read ptr into write domain
    logic [AW:0] wptr_gray_rsync [SyncStages_g];   // write ptr into read domain

    always_ff @(posedge In_Clk) begin
        rptr_gray_wsync[0] <= rptr_gray;
        for (int i = 1; i < SyncStages_g; i++)
            rptr_gray_wsync[i] <= rptr_gray_wsync[i-1];
    end

    always_ff @(posedge Out_Clk) begin
        wptr_gray_rsync[0] <= wptr_gray;
        for (int i = 1; i < SyncStages_g; i++)
            wptr_gray_rsync[i] <= wptr_gray_rsync[i-1];
    end

    //--------------------------------------------------------------------------
    // Write side
    //--------------------------------------------------------------------------
    logic [AW:0] rptr_gray_w;
    assign rptr_gray_w = rptr_gray_wsync[SyncStages_g-1];

    logic full;
    assign full = (wptr_gray == {~rptr_gray_w[AW:AW-1], rptr_gray_w[AW-2:0]});

    assign In_Ready = !wr_rst && !full;

    always_ff @(posedge In_Clk) begin
        if (wr_rst) begin
            wptr_bin  <= '0;
            wptr_gray <= '0;
        end else if (In_Valid && In_Ready) begin
            mem[wptr_bin[AW-1:0]] <= In_Data;
            wptr_bin  <= wptr_bin + 1'b1;
            wptr_gray <= bin2gray(wptr_bin + 1'b1);
        end
    end

    //--------------------------------------------------------------------------
    // Read side (first word fall through)
    //--------------------------------------------------------------------------
    logic [AW:0] wptr_gray_r;
    assign wptr_gray_r = wptr_gray_rsync[SyncStages_g-1];

    logic empty;
    assign empty = (rptr_gray == wptr_gray_r);

    assign Out_Valid = !rd_rst && !empty;
    assign Out_Data  = mem[rptr_bin[AW-1:0]];

    always_ff @(posedge Out_Clk) begin
        if (rd_rst) begin
            rptr_bin  <= '0;
            rptr_gray <= '0;
        end else if (Out_Valid && Out_Ready) begin
            rptr_bin  <= rptr_bin + 1'b1;
            rptr_gray <= bin2gray(rptr_bin + 1'b1);
        end
    end

endmodule

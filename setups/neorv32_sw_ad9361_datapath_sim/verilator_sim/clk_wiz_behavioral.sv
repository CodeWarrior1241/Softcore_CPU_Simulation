//==============================================================================
// clk_wiz_behavioral.sv
//
// Behavioral replacement for Top_ECS_Clock_300MHz_0 (Xilinx clk_wiz / PLLE4_ADV).
// The real PLL behavioral model (PLLE4_ADV) has complex #delay-based lock
// timing that does not simulate reliably in Verilator with --bbox-unsup.
//
// This module provides the same port interface and functional behavior:
//   - clk_in1_p/n (300 MHz differential) -> clk_out1 (150 MHz) + clk_out2 (300 MHz)
//   - resetn: active-low reset
//   - locked: asserts after a short delay once reset is released
//==============================================================================

`timescale 1ns / 1ps

module Top_ECS_Clock_300MHz_0 (
    output wire clk_out1,       // 150 MHz
    output wire clk_out2,       // 300 MHz
    input  wire resetn,
    output wire locked,
    input  wire clk_in1_p,
    input  wire clk_in1_n
);

    // Derive single-ended clock from differential input
    wire clk_in = clk_in1_p;

    // clk_out2 = 300 MHz (same as input)
    assign clk_out2 = clk_in;

    // clk_out1 = 150 MHz (divide-by-2)
    reg clk_div2 = 0;
    always @(posedge clk_in) begin
        if (!resetn)
            clk_div2 <= 0;
        else
            clk_div2 <= ~clk_div2;
    end
    assign clk_out1 = clk_div2;

    // Lock: assert after 16 input clock cycles of reset being released.
    // Real PLL takes much longer; in behavioral sim this is sufficient.
    reg [4:0] lock_cnt = 0;
    reg       locked_r = 0;
    always @(posedge clk_in) begin
        if (!resetn) begin
            lock_cnt <= 0;
            locked_r <= 0;
        end else if (!locked_r) begin
            if (lock_cnt == 5'd16)
                locked_r <= 1;
            else
                lock_cnt <= lock_cnt + 1;
        end
    end
    assign locked = locked_r;

endmodule

// hb_panel -- the whole display: seventeen cards on one pin-header stack.
// hookbusy.md.
//
// Sixteen lamp cards at 0.4 inch, plus the interface card (common_card) at the
// left end, on four stacking headers that pass straight through -- HA, LEB,
// PWR, and control (hookbusy.md 3, 4.2).  In the normal configuration the
// columns alternate hook and busy -- green, orange, green, orange -- and a
// block is an adjacent colour PAIR:
//
//    common   1   2   3   4   5   6          15  16
//    legend  0H  0B  1H  1B  2H  2B   ...    7H  7B
//     s=0     .   .   .   .   .   .           .   .
//     ...
//     s=7     .   .   .   .   .   .           .   .
//
// A port is a horizontal pair 8 mm apart: BOTH lit is a call, green alone is
// off hook and unserved, orange alone is ringing or a port held by nothing,
// dark is idle.  observers.md 4.1's four states, read without a hue
// judgement -- POSITION carries hook-versus-busy and the colour only confirms
// it, which is what the bicolour grid of observers.md 7 could not do.
//
// THE JUMPERS ARE PARAMETERS because a jumper is set once, with the subrack,
// and never again.  BLK[c] is card c's shunt column and HOOK[c] its mode
// block; the defaults are the normal configuration and nothing else in the
// design depends on them.  Sixteen hook cards is a legal setting and it is
// what a fabric-only bring-up wants (fabric.md 7 step 2), because not one
// lamp card needs the marker to exist.
`timescale 1ns/1ps

module hb_panel #(
    // Card c watches block BLK[c*3 +: 3].  Default: c >> 1, so blocks pair up.
    parameter [47:0] BLK  = 48'o7766554433221100,
    // 1 = a hook card (green), 0 = a busy card (orange).  Default: alternate.
    parameter [15:0] HOOK = 16'h5555,
    parameter integer INH_TICKS = 12,
    parameter         INH_EN    = 1'b1
)(
    input             clk,
    input             rst_n,          // power-on, for the '164 model only
    input             reset_n,        // /RESET, cable B pin 7: every '259's /CLR

    // cable A
    input      [2:0]  slotq,
    input             hclk,
    input      [7:0]  ha,
    // cable B
    input             sdata,
    input             sclk,
    input             pb0,

    output     [127:0] lamp,          // lamp[c*8 + s]
    output     [2:0]   dst_blk        // what the stack's own '164 currently names
);
    wire [7:0] leb_n;
    wire [2:0] slotq_s;
    wire       hclk_s, pb0_s, reset_n_s;

    common_card #(.INH_TICKS(INH_TICKS), .INH_EN(INH_EN)) u_common (
        .clk(clk), .rst_n(rst_n),
        .sdata(sdata), .sclk(sclk),
        .slotq(slotq), .hclk(hclk), .pb0(pb0), .reset_n(reset_n),
        .leb_n(leb_n),
        .slotq_s(slotq_s), .hclk_s(hclk_s), .pb0_s(pb0_s), .reset_n_s(reset_n_s),
        .dst_blk(dst_blk));

    genvar c;
    generate for (c = 0; c < 16; c = c + 1) begin : card
        lamp_card #(.BLK(BLK[c*3 +: 3]), .HOOK(HOOK[c])) u_card (
            .clk(clk),
            .slotq(slotq_s), .hclk(hclk_s), .pb0(pb0_s), .reset_n(reset_n_s),
            .ha(ha), .leb_n(leb_n),
            .lamp(lamp[c*8 +: 8]));
    end endgenerate
endmodule

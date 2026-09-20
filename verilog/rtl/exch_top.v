// exch_top -- ONE exchange: the clock card, the mainboard and eight blocks.
// exchange/exch-protocol.md 3, exch-fabric.md, exch-mainboard.md.
//
// This is the exchange logic and nothing else -- mvp-ex.md 1's "= 70 packages".
// Cards are not in here: the module's edge is the channel-slot pins of
// mf8-backplane.md 8, so whatever plugs into a port plugs in from outside, and
// a port has no idea what it is.  The highway conductors and the cell clocks
// come out too, because that is where an MF8 trunk card taps its own block.
//
// Everything is parameterised and nothing is global, so more than one exchange
// may be instantiated, each on its own crystal.
`timescale 1ns/1ps
`include "exch_defs.vh"

module exch_top #(
    parameter [7:0]   BLOCK_FITTED = 8'b0000_0100,                  // MVP: block 2
    parameter [63:0]  PORT_FITTED  = 64'h0000_0000_0003_0000,       // MVP: ports 20, 21
    parameter [63:0]  PORT_RINGS   = {64{1'b1}},                    // /ANS open: phones
    parameter [23:0]  SHUNT        = 24'o76543210,                  // the shunt field
    parameter [7:0]   SHUNT_FITTED = BLOCK_FITTED,
    parameter         RBT_IS_FILL  = 1'b1,                          // no ringback card
    // A tone card drives RBT and /RING_CAD off its rear connector
    // (common/tone-plan.md 4.3-4.4, exchange/exch-mainboard.md 2.1).  With these
    // clear the clock card keeps both, which is the exchange as it was.
    parameter         TONE_CARD    = 1'b0,
    parameter integer T_RISE       = 1024,                          // 16 ms in frames
    parameter integer T_FALL       = 16384,                         // 256 ms in frames
    parameter integer RING_ON      = 128000,                        // 2 s
    parameter integer RING_OFF     = 256000                         // 4 s
)(
    input                clk,            // this exchange's own 4.096 MHz crystal
    input                rst_n,

    // ---- the 64 channel slots: what a card plugs into --------------------
    input      [63:0]    c_tx,
    input      [63:0]    a_tx,           // M
    input      [63:0]    word,

    // ---- the two bus conductors a tone card drives, when one is fitted ----
    input                rbt_in,         // the ringback bit stream
    input                ring_cad_n_in,  // the ring cadence, LOW while ringing
    output     [63:0]    c_rx,
    output     [63:0]    a_rx,           // E, in the ring cadence while the port rings

    // ---- cable B: the control bus, serial (exch-mainboard.md 2.3) --------
    input                sdata,
    input                sclk,
    input                wr,
    output               pb_busy,
    output               pb_word,
    output     [63:0]    port_busy,      // each block's eight BUSY lines, for its monitor

    // ---- cable A: the clocks, and the sixteen highway conductors ---------
    output     [7:0]     hc,             // brought out so a trunk card can tap its block
    output     [7:0]     ha,
    output     [2:0]     slot,
    output     [2:0]     slotq,
    output     [2:0]     tick,           // the cell's eighths: a trunk card's encoder wants them
    output               hclk,
    output               hb,
    output               tx_clk,
    output               frame_stb,
    output               tx_oct,
    output               rx_oct,
    output               fill,
    output               ring_cad_n,     // the conductor as it ends up: card, or clock card
    output               tick_1k
);
    wire       cap_stb;
    wire [7:0]  hc_from_block, ha_from_block, blk_to_block;
    wire [63:0] blk_dec;
    wire [7:0] pb_busy_b, pb_word_b;
    wire       ring_cad_n_clk;

    clock_card #(.RING_ON(RING_ON), .RING_OFF(RING_OFF)) u_clk (
        .clk(clk), .rst_n(rst_n),
        .tick(tick), .hclk(hclk), .hb(hb), .slot(slot), .slotq(slotq),
        .cap_stb(cap_stb), .tx_clk(tx_clk), .frame_stb(frame_stb),
        .tx_oct(tx_oct), .rx_oct(rx_oct), .fill(fill),
        .ring_cad_n(ring_cad_n_clk), .tick_1k(tick_1k));

    // The clock card keeps a PULL on /RING_CAD, not a driver, once a tone card
    // owns it: undriven and pulled high no phone would ever ring, so it is
    // pulled LOW and a shelf with no tone card rings continuously instead
    // (common/tone-plan.md 4.3).
    assign ring_cad_n = TONE_CARD ? ring_cad_n_in : ring_cad_n_clk;

    // The ribbon, and the shunt field at every tap.
    mainboard #(.SHUNT(SHUNT), .SHUNT_FITTED(SHUNT_FITTED & BLOCK_FITTED)) u_mb (
        .fill_pull({8{fill}}),
        .hc_from_block(hc_from_block), .ha_from_block(ha_from_block),
        .blk_dec(blk_dec), .hc(hc), .ha(ha), .blk_to_block(blk_to_block));

    wire rbt = TONE_CARD ? rbt_in : (RBT_IS_FILL ? fill : 1'b0);

    genvar h;
    generate for (h = 0; h < `NB; h = h + 1) begin : blocks
        if (BLOCK_FITTED[h]) begin : fitted
            block #(.H(h[2:0]),
                    .PORT_FITTED(PORT_FITTED[h*8 +: 8]),
                    .PORT_RINGS(PORT_RINGS[h*8 +: 8]),
                    .T_RISE(T_RISE), .T_FALL(T_FALL)) u_block (
                .clk(clk), .rst_n(rst_n),
                .slot(slot), .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
                .fill(fill), .rbt(rbt), .ring_cad_n(ring_cad_n),
                .hc(hc), .ha(ha),
                .hc_out(hc_from_block[h]), .ha_out(ha_from_block[h]),
                .c_tx(c_tx[h*8 +: 8]), .a_tx(a_tx[h*8 +: 8]), .word(word[h*8 +: 8]),
                .c_rx(c_rx[h*8 +: 8]), .a_rx(a_rx[h*8 +: 8]),
                .blk(blk_to_block[h]), .sdata(sdata), .sclk(sclk), .wr(wr),
                .blk_dec(blk_dec[h*8 +: 8]),
                .pb_busy(pb_busy_b[h]), .pb_word(pb_word_b[h]),
                .port_busy(port_busy[h*8 +: 8]));
        end else begin : absent
            // No block in this position: it drives nothing, and the mainboard
            // pulls its column to FILL.  A cleared latch listens to port 00,
            // which is on block 0 and is never fitted anyway (mvp-ex.md 2).
            assign hc_from_block[h] = 1'b0;
            assign ha_from_block[h] = 1'b0;
            assign c_rx[h*8 +: 8]   = 8'h00;
            assign a_rx[h*8 +: 8]   = 8'h00;
            assign pb_busy_b[h]     = 1'b0;
            assign pb_word_b[h]     = 1'b0;
            assign blk_dec[h*8 +: 8]   = 8'h00;
            assign port_busy[h*8 +: 8] = 8'h00;
        end
    end endgenerate

    assign pb_busy = |pb_busy_b;     // tri-state in 74HC, pulled low at the marker
    assign pb_word = |pb_word_b;
endmodule

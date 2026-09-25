// exch -- ONE exchange: the clock card, the mainboard and the eight block
// positions.  Nothing that plugs in -- no marker, no register, no network
// unit, no card.  Those are instantiated beside it, which is why a port has
// no idea what it is and why a trunk card can tap HC and /HA from outside.
//
// The hierarchy is the layout.  Each module is a thing you could point at in
// a rack, and the module boundaries are the connectors.
//
// top_min and top_max both instantiate THIS, unchanged, so that "the maximal
// build is the same fabric" is true by construction rather than by care.
//
// A block position with no shunts drives nothing and its conductor is pulled
// to FILL -- which is exactly what an unfitted block is, so BLOCK_FITTED is
// spelled as SHUNT_FITTED and PORT_FITTED and needs no separate switch.
`timescale 1ns/1ps
`include "exch.vh"

module exch #(
    parameter [63:0] PORT_FITTED  = 64'h0000_0000_0003_0000,  // mvp.md 1: ports 20 and 21
    parameter [23:0] SHUNT        = 24'o76543210,
    parameter [7:0]  SHUNT_FITTED = 8'b0000_0100,             // mvp.md 1: block 2 alone
    parameter        RBT_IS_FILL  = 1'b1,   // no ringback card: a caller hears silence
    parameter [8:0]  T_ARM        = 9'd16,
    parameter [8:0]  T_REL        = 9'd256,
    parameter [12:0] RING_ON_MS   = 13'd2048,
    parameter [12:0] RING_OFF_MS  = 13'd4096
)(
    input                    clk,          // the 4.096 MHz crystal
    input                    rst_n,

    // ---- the 64 channel sockets --------------------------------------------
    input      [63:0]        c_tx,         // a5
    input      [63:0]        a_tx,         // a6.  M
    input      [63:0]        ans_n,        // a13.  /ANS, open = this port rings
    input      [63:0]        word_n,       // a12.  the card word pin.  MAXIMAL
    output     [63:0]        c_rx,         // a9
    output     [63:0]        a_rx,         // a10

    // ---- the block headers' commons ----------------------------------------
    input      [7:0]         mute_blk,

    // ---- the ringback tone card --------------------------------------------
    input                    rbt_in,

    // ---- cable B, in: a marker or a console has the bus ---------------------
    input                    sdata,
    input                    sclk,
    input                    wr,
    output                   hw_n,         // MAXIMAL: /HW, the pointed card's word

    // ---- cable A, out: for the marker, the registers and any observer ------
    output     [7:0]         hc,
    output                   ha_n,         // the M plane
    output                   hb_n,         // the BUSY plane, same address, same instant
    output     [2:0]         tick,         // the master tick's phase in a cell; HCLK
                                           // and LINE_HB are taps of it
    output     [2:0]         slot,
    output     [2:0]         slotq,
    output                   hclk,
    output                   line_hb,
    output                   cap_stb,
    output                   tx_clk,
    output                   frame_stb,
    output                   clk_8k,
    output                   rx_oct,
    output                   oct_stb,
    output     [`SCANW-1:0]  scan,
    output                   pass_stb,
    output                   fill,
    output                   ring_cad_n,
    output                   tick_1k,

    // ---- for a monitor ------------------------------------------------------
    output     [63:0]        port_busy
);
    clock_card #(.RING_ON_MS(RING_ON_MS), .RING_OFF_MS(RING_OFF_MS)) u_clk (
        .clk(clk), .rst_n(rst_n),
        .tick(tick), .hclk(hclk), .line_hb(line_hb),
        .slot(slot), .slotq(slotq), .cap_stb(cap_stb),
        .tx_clk(tx_clk), .frame_stb(frame_stb), .clk_8k(clk_8k),
        .rx_oct(rx_oct), .oct_stb(oct_stb),
        .scan(scan), .pass_stb(pass_stb),
        .fill(fill), .ring_cad_n(ring_cad_n), .tick_1k(tick_1k));

    // RBT is pulled to FILL at the clock card when no ringback card is fitted,
    // so a caller hears silence while the far phone rings (mvp.md 2) -- the
    // same mechanism as an unfitted block, not a special case.
    wire rbt = RBT_IS_FILL ? fill : rbt_in;

    wire [7:0]  hc_from_block, ha_pd_from_block, hb_pd_from_block;
    wire [7:0]  hw_pd_from_block;
    wire [63:0] blk_dec;
    wire [7:0]  blk_n;

    // ---- the eight block positions -----------------------------------------
    // A generate: eight identical boards in eight identical connectors.  Each
    // is still a thing in the hierarchy, as pos[p].u_blk.
    //
    // A BLOCK'S NUMBER IS WHAT ITS SHUNT SAYS, NOT WHERE IT SITS.  BLOCK is
    // the highway this position is jumpered onto, carried down the ribbon to
    // its eight port circuits, so a port's turn on /HA and /HB is the same
    // number as its highway.  With the identity shunt position p is block p
    // and nothing changes; with any other shunt the two differ, and the old
    // `.BLOCK(3'dp)` put a port's supervision under one number and its voice
    // under another.  (mainboard.md 4, port-card.md)
    //
    // A position with no shunt still gets a number here -- whatever the
    // SHUNT field says for it -- and its port circuits, if any are stuffed,
    // will take that turn on the planes.  That is the "shunts left out" fault
    // of mainboard.md 6, and it reads here as the collision it is.
    genvar p;
    generate
        for (p = 0; p < 8; p = p + 1) begin : pos
            block #(.BLOCK(SHUNT[p*3 +: 3]), .PORT_FITTED(PORT_FITTED[p*8 +: 8]),
                    .T_ARM(T_ARM), .T_REL(T_REL)) u_blk (
                .clk(clk), .rst_n(rst_n),
                .slot(slot), .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
                .tick_1k(tick_1k), .scan(scan), .fill(fill), .rbt(rbt),
                .ring_cad_n(ring_cad_n),
                .hc(hc), .hc_out(hc_from_block[p]),
                .ha_n(ha_n), .ha_pd(ha_pd_from_block[p]), .hb_pd(hb_pd_from_block[p]),
                .c_tx(c_tx[p*8 +: 8]), .a_tx(a_tx[p*8 +: 8]),
                .ans_n(ans_n[p*8 +: 8]), .word_n(word_n[p*8 +: 8]),
                .c_rx(c_rx[p*8 +: 8]), .a_rx(a_rx[p*8 +: 8]),
                .mute_blk(mute_blk[p]),
                .sdata(sdata), .sclk(sclk), .wr(wr), .blk_n(blk_n[p]),
                .blk_dec(blk_dec[p*8 +: 8]), .hw_pd(hw_pd_from_block[p]),
                .port_busy(port_busy[p*8 +: 8]));
        end
    endgenerate

    mainboard #(.SHUNT(SHUNT), .SHUNT_FITTED(SHUNT_FITTED)) u_mb (
        .fill(fill),
        .hc_from_block(hc_from_block),
        .ha_pd_from_block(ha_pd_from_block),
        .hb_pd_from_block(hb_pd_from_block),
        .blk_dec(blk_dec),
        .hw_pd_from_block(hw_pd_from_block),
        .hc(hc), .ha_n(ha_n), .hb_n(hb_n), .blk_n(blk_n), .hw_n(hw_n));
endmodule

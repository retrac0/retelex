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
// A block is FITTED when its header jumper is: no jumper, no number, and the
// block drives no highway, answers no word and its ports take no turn.  So
// BLOCK_FITTED is one fact a position, and PORT_FITTED is one a socket.
`timescale 1ns/1ps
`include "exch.vh"

module exch #(
    parameter [63:0] PORT_FITTED  = 64'h0000_0000_0003_0000,  // mvp.md 1: ports 20 and 21
    parameter [23:0] BLOCK_NUM    = 24'o76543210,             // each header's jumper, octal, position 0 rightmost
    parameter [7:0]  BLOCK_FITTED = 8'b0000_0100,             // mvp.md 1: block 2 alone
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

    // ---- the bus, in: a marker or a console has the control lines -----------
    input                    sdata,
    input                    sclk,
    input                    wr,
    // MAXIMAL: /WS, the select.  Its drains are the READERS', beside the
    // exchange, so it arrives here resolved, as cable B does: a reader pulls
    // it in a port's bit-time, and that port's card answers on /HW
    input                    ws_n,
    output                   hw_n,         // MAXIMAL: /HW, the selected card's word

    // ---- the bus, out: for the marker, the registers and any observer -------
    output     [7:0]         hc,
    output                   ha_n,         // the M plane
    output                   hb_n,         // the BUSY plane, same address, same instant
    output     [2:0]         tick,         // the master tick's phase in a cell; HCLK
                                           // is a tap of it
    output     [2:0]         slot,
    output     [2:0]         slotq,
    output                   hclk,
    output                   cap_stb,
    output                   frame_stb,    // SLOT2's fall: the frame edge
    output     [`SCANW-1:0]  scan,
    output                   ring_cad_n,

    // ---- NOT the bus: what each block makes from SLOT2 and SCAN ------------
    // (frame_decode.v).  Brought out for the sockets and the benches, which
    // sit outside the blocks in this model; on a board every block has its own
    output                   tx_clk,       // socket a1
    output                   clk_8k,       // socket a3, TX_OCT
    output                   rx_oct,       // socket a8
    output                   oct_stb,
    output                   fill,         // socket a4: SCAN0
    output                   tick_1k,      // SCAN5's fall, as a strobe
    output                   pass_stb,     // the same edge, by its other name

    // ---- for a monitor ------------------------------------------------------
    output     [63:0]        port_busy
);
    clock_card #(.RING_ON_MS(RING_ON_MS), .RING_OFF_MS(RING_OFF_MS)) u_clk (
        .clk(clk), .rst_n(rst_n),
        .tick(tick), .hclk(hclk),
        .slot(slot), .slotq(slotq), .cap_stb(cap_stb),
        .frame_stb(frame_stb), .scan(scan), .ring_cad_n(ring_cad_n));

    // ---- each block's decode, modelled once: the eight are identical ------
    frame_decode u_dec (
        .slot2(slot[2]), .frame_stb(frame_stb), .scan(scan),
        .tx_clk(tx_clk), .tx_oct(clk_8k), .rx_oct(rx_oct), .oct_stb(oct_stb),
        .fill(fill), .tick_1k(tick_1k));
    assign pass_stb = tick_1k;

    // RBT is pulled to SCAN0 -- which is FILL -- when no ringback card is
    // fitted, so a caller hears silence while the far phone rings (mvp.md 2):
    // the same mechanism as an unfitted block, not a special case.
    wire rbt = RBT_IS_FILL ? fill : rbt_in;

    wire [7:0]  hc_from_block, ha_pd_from_block, hb_pd_from_block;
    wire [7:0]  hw_pd_from_block;

    // ---- the eight block positions -----------------------------------------
    // A generate: eight identical boards in eight identical connectors.  Each
    // is still a thing in the hierarchy, as pos[p].u_blk.
    //
    // A BLOCK'S NUMBER IS ITS OWN HEADER JUMPER.  BLOCK_NUM[p] is what the
    // jumper in position p is set to: the highway its HC_OUT is routed onto,
    // and -- through the '148 behind the same jumper -- the h its '688 matches
    // DST[5:3] against and the h its port circuits take their turn under.
    // One strap, three uses; the mainboard holds none of it.  BLOCK_FITTED[p]
    // is the '148's GS: no jumper, no number, and the block is silent.
    //
    // With the identity setting position p is block p, and nothing about
    // position ever mattered except which socket a card's C_TX enters.
    genvar p;
    generate
        for (p = 0; p < 8; p = p + 1) begin : pos
            block #(.BLOCK(BLOCK_NUM[p*3 +: 3]), .JUMPERED(BLOCK_FITTED[p]),
                    .PORT_FITTED(PORT_FITTED[p*8 +: 8]),
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
                .sdata(sdata), .sclk(sclk), .wr(wr),
                .ws_n(ws_n), .hw_pd(hw_pd_from_block[p]),
                .port_busy(port_busy[p*8 +: 8]));
        end
    endgenerate

    mainboard #(.BLOCK_NUM(BLOCK_NUM), .BLOCK_FITTED(BLOCK_FITTED)) u_mb (
        .fill(fill),
        .hc_from_block(hc_from_block),
        .ha_pd_from_block(ha_pd_from_block),
        .hb_pd_from_block(hb_pd_from_block),
        .hw_pd_from_block(hw_pd_from_block),
        .hc(hc), .ha_n(ha_n), .hb_n(hb_n), .hw_n(hw_n));
endmodule

// block -- eight ports and what they share.  fabric.md 3.1.
//
// A block owns one highway.  Its commutator is a '151 with the eight ports'
// C_TX on its inputs and SLOT on its selects: a rotary switch turning at
// 64 kHz, which is, part for part, an MF8 trunk transmitter's frame mux.
// Which highway it drives and which /BLK line is its own come from the
// mainboard's shunt field -- layout, not logic.
//
// WHAT THIS BLOCK NO LONGER HAS, against fabric.md 3.1:
//   the A commutator            -- HA[0..7] are gone; each port drives /HA itself
//   the BUSY commutator         -- BUSY is /HB, a second scanned conductor
//   the word commutator         -- the word is /HW, driven by the card the
//                                  marker pointed at; there is no '151 and no
//                                  /BLK gate left in the word path
//   the HA_OUT driver and its shunt column -- the shunt field is two columns now
//   the SCAN[2:0] receivers     -- SCAN[5:0] comes off cable A, six conductors
//   con_n and the pb_sel mux    -- the console reads /HA like everyone else
//   PB[1:0] entirely            -- nothing block-steered is read any more
// All four '151s go.  The block gains nothing on the fabric side: it passes
// SCAN, /HA and /HB through to its eight ports and ORs their drains.
//
// THE BLOCK STILL HAS NO ADDRESS AND NO COMPARATOR.  BLOCK is carried only so
// that it can be strapped through to the port circuits, which do need to know
// their own number to take their turn on the supervision planes
// (port-card.md's BLOCK[0..2]).  Which highway this block drives is still the
// shunt's business and not this parameter's.
`timescale 1ns/1ps
`include "exch.vh"

module block #(
    parameter [2:0]  BLOCK       = 3'd0,    // strapped through to the eight port circuits
    parameter [7:0]  PORT_FITTED = 8'hFF,   // which of the eight port circuits are populated
    parameter [8:0]  T_ARM       = 9'd16,
    parameter [8:0]  T_REL       = 9'd256
)(
    input                   clk,
    input                   rst_n,

    // ---- cable A -----------------------------------------------------------
    input      [2:0]        slot,        // the commutator's address
    input      [2:0]        slotq,       // the strobe decoder's address
    input                   cap_stb,
    input                   frame_stb,
    input                   tick_1k,
    input      [`SCANW-1:0] scan,
    input                   fill,
    input                   rbt,
    input                   ring_cad_n,
    input      [7:0]        hc,          // all eight highways come back in
    output                  hc_out,      // this block drives one of them, through its shunt
    input                   ha_n,        // /HA as received, through a '14 Schmitt:
                                         // the rise is resistive, not driven
    output                  ha_pd,       // the OR of this block's eight M drains
    output                  hb_pd,       // and of its eight BUSY drains

    // ---- the eight channel sockets ----------------------------------------
    input      [7:0]        c_tx,        // a5
    input      [7:0]        a_tx,        // a6.  M
    input      [7:0]        ans_n,       // a13.  /ANS, pulled up at the port
    input      [7:0]        word_n,      // a12.  the card word pin, pulled up.  MAXIMAL
    output     [7:0]        c_rx,        // a9
    output     [7:0]        a_rx,        // a10

    // ---- the block header commons -----------------------------------------
    input                   mute_blk,    // an adapter busies its whole group

    // ---- cable B -----------------------------------------------------------
    input                   sdata,
    input                   sclk,
    input                   wr,
    input                   blk_n,       // /BLK, back from this position's shunt column
    output     [7:0]        blk_dec,     // this block's own '138 on DST[5:3], out to the shunt
    output                  hw_pd,       // MAXIMAL: this block's drain onto /HW

    // ---- for a monitor on this block ---------------------------------------
    output     [7:0]        port_busy
);
    // ---- 2 x 74HC164: sixteen bits, shifted by SCLK, no output latch -------
    // Nothing reads these until WR, so the garbage that ripples through
    // between writes is the same garbage the parallel bus carried between
    // writes.  mainboard.md 2.3.2.
    reg [`CWW-1:0] cw;
    reg            sclk_d;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin cw <= {`CWW{1'b0}}; sclk_d <= 1'b0; end
        else begin
            sclk_d <= sclk;
            if (sclk && !sclk_d) cw <= {cw[`CWW-2:0], sdata};
        end

    // ---- 74HC138: DST[5:3] into eight lines, out to the shunt field --------
    // WIDENS WITH `PW: a four-bit block field wants a '154.
    assign blk_dec = 8'd1 << cw[13:11];

    wire [7:0] rb, ha_pd_k, hb_pd_k;
    wire [7:0] c_mux, word_com;
    wire [7:0] wr_dec;

    // ---- the guard: G . WR, a quarter package ------------------------------
    // A word that does not carry bit 15 cannot write -- but it still shifts
    // and still pulses WR, which is the event word.
    wire wr_en = !blk_n && wr && cw[`CWW-1];

    // ---- 74HC138 write decoder: /BLK . WR . G enables, DST[2:0] picks ------
    // One package, the same part as blk_dec above on a different field of the
    // same word.  WIDENS WITH `PW: a four-bit slot field wants a '154.
    assign wr_dec = wr_en ? (8'd1 << cw[10:8]) : 8'd0;

    // ---- 74HC157 x4: ringback substitution ahead of the commutator ---------
    // and the pull to FILL on an unfitted slot, exactly as an empty MF8 slot
    // is pulled.  Written out because the condition is per-slot: a scalar
    // ternary here would put RBT on all eight the moment any one port rings.
    assign c_mux[0] = PORT_FITTED[0] ? (rb[0] ? rbt : c_tx[0]) : fill;
    assign c_mux[1] = PORT_FITTED[1] ? (rb[1] ? rbt : c_tx[1]) : fill;
    assign c_mux[2] = PORT_FITTED[2] ? (rb[2] ? rbt : c_tx[2]) : fill;
    assign c_mux[3] = PORT_FITTED[3] ? (rb[3] ? rbt : c_tx[3]) : fill;
    assign c_mux[4] = PORT_FITTED[4] ? (rb[4] ? rbt : c_tx[4]) : fill;
    assign c_mux[5] = PORT_FITTED[5] ? (rb[5] ? rbt : c_tx[5]) : fill;
    assign c_mux[6] = PORT_FITTED[6] ? (rb[6] ? rbt : c_tx[6]) : fill;
    assign c_mux[7] = PORT_FITTED[7] ? (rb[7] ? rbt : c_tx[7]) : fill;

    // ---- the card word pins, a12 -------------------------------------------
    // Low for a one; open reads no word at all, which is class 000,
    // unequipped.  MAXIMAL.
    assign word_com = PORT_FITTED & ~word_n;

    port #(.FITTED(PORT_FITTED[0]), .BLOCK(BLOCK), .POS(3'd0),
           .T_ARM(T_ARM), .T_REL(T_REL)) u_port0 (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .tick_1k(tick_1k),
        .scan(scan), .ring_cad_n(ring_cad_n),
        .hc(hc), .ha_n(ha_n), .ha_pd(ha_pd_k[0]), .hb_pd(hb_pd_k[0]),
        .a_tx(a_tx[0]), .ans_n(ans_n[0]),
        .c_rx(c_rx[0]), .a_rx(a_rx[0]),
        .mute_blk(mute_blk), .rb(rb[0]), .busy(port_busy[0]),
        .wr(wr_dec[0]), .src(cw[7:2]), .bsy_in(cw[1]), .clm_in(cw[0]));

    port #(.FITTED(PORT_FITTED[1]), .BLOCK(BLOCK), .POS(3'd1),
           .T_ARM(T_ARM), .T_REL(T_REL)) u_port1 (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .tick_1k(tick_1k),
        .scan(scan), .ring_cad_n(ring_cad_n),
        .hc(hc), .ha_n(ha_n), .ha_pd(ha_pd_k[1]), .hb_pd(hb_pd_k[1]),
        .a_tx(a_tx[1]), .ans_n(ans_n[1]),
        .c_rx(c_rx[1]), .a_rx(a_rx[1]),
        .mute_blk(mute_blk), .rb(rb[1]), .busy(port_busy[1]),
        .wr(wr_dec[1]), .src(cw[7:2]), .bsy_in(cw[1]), .clm_in(cw[0]));

    port #(.FITTED(PORT_FITTED[2]), .BLOCK(BLOCK), .POS(3'd2),
           .T_ARM(T_ARM), .T_REL(T_REL)) u_port2 (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .tick_1k(tick_1k),
        .scan(scan), .ring_cad_n(ring_cad_n),
        .hc(hc), .ha_n(ha_n), .ha_pd(ha_pd_k[2]), .hb_pd(hb_pd_k[2]),
        .a_tx(a_tx[2]), .ans_n(ans_n[2]),
        .c_rx(c_rx[2]), .a_rx(a_rx[2]),
        .mute_blk(mute_blk), .rb(rb[2]), .busy(port_busy[2]),
        .wr(wr_dec[2]), .src(cw[7:2]), .bsy_in(cw[1]), .clm_in(cw[0]));

    port #(.FITTED(PORT_FITTED[3]), .BLOCK(BLOCK), .POS(3'd3),
           .T_ARM(T_ARM), .T_REL(T_REL)) u_port3 (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .tick_1k(tick_1k),
        .scan(scan), .ring_cad_n(ring_cad_n),
        .hc(hc), .ha_n(ha_n), .ha_pd(ha_pd_k[3]), .hb_pd(hb_pd_k[3]),
        .a_tx(a_tx[3]), .ans_n(ans_n[3]),
        .c_rx(c_rx[3]), .a_rx(a_rx[3]),
        .mute_blk(mute_blk), .rb(rb[3]), .busy(port_busy[3]),
        .wr(wr_dec[3]), .src(cw[7:2]), .bsy_in(cw[1]), .clm_in(cw[0]));

    port #(.FITTED(PORT_FITTED[4]), .BLOCK(BLOCK), .POS(3'd4),
           .T_ARM(T_ARM), .T_REL(T_REL)) u_port4 (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .tick_1k(tick_1k),
        .scan(scan), .ring_cad_n(ring_cad_n),
        .hc(hc), .ha_n(ha_n), .ha_pd(ha_pd_k[4]), .hb_pd(hb_pd_k[4]),
        .a_tx(a_tx[4]), .ans_n(ans_n[4]),
        .c_rx(c_rx[4]), .a_rx(a_rx[4]),
        .mute_blk(mute_blk), .rb(rb[4]), .busy(port_busy[4]),
        .wr(wr_dec[4]), .src(cw[7:2]), .bsy_in(cw[1]), .clm_in(cw[0]));

    port #(.FITTED(PORT_FITTED[5]), .BLOCK(BLOCK), .POS(3'd5),
           .T_ARM(T_ARM), .T_REL(T_REL)) u_port5 (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .tick_1k(tick_1k),
        .scan(scan), .ring_cad_n(ring_cad_n),
        .hc(hc), .ha_n(ha_n), .ha_pd(ha_pd_k[5]), .hb_pd(hb_pd_k[5]),
        .a_tx(a_tx[5]), .ans_n(ans_n[5]),
        .c_rx(c_rx[5]), .a_rx(a_rx[5]),
        .mute_blk(mute_blk), .rb(rb[5]), .busy(port_busy[5]),
        .wr(wr_dec[5]), .src(cw[7:2]), .bsy_in(cw[1]), .clm_in(cw[0]));

    port #(.FITTED(PORT_FITTED[6]), .BLOCK(BLOCK), .POS(3'd6),
           .T_ARM(T_ARM), .T_REL(T_REL)) u_port6 (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .tick_1k(tick_1k),
        .scan(scan), .ring_cad_n(ring_cad_n),
        .hc(hc), .ha_n(ha_n), .ha_pd(ha_pd_k[6]), .hb_pd(hb_pd_k[6]),
        .a_tx(a_tx[6]), .ans_n(ans_n[6]),
        .c_rx(c_rx[6]), .a_rx(a_rx[6]),
        .mute_blk(mute_blk), .rb(rb[6]), .busy(port_busy[6]),
        .wr(wr_dec[6]), .src(cw[7:2]), .bsy_in(cw[1]), .clm_in(cw[0]));

    port #(.FITTED(PORT_FITTED[7]), .BLOCK(BLOCK), .POS(3'd7),
           .T_ARM(T_ARM), .T_REL(T_REL)) u_port7 (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .tick_1k(tick_1k),
        .scan(scan), .ring_cad_n(ring_cad_n),
        .hc(hc), .ha_n(ha_n), .ha_pd(ha_pd_k[7]), .hb_pd(hb_pd_k[7]),
        .a_tx(a_tx[7]), .ans_n(ans_n[7]),
        .c_rx(c_rx[7]), .a_rx(a_rx[7]),
        .mute_blk(mute_blk), .rb(rb[7]), .busy(port_busy[7]),
        .wr(wr_dec[7]), .src(cw[7:2]), .bsy_in(cw[1]), .clm_in(cw[0]));

    // ---- 74HC151: THE commutator.  The whole switch, once a block. ---------
    // Input k is port k; SLOT steps 0 to 7 once a frame, so the output is
    // port 0's bit for the first 1.95 us, port 1's for the next, and so on.
    // Buffered by a '244, that is this block's highway.
    assign hc_out = c_mux[slot];

    // ---- the open drains, wired together -----------------------------------
    // In 74HC these 2N7002 sources sit on two conductors with one 4.7 k pull-up
    // each at the clock card; there is nothing here to OR.  The mainboard does
    // the wired-OR and the inversion into /HA and /HB.  Both are ungated by the
    // shunt on purpose: a port's turn is its NUMBER, and its number does not
    // move when the block is shunted onto a different highway.
    assign ha_pd = |ha_pd_k;
    assign hb_pd = |hb_pd_k;

    // ---- MAXIMAL: the card word on /HW -------------------------------------
    // NOT a commutator and NOT /BLK-gated.  All 64 cards share one conductor;
    // the marker points at a port by leaving a word in the shift registers
    // whose DST names it, and that one card drives /HW, a bit a frame at
    // 64 kHz, for sixteen frames -- 250 us for a whole word.
    //
    // The select is the WHOLE six-bit DST, so this block answers only when
    // DST[5:3] is its own shunt column AND DST[2:0] picks one of its slots.
    // blk_n already carries the first half, back from the shunt field, which
    // is why the comparison here is only the slot.
    //
    // Nothing continuous depends on /HW.  The scanner never waits for it, no
    // hunt is gated on it, and a word in flight cannot disturb a supervision
    // sample -- which is the whole reason the word is not on the scan.
    // A minimal block leaves the footprint unstuffed.
    assign hw_pd = !blk_n && word_com[cw[10:8]];

    // frame_stb reaches the ports' sockets, not the port circuits: the
    // detectors run off TICK and the captures off SLOTQ.  It is carried so a
    // channel card on this block's ribbon has its frame reference.
    wire _unused = &{1'b0, frame_stb, 1'b0};
endmodule

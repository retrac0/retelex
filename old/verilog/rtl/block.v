// block -- eight ports and what they share.  fabric.md 3.1.
//
// A block owns one highway pair.  Its commutator is a '151 with the eight
// ports' C_TX on its inputs and SLOT on its selects: a rotary switch turning at
// 64 kHz, which is, part for part, an MF8 trunk transmitter's frame mux.  The
// block knows nothing else -- no address, no comparator, no class.  Which
// highway it drives and which BLK select is its own come from the mainboard's
// shunt field (mainboard.md 1), here the H parameter.
`timescale 1ns/1ps
`include "exch_defs.vh"

module block #(
    /* verilator lint_off UNUSEDPARAM */
    // This block's number.  Nothing in here reads it -- which is the point:
    // a block has no address and no comparator, and which highway it drives
    // comes from the mainboard's shunt field (mainboard.md 1).  It is
    // carried only so the instance names itself in a waveform.
    parameter [2:0]  H            = 3'd0,
    /* verilator lint_on UNUSEDPARAM */
    parameter [7:0]  PORT_FITTED  = 8'hFF,      // which of the eight port circuits are populated
    parameter [7:0]  PORT_RINGS   = 8'hFF,      // /ANS open: a phone's card, so the port rings
    parameter integer T_RISE      = 1024,
    parameter integer T_FALL      = 16384
)(
    input             clk,
    input             rst_n,

    input      [2:0]  slot,
    input      [2:0]  slotq,
    input             cap_stb,
    input             frame_stb,
    input             fill,
    input             rbt,
    input             ring_cad_n,

    input      [7:0]  hc,            // all sixteen highways come back in
    input      [7:0]  ha,
    output            hc_out,        // this block drives one wire of each
    output            ha_out,

    // the eight cards
    input      [7:0]  c_tx,
    input      [7:0]  a_tx,
    input      [7:0]  word,          // the card's class and options, 16 bits at 128 kHz
    output     [7:0]  c_rx,
    output     [7:0]  a_rx,

    // the control bus, serial (mainboard.md 2.3)
    input             blk,           // /BLK, back from this position's shunt column
    input             sdata,
    input             sclk,
    input             wr,
    input             con_n,         // high: marker owns the bus; low: console
    input      [2:0]  scan_port,     // marker scanner[2:0] — probe select while con_n
    output     [7:0]  blk_dec,       // this block's own '138 on DST[5:3], out to the shunt
    output            pb_busy,       // the probe bus, driven only while BLK[H]
    output            pb_word,
    output     [7:0]  port_busy      // the eight ports' BUSY, for a monitor on this block
);
    wire [7:0] rb, a_hw, busy_hw;
    wire       pb_busy_i, pb_word_i;

    // Two 74HC164: sixteen bits, shifted by SCLK, with no output latch.  Nothing
    // reads the outputs until WR, so the garbage that ripples through between
    // writes is the same garbage the parallel bus carried between writes.
    reg [15:0] cw;
    reg        sclk_d;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin cw <= 16'd0; sclk_d <= 1'b0; end
        else begin
            sclk_d <= sclk;
            if (sclk && !sclk_d) cw <= {cw[14:0], sdata};
        end

    assign blk_dec = 8'd1 << cw[13:11];        // the '138, out to the mainboard
    wire [7:0] c_mux, a_com, busy_com, word_com;
    wire [7:0] wr_dec;

    genvar k;
    generate for (k = 0; k < 8; k = k + 1) begin : slots
        // the write decoder: BLK[H] . WR enables, PORT[2:0] picks the latch
        // BLK[h].WR became /BLK . WR . G: a word without the guard cannot write
        assign wr_dec[k] = blk && wr && cw[15] && (cw[10:8] == k[2:0]);

        // an unpopulated slot: C pulled to FILL, A and BUSY to 0, no word.
        // fabric.md 1.1 -- exactly as an empty MF8 slot is pulled.
        assign c_mux[k]    = PORT_FITTED[k] ? (rb[k] ? rbt : c_tx[k]) : fill;   // the '157
        assign a_com[k]    = PORT_FITTED[k] ? a_hw[k]    : 1'b0;
        assign busy_com[k] = PORT_FITTED[k] ? busy_hw[k] : 1'b0;
        assign word_com[k] = PORT_FITTED[k] ? word[k]    : 1'b0;

        port #(.FITTED(PORT_FITTED[k]), .RINGS(PORT_RINGS[k]),
               .T_RISE(T_RISE), .T_FALL(T_FALL)) u_port (
            .clk(clk), .rst_n(rst_n),
            .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
            .ring_cad_n(ring_cad_n),
            .hc(hc), .ha(ha),
            .a_tx(a_tx[k]), .c_rx(c_rx[k]), .a_rx(a_rx[k]),
            .rb(rb[k]), .a_hw(a_hw[k]), .busy_hw(busy_hw[k]),
            .wr(wr_dec[k]), .src(cw[7:2]), .bsy_in(cw[1]), .clm_in(cw[0]));
    end endgenerate

    // Highway commutators on SLOT.  Probe BUSY and word: while the marker
    // owns the bus, the scanner's low three bits (same field as DST[2:0]) hold
    // the port for the whole visit so a 16-bit word at 128 kHz fits one octet.
    // The console's PROBE uses the serial word's DST[2:0] instead (fabric.md 1,
    // extensions.md 2.2).  Write decoder still reads DST from the '164.
    wire [2:0] pb_sel = con_n ? scan_port : cw[10:8];
    mux8 u_cc (.d(c_mux),    .s(slot),     .y(hc_out));
    mux8 u_ca (.d(a_com),    .s(slot),     .y(ha_out));
    mux8 u_cb (.d(busy_com), .s(pb_sel),   .y(pb_busy_i));
    mux8 u_cw (.d(word_com), .s(pb_sel),   .y(pb_word_i));

    // In 74HC the probe bus is tri-state, one block enabled by BLK[H], pulled
    // LOW at the marker so an absent block reads as eight unequipped slots
    // (mainboard.md 6).  A mux at the top does the same job here.
    assign port_busy = busy_com;

    assign pb_busy = blk ? pb_busy_i : 1'b0;
    assign pb_word = blk ? pb_word_i : 1'b0;
endmodule

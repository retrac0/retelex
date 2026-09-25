// top_min -- THE MINIMAL EXCHANGE.  mvp.md.
//
// The smallest exchange that does automatic calls: two phones dial each other
// with two digits, one rings, the other hears it ringing, they talk, and
// either can hang up first, with nobody in charge of the call.
//
// Six-bit two-digit addressing, no network unit, the small marker.  Every
// part of it is a part of the full exchange: it grows into the 48-line
// exchange by adding cards, never by changing the fabric or the line cards.
//
// top_max instantiates THE SAME `exch`, unchanged, and adds the class marker,
// a register pool, a network unit and monitors beside it.  What is MAXIMAL
// here is one wire -- hw_n, the card word bus -- brought out and left unused.
`timescale 1ns/1ps
`include "exch.vh"

module top_min #(
    parameter [63:0] PORT_FITTED  = 64'h0000_0000_0003_0000,  // ports 20 and 21
    parameter [23:0] SHUNT        = 24'o76543210,
    parameter [7:0]  SHUNT_FITTED = 8'b0000_0100,             // block 2 alone
    parameter [8:0]  T_ARM        = 9'd16,
    parameter [8:0]  T_REL        = 9'd256,
    parameter [12:0] RING_ON_MS   = 13'd2048,
    parameter [12:0] RING_OFF_MS  = 13'd4096,
    parameter [15:0] NODIG        = 16'd10000   // register.md 6; see pulse_reg
)(
    input             clk,          // the 4.096 MHz crystal
    input             rst_n,

    // ---- the 64 channel sockets: cards plug in BESIDE the exchange --------
    input      [63:0] c_tx,
    input      [63:0] a_tx,
    input      [63:0] ans_n,
    input      [63:0] word_n,
    output     [63:0] c_rx,
    output     [63:0] a_rx,

    input      [7:0]  mute_blk,
    input             rbt_in,

    // ---- what a bench, a lamp field or a network unit watches -------------
    output     [7:0]  hc,
    output            ha_n,
    output            hb_n,
    output     [`SCANW-1:0] scan,
    output            frame_stb,
    output            pass_stb,
    output            tick_1k,
    output            fill,
    output            ring_cad_n,
    output     [63:0] port_busy,

    // MAXIMAL: /HW, the card word bus.  No card drives it on a minimal build,
    // so it sits at its pull-up and reads all ones.  ALL ONES IS NOT A WORD --
    // see mainboard.v -- so the class marker must pair a read with the BUSY it
    // already has and treat a silent sixteen frames as unequipped.  Brought
    // out so that fitting the class marker is fitting a card, not a rewire.
    output            hw_n,

    output     [`PW-1:0] probe_port,
    output            probe_m,
    output            probe_busy,
    output            probe_fresh,
    output            reg_busy,
    output     [2:0]  reg_ndig,
    output     [15:0] reg_digits,
    output     [`PW-1:0] caller,
    output     [`PW-1:0] called,
    output     [1:0]  mk_state
);
    wire [2:0] slot, slotq, tick;
    wire hclk, line_hb, cap_stb, tx_clk, clk_8k, rx_oct, oct_stb;
    wire m_sdata, m_sclk, m_wr;

    exch #(.PORT_FITTED(PORT_FITTED), .SHUNT(SHUNT),
           .SHUNT_FITTED(SHUNT_FITTED), .T_ARM(T_ARM), .T_REL(T_REL),
           .RING_ON_MS(RING_ON_MS), .RING_OFF_MS(RING_OFF_MS)) u_exch (
        .clk(clk), .rst_n(rst_n),
        .c_tx(c_tx), .a_tx(a_tx), .ans_n(ans_n), .word_n(word_n),
        .c_rx(c_rx), .a_rx(a_rx),
        .mute_blk(mute_blk), .rbt_in(rbt_in),
        .sdata(m_sdata), .sclk(m_sclk), .wr(m_wr), .hw_n(hw_n),
        .hc(hc), .ha_n(ha_n), .hb_n(hb_n), .tick(tick),
        .slot(slot), .slotq(slotq),
        .hclk(hclk), .line_hb(line_hb), .cap_stb(cap_stb), .tx_clk(tx_clk),
        .frame_stb(frame_stb), .clk_8k(clk_8k), .rx_oct(rx_oct),
        .oct_stb(oct_stb),
        .scan(scan), .pass_stb(pass_stb),
        .fill(fill), .ring_cad_n(ring_cad_n), .tick_1k(tick_1k),
        .port_busy(port_busy));

    // The marker is a CARD on the common-control tap.  It reads M off /HA and
    // BUSY off /HB and drives cable B; it has no other connection to the
    // fabric.  Swap it for the class marker and nothing here changes
    // (common-control.md 1).
    mini_marker #(.NODIG(NODIG)) u_mk (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
        .scan(scan), .ha_n(ha_n), .hb_n(hb_n), .tick_1k(tick_1k),
        .sdata(m_sdata), .sclk(m_sclk), .wr(m_wr),
        .probe_port(probe_port), .probe_m(probe_m), .probe_busy(probe_busy),
        .probe_fresh(probe_fresh),
        .reg_busy(reg_busy), .reg_ndig(reg_ndig), .reg_digits(reg_digits),
        .caller_o(caller), .called_o(called), .state(mk_state));

    // Carried for a channel card on the block ribbon, not used by the exchange
    // logic: the captures run off SLOTQ and the detectors off TICK.
    wire _unused = &{1'b0, tick, hclk, line_hb, tx_clk, clk_8k, rx_oct,
                     oct_stb, slot, 1'b0};
endmodule

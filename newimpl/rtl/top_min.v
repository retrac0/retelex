// top_min -- THE MINIMAL EXCHANGE.  exchange/README.md §2.
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
// a register card, a network unit and its monitors beside it.  What is MAXIMAL
// here is two wires -- /HW, the card word bus, and /WS, the select that names
// the card on it -- brought out, and nothing on this build pulls /WS.
`timescale 1ns/1ps
`include "exch.vh"

module top_min #(
    parameter [63:0] PORT_FITTED  = 64'h0000_0000_0003_0000,  // ports 20 and 21
    parameter [23:0] BLOCK_NUM        = 24'o76543210,
    parameter [7:0]  BLOCK_FITTED = 8'b0000_0100,             // block 2 alone
    parameter [8:0]  T_ARM        = 9'd16,
    parameter [8:0]  T_REL        = 9'd256,
    parameter [12:0] RING_ON_MS   = 13'd2048,
    parameter [12:0] RING_OFF_MS  = 13'd4096,
    parameter [15:0] NODIG        = 16'd10000   // register.md §1; see pulse_reg
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
    // so it sits at its pull-up.  A card pulls it low for a 1, so a reader
    // that reads it low-true, as word_rx does, takes that as ALL ZEROS: NONE,
    // what an absent card must read -- see mainboard.v.  Brought out so that
    // fitting the class marker is fitting a card, not a rewire.
    output            hw_n,
    // MAXIMAL: /WS, the select.  The marker's reader is its only drain here,
    // and with /NET high it never reads, so /WS sits at its pull-up too.
    output            ws_n,

    output     [`PW-1:0] probe_port,
    output            probe_m,
    output            probe_busy,
    output            probe_fresh,
    output            reg_busy,
    output     [2:0]  reg_ndig,
    output     [15:0] reg_digits,
    output     [`PW-1:0] caller,
    output     [`PW-1:0] called,
    output     [2:0]  mk_state
);
    wire [2:0] slot, slotq, tick;
    wire hclk, cap_stb, tx_clk, clk_8k, rx_oct, oct_stb;
    wire m_sdata, m_sclk, m_wr, m_oe;
    // the network half's lines, with nothing on the other end of the ribbon
    wire nc_flood, nc_ack, nc_gone, nc_nodig, nc_brk, nc_ovf;
    wire [`PW-1:0] nc_rport;

    // ONE MASTER.  The marker's '244s are the only drivers on cable B, so the
    // bus is what they drive while enabled and the blocks' pull-downs when
    // not -- bus.md §6.1: SCLK and WR low, which shifts and writes nothing.
    wire b_sdata = m_oe && m_sdata;
    wire b_sclk  = m_oe && m_sclk;
    wire b_wr    = m_oe && m_wr;

    // /WS: a pull-up at the clock card and one open drain, the marker's reader
    wire m_ws_pd;
    assign ws_n = ~m_ws_pd;

    exch #(.PORT_FITTED(PORT_FITTED), .BLOCK_NUM(BLOCK_NUM),
           .BLOCK_FITTED(BLOCK_FITTED), .T_ARM(T_ARM), .T_REL(T_REL),
           .RING_ON_MS(RING_ON_MS), .RING_OFF_MS(RING_OFF_MS)) u_exch (
        .clk(clk), .rst_n(rst_n),
        .c_tx(c_tx), .a_tx(a_tx), .ans_n(ans_n), .word_n(word_n),
        .c_rx(c_rx), .a_rx(a_rx),
        .mute_blk(mute_blk), .rbt_in(rbt_in),
        .sdata(b_sdata), .sclk(b_sclk), .wr(b_wr), .ws_n(ws_n), .hw_n(hw_n),
        .hc(hc), .ha_n(ha_n), .hb_n(hb_n), .tick(tick),
        .slot(slot), .slotq(slotq),
        .hclk(hclk), .cap_stb(cap_stb), .tx_clk(tx_clk),
        .frame_stb(frame_stb), .clk_8k(clk_8k), .rx_oct(rx_oct),
        .oct_stb(oct_stb),
        .scan(scan), .pass_stb(pass_stb),
        .fill(fill), .ring_cad_n(ring_cad_n), .tick_1k(tick_1k),
        .port_busy(port_busy));

    // The marker is a CARD on the bus.  It reads M off /HA and
    // BUSY off /HB and drives cable B; it has no other connection to the
    // fabric.  Swap it for the class marker and nothing here changes
    // (exchange/README.md §2).
    //
    // NO NETWORK UNIT IS FITTED, and the lines it would drive are what an
    // empty ribbon reads: /NET and /UREQ at their pull-ups, every strobe low,
    // no claim.  With /NET high the marker reads no card word and key 1 is
    // highway 1 -- the path it took before it had a network half at all.
    // SETTLE, twice the ports' T_ARM: after a connect the marker holds the
    // register until the called port's E detector has surely risen (S_WATCH).
    mini_marker #(.NODIG(NODIG), .SETTLE(T_ARM + T_ARM)) u_mk (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
        .scan(scan), .ha_n(ha_n), .hb_n(hb_n),
        .sdata(m_sdata), .sclk(m_sclk), .wr(m_wr), .b_oe(m_oe),
        .hw_n(hw_n), .ws_n(ws_n), .ws_pd(m_ws_pd), .ureq_n(1'b1),
        .net_n(1'b1), .flood_go(nc_flood),
        .u_restart(1'b0), .u_local(1'b0), .u_done(1'b0), .u_nogo(1'b0),
        .u_att(1'b0), .u_att_port({`PW{1'b0}}), .att_ack(nc_ack),
        .probe_port(probe_port), .probe_m(probe_m), .probe_busy(probe_busy),
        .probe_fresh(probe_fresh),
        .reg_busy(reg_busy), .reg_ndig(reg_ndig), .reg_digits(reg_digits),
        .reg_port(nc_rport), .reg_gone(nc_gone), .reg_nodig(nc_nodig),
        .reg_brk(nc_brk),
        .caller_o(caller), .called_o(called), .state(mk_state), .q_ovf(nc_ovf));

    // Carried for a channel card on the block ribbon, not used by the exchange
    // logic: the captures run off SLOTQ and the detectors off TICK.
    wire _unused = &{1'b0, tick, hclk, tx_clk, clk_8k, rx_oct,
                     oct_stb, slot, nc_flood, nc_ack, nc_gone, nc_nodig, nc_brk,
                     nc_ovf, nc_rport, 1'b0};
endmodule

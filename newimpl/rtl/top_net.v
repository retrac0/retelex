// top_net -- THE MINIMAL EXCHANGE ON A NETWORK.  common-control.md 4.  NETWORK.
//
// top_min, with a network unit fitted beside the same mini marker.  "A flood
// never needs a smarter marker" (common-control.md 1): the mini marker plus a
// network unit is a pulse-flood exchange, dialled `1 e b h s` from anywhere
// and `h s` at home.  The class marker, the register pool and the card word's
// secondary are the maximal build's and are not here.
//
// A THIRD TOP, and deliberately: the rewrite's plan had two, with the unit
// only in top_max.  Joel chose, 2026-09-25, to bring the unit up beside the
// mini marker first.  top_min is not touched by it: the marker's network half
// is there too, tied to "no unit fitted", and takes exactly the path it took
// before it had one.  The regions only this top stuffs are tagged NETWORK.
//
// WHAT THE NETWORK ADDS IS CARDS, never a change to the fabric:
//   the network unit        beside the marker, on the same tap
//   trunk cards             in channel sockets, like any card: each says in its
//                           own word that it is a trunk and which way it faces
//   /NET                    one conductor, grounded by the unit
//   /UREQ                   one spare on the 16-way: the unit's claim on cable B
//
// CABLE B HAS TWO MASTERS HERE AND NO GRANT.  Each drives SDATA, SCLK and WR
// through its own '244, enabled only while it holds the bus; with neither
// enabled the blocks' pull-downs read all three low, which shifts and writes
// nothing (mainboard.md 6).  Two enabled at once is two '244s on one wire,
// and reads as x -- and `b_clash` says so, for every bench to count.
`timescale 1ns/1ps
`include "exch.vh"

module top_net #(
    parameter [63:0] PORT_FITTED  = 64'h0000_0000_0003_0600,  // 11, 12, 20, 21
    parameter [23:0] BLOCK_NUM    = 24'o76543210,
    parameter [7:0]  BLOCK_FITTED = 8'b0000_0110,             // blocks 1 and 2
    parameter [8:0]  T_ARM        = 9'd16,
    parameter [8:0]  T_REL        = 9'd256,
    parameter [12:0] RING_ON_MS   = 13'd2048,
    parameter [12:0] RING_OFF_MS  = 13'd4096,
    // the register's and the monitors' windows (register.md 2)
    parameter [8:0]  HIT          = 9'd8,
    parameter [8:0]  ID           = 9'd128,
    parameter [8:0]  CLR          = 9'd256,
    parameter [15:0] NODIG        = 16'd10000,
    // NETWORK: the unit's straps and stuffing
    parameter [2:0]  OWN_E        = 3'd2,
    parameter [2:0]  OWN_B        = 3'd2,
    parameter [3:0]  STRAP_N      = 4'b0000,
    parameter [1:0]  GUARD        = 2'd0,
    parameter integer NMON        = 2,
    parameter integer NRES        = 2,
    parameter [15:0] T_GUARD0     = 16'd128,
    parameter [15:0] T_KEY        = 16'd5000,
    parameter [15:0] T_CLAIM      = 16'd2000
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

    // ---- the clocks a card on a socket takes (common-cards.md 1.1) --------
    output            tx_clk,
    output            loop_hb,
    output            clk_8k,       // TX_OCT
    output            rx_oct,
    output            fill,

    // ---- what a bench, a lamp field or a debugger watches ------------------
    output            ha_n,
    output            hb_n,
    output            hw_n,
    output     [`SCANW-1:0] scan,
    output            frame_stb,
    output            tick_1k,
    output            ring_cad_n,
    output     [63:0] port_busy,
    output            b_sdata,      // cable B as it is on the wire
    output            b_sclk,
    output            b_wr,
    output            b_clash,      // both masters' '244s on at once.  Must never light

    output            reg_busy,
    output     [`PW-1:0] caller,
    output     [2:0]  mk_state,
    output            mk_ovf,
    output     [3:0]  dirs_held,
    output     [NRES-1:0] res_busy,
    output     [NMON-1:0] mon_held,
    output            claimed,
    output            hunting,
    output            un_ovf,
    output     [7:0]  n_glare,
    output     [7:0]  n_nofwd
);
    wire [2:0] slot, slotq, tick;
    wire [7:0] hc;
    wire hclk, line_hb, cap_stb, oct_stb, pass_stb;
    // the marker's tap, which nothing on this build watches
    wire [`PW-1:0] nc_pport, nc_called;
    wire           nc_pm, nc_pb, nc_pf;

    // ---- cable B, resolved as the board resolves it ------------------------
    wire m_sdata, m_sclk, m_wr, m_oe;
    wire u_sdata, u_sclk, u_wr, u_oe;
    assign b_clash = m_oe && u_oe;
    assign b_sdata = b_clash ? 1'bx : (m_oe ? m_sdata : (u_oe ? u_sdata : 1'b0));
    assign b_sclk  = b_clash ? 1'bx : (m_oe ? m_sclk  : (u_oe ? u_sclk  : 1'b0));
    assign b_wr    = b_clash ? 1'bx : (m_oe ? m_wr    : (u_oe ? u_wr    : 1'b0));

    exch #(.PORT_FITTED(PORT_FITTED), .BLOCK_NUM(BLOCK_NUM),
           .BLOCK_FITTED(BLOCK_FITTED), .T_ARM(T_ARM), .T_REL(T_REL),
           .RING_ON_MS(RING_ON_MS), .RING_OFF_MS(RING_OFF_MS)) u_exch (
        .clk(clk), .rst_n(rst_n),
        .c_tx(c_tx), .a_tx(a_tx), .ans_n(ans_n), .word_n(word_n),
        .c_rx(c_rx), .a_rx(a_rx),
        .mute_blk(mute_blk), .rbt_in(rbt_in),
        .sdata(b_sdata), .sclk(b_sclk), .wr(b_wr), .hw_n(hw_n),
        .hc(hc), .ha_n(ha_n), .hb_n(hb_n), .tick(tick),
        .slot(slot), .slotq(slotq),
        .hclk(hclk), .line_hb(line_hb), .cap_stb(cap_stb), .tx_clk(tx_clk),
        .frame_stb(frame_stb), .clk_8k(clk_8k), .rx_oct(rx_oct),
        .oct_stb(oct_stb),
        .scan(scan), .pass_stb(pass_stb),
        .fill(fill), .ring_cad_n(ring_cad_n), .tick_1k(tick_1k),
        .port_busy(port_busy));

    // LOOP_HB is made at the block, /SLOT[1] through one inverter
    // (common-cards.md 1.1, clocks.md 4); brought out for the cards.
    assign loop_hb = ~slot[1];

    // ---- NETWORK: the two ribbons between the marker and the unit ----------
    wire           net_n, ureq_n;
    wire           flood_go, u_restart, u_local, u_done, u_nogo, u_att, att_ack;
    wire [`PW-1:0] u_att_port;
    wire           r_gone, r_nodig, r_brk;
    wire [2:0]     r_ndig;
    wire [15:0]    r_digits;
    wire [`PW-1:0] r_port;

    mini_marker #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG)) u_mk (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
        .scan(scan), .ha_n(ha_n), .hb_n(hb_n), .tick_1k(tick_1k),
        .sdata(m_sdata), .sclk(m_sclk), .wr(m_wr), .b_oe(m_oe),
        .hw_n(hw_n), .ureq_n(ureq_n),
        .net_n(net_n), .flood_go(flood_go),
        .u_restart(u_restart), .u_local(u_local), .u_done(u_done), .u_nogo(u_nogo),
        .u_att(u_att), .u_att_port(u_att_port), .att_ack(att_ack),
        .probe_port(nc_pport), .probe_m(nc_pm), .probe_busy(nc_pb),
        .probe_fresh(nc_pf),
        .reg_busy(reg_busy), .reg_ndig(r_ndig), .reg_digits(r_digits),
        .reg_port(r_port), .reg_gone(r_gone), .reg_nodig(r_nodig), .reg_brk(r_brk),
        .caller_o(caller), .called_o(nc_called), .state(mk_state), .q_ovf(mk_ovf));

    net_unit #(.OWN_E(OWN_E), .OWN_B(OWN_B), .STRAP_N(STRAP_N), .GUARD(GUARD),
               .NMON(NMON), .NRES(NRES), .HIT(HIT), .ID(ID), .CLR(CLR),
               .T_GUARD0(T_GUARD0), .T_KEY(T_KEY), .T_CLAIM(T_CLAIM),
               .T_ARM(T_ARM)) u_net (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
        .scan(scan), .ha_n(ha_n), .hb_n(hb_n), .tick_1k(tick_1k),
        .sdata(u_sdata), .sclk(u_sclk), .wr(u_wr), .b_oe(u_oe), .hw_n(hw_n),
        .ureq_n(ureq_n),
        .net_n(net_n), .flood_go(flood_go), .restart(u_restart), .local_go(u_local),
        .done(u_done), .nogo(u_nogo), .att(u_att), .att_port(u_att_port),
        .att_ack(att_ack),
        .r_busy(reg_busy), .r_port(r_port), .r_ndig(r_ndig), .r_digits(r_digits),
        .r_brk(r_brk), .r_gone(r_gone), .r_nodig(r_nodig),
        .dirs_held(dirs_held), .res_busy(res_busy), .mon_held(mon_held),
        .claimed_o(claimed), .hunting(hunting), .q_ovf(un_ovf),
        .n_glare(n_glare), .n_nofwd(n_nofwd));

    // Carried for a channel card on the block ribbon, not used by the exchange
    // logic: the captures run off SLOTQ and the detectors off TICK.
    wire _unused = &{1'b0, hc, tick, hclk, line_hb, oct_stb, pass_stb, slot[2],
                     slot[0], nc_pport, nc_called, nc_pm, nc_pb, nc_pf, 1'b0};
endmodule

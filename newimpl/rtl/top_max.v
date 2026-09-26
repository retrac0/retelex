// top_max -- THE MAXIMAL EXCHANGE: the class marker.  marker.md §4;
// exchange/README.md §2; network.md §3.
//
// The exchange of top_net with the mini marker's card pulled and the class
// marker's plugged in.  The fabric does not change, and neither does the
// network unit: "a network unit plugs into either" marker (marker.md, the
// header), over the same two ribbons.
//
// THE REGISTER IS BESIDE THE MARKER, NOT INSIDE IT.  In the maximal build a
// register is a pool member on its own card (pulse_reg.v, the header), and
// register.md §3's ribbon is the wires below: the marker hands it a
// caller and takes back levels, and the unit taps the same levels for the
// flood.  One card is fitted.  A second wants a bank a register on the unit
// (README 6), and is not here.
//
// THE UNIT IS STUFFING.  UNIT_FITTED leaves its card out: /NET and /UREQ then
// read their pull-ups, every strobe of its ribbon is low, and the class
// marker takes key 1 as highway 1 -- the standalone exchange of
// exchange/README.md §2.  Nothing on the marker changes with it.
//
// The regions only a fitted unit stuffs are tagged NETWORK.
`timescale 1ns/1ps
`include "exch.vh"

module top_max #(
    parameter [63:0] PORT_FITTED  = 64'h0000_0000_0003_0600,  // 11, 12, 20, 21
    parameter [23:0] BLOCK_NUM    = 24'o76543210,
    parameter [7:0]  BLOCK_FITTED = 8'b0000_0110,             // blocks 1 and 2
    parameter [8:0]  T_ARM        = 9'd16,
    parameter [8:0]  T_REL        = 9'd256,
    parameter [12:0] RING_ON_MS   = 13'd2048,
    parameter [12:0] RING_OFF_MS  = 13'd4096,
    // the register's and the monitors' windows (register.md §1)
    parameter [8:0]  HIT          = 9'd8,
    parameter [8:0]  ID           = 9'd128,
    parameter [8:0]  CLR          = 9'd256,
    parameter [15:0] NODIG        = 16'd10000,
    // the marker's walk: passes between its reads.  A round is 63 x WALK ms,
    // the longest a caller waits for dial tone
    parameter [4:0]  WALK         = 5'd4,
    // NETWORK: the unit card, and its straps and stuffing
    parameter        UNIT_FITTED  = 1'b1,
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

    // ---- the clocks a card on a socket takes (common-cards.md §1.1) -------
    output            tx_clk,
    output            loop_hb,
    output            clk_8k,       // TX_OCT
    output            rx_oct,
    output            fill,
    output            hclk,

    // ---- what a bench, a lamp field or a debugger watches ------------------
    output            ha_n,
    output            hb_n,
    output            hw_n,
    output            ws_n,
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
    output     [`PW-1:0] called,
    output     [3:0]  mk_state,
    output            mk_pwait,     // marker.md §4.3: a P line is waiting
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
    wire cap_stb, oct_stb, pass_stb;

    // ---- cable B, resolved as the board resolves it ------------------------
    wire m_sdata, m_sclk, m_wr, m_oe;
    wire u_sdata, u_sclk, u_wr, u_oe;
    assign b_clash = m_oe && u_oe;
    assign b_sdata = b_clash ? 1'bx : (m_oe ? m_sdata : (u_oe ? u_sdata : 1'b0));
    assign b_sclk  = b_clash ? 1'bx : (m_oe ? m_sclk  : (u_oe ? u_sclk  : 1'b0));
    assign b_wr    = b_clash ? 1'bx : (m_oe ? m_wr    : (u_oe ? u_wr    : 1'b0));

    // ---- /WS: a 4.7 k pull-up at the clock card and the readers' drains -----
    wire m_ws_pd, u_ws_pd;
    assign ws_n = ~(m_ws_pd | u_ws_pd);

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

    // LOOP_HB is made at the block, /SLOT[1] through one inverter
    assign loop_hb = ~slot[1];

    // ---- the register's ribbon (register.md §3) ------------------------------
    wire           r_attach, r_release, r_restart;
    wire [`PW-1:0] r_attach_port, r_port;
    wire           r_gone, r_nodig, r_brk, r_counting, r_hook, r_settled;
    wire [2:0]     r_ndig;
    wire [15:0]    r_digits;

    // ---- NETWORK: the unit's ribbon ----------------------------------------------
    wire           net_n, ureq_n;
    wire           flood_go, u_restart, u_local, u_done, u_nogo, u_att, att_ack;
    wire [`PW-1:0] u_att_port;

    marker #(.WALK(WALK)) u_mk (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
        .scan(scan), .ha_n(ha_n), .hb_n(hb_n),
        .sdata(m_sdata), .sclk(m_sclk), .wr(m_wr), .b_oe(m_oe),
        .hw_n(hw_n), .ws_n(ws_n), .ws_pd(m_ws_pd), .ureq_n(ureq_n),
        .reg_attach(r_attach), .reg_port(r_attach_port), .reg_release(r_release),
        .reg_restart(r_restart),
        .r_busy(reg_busy), .r_ndig(r_ndig), .r_digits(r_digits),
        .r_gone(r_gone), .r_nodig(r_nodig), .r_settled(r_settled),
        .net_n(net_n), .flood_go(flood_go),
        .u_restart(u_restart), .u_local(u_local), .u_done(u_done), .u_nogo(u_nogo),
        .u_att(u_att), .u_att_port(u_att_port), .att_ack(att_ack),
        .caller_o(caller), .called_o(called), .state(mk_state), .pwait_o(mk_pwait),
        .q_ovf(mk_ovf));

    // One register card.  SETTLE, twice the ports' T_ARM: after a connect the
    // marker holds it until the called port's E detector has surely risen.
    pulse_reg #(.HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG),
                .SETTLE(T_ARM + T_ARM)) u_reg (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
        .scan(scan), .ha_n(ha_n), .hb_n(hb_n), .tick_1k(tick_1k),
        .attach(r_attach), .attach_port(r_attach_port),
        .release_it(r_release), .restart(r_restart),
        .busy(reg_busy), .port(r_port), .ndig(r_ndig), .digits(r_digits),
        .gone(r_gone), .nodig(r_nodig), .brk(r_brk), .counting(r_counting),
        .hook(r_hook), .settled(r_settled));

    generate if (UNIT_FITTED) begin : unit
        // ---- NETWORK: the unit card ----------------------------------------------
        net_unit #(.OWN_E(OWN_E), .OWN_B(OWN_B), .STRAP_N(STRAP_N), .GUARD(GUARD),
                   .NMON(NMON), .NRES(NRES), .HIT(HIT), .ID(ID), .CLR(CLR),
                   .T_GUARD0(T_GUARD0), .T_KEY(T_KEY), .T_CLAIM(T_CLAIM),
                   .T_ARM(T_ARM)) u_net (
            .clk(clk), .rst_n(rst_n),
            .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb),
            .scan(scan), .ha_n(ha_n), .hb_n(hb_n),
            .sdata(u_sdata), .sclk(u_sclk), .wr(u_wr), .b_oe(u_oe), .hw_n(hw_n),
            .ws_n(ws_n), .ws_pd(u_ws_pd), .ureq_n(ureq_n),
            .net_n(net_n), .flood_go(flood_go), .restart(u_restart), .local_go(u_local),
            .done(u_done), .nogo(u_nogo), .att(u_att), .att_port(u_att_port),
            .att_ack(att_ack),
            .r_busy(reg_busy), .r_port(r_port), .r_ndig(r_ndig), .r_digits(r_digits),
            .r_brk(r_brk), .r_gone(r_gone), .r_nodig(r_nodig),
            .dirs_held(dirs_held), .res_busy(res_busy), .mon_held(mon_held),
            .claimed_o(claimed), .hunting(hunting), .q_ovf(un_ovf),
            .n_glare(n_glare), .n_nofwd(n_nofwd));
    end else begin : no_unit
        // An empty position: the pull-ups, and a ribbon with nothing on it
        assign net_n = 1'b1;  assign ureq_n = 1'b1;
        assign u_sdata = 1'b0; assign u_sclk = 1'b0; assign u_wr = 1'b0;
        assign u_oe = 1'b0;   assign u_ws_pd = 1'b0;
        assign u_restart = 1'b0; assign u_local = 1'b0; assign u_done = 1'b0;
        assign u_nogo = 1'b0; assign u_att = 1'b0; assign u_att_port = {`PW{1'b0}};
        assign dirs_held = 4'd0; assign res_busy = {NRES{1'b0}};
        assign mon_held = {NMON{1'b0}}; assign claimed = 1'b0; assign hunting = 1'b0;
        assign un_ovf = 1'b0; assign n_glare = 8'd0; assign n_nofwd = 8'd0;
        wire _unused_ribbon = &{1'b0, flood_go, att_ack, r_brk, r_port, 1'b0};
    end endgenerate

    // Carried for a channel card on the block ribbon, not used by the exchange
    // logic: the captures run off SLOTQ and the detectors off TICK.  The
    // register's `counting` and `hook` are for a lamp field.
    wire _unused = &{1'b0, hc, tick, oct_stb, pass_stb, slot[2], slot[0],
                     r_counting, r_hook, 1'b0};
endmodule

// net_unit -- the network unit: the pulse flood.  network.md 3, 4;
// common-control.md 2.2-2.4, 4; monitor.md.  NETWORK.
//
// ONE CARD, AND EVERYTHING THE NETWORK NEEDS IS ON IT.  The fabric, the ports,
// the register, the marker and the release rule are the standalone
// exchange's, unchanged; this card is what a pulse-flood exchange adds
// (network.md 3.1).  It fits:
//
//   its own probe on SCAN -- it never borrows the marker's, which freezes on
//     a called port exactly when the marker is busiest
//   its own cable-B master -- queue and serialiser -- ranked above the
//     marker, with /UREQ to say so; and its own word reader, which names a
//     port on /WS in that port's bit-time and so needs no bus at all
//   a CLASSIFIER: a port showing M with BUSY clear is read off /HW.  A flood
//     trunk is an incoming seizure: hold it, give it a monitor, forward it.
//     Anything else is the marker's
//   the MONITORS (monitor.md), as a pool on this card, each cell its own
//     probe and its own pulse counter.  They claim; nothing else here does
//   the ORIGIN bank for the one register: seize a trunk every way, watch the
//     caller's digits go down them live, keep the one that claims
//   the FORWARDER and the RESOLVERS (network.md 3.2): a seizure is passed
//     into every other direction, and held until one of them claims
//   a HUNT: one sweep of all 64 ports that finds, for each direction asked
//     for, the free trunk facing that way -- the lowest-numbered, or the
//     highest where the trunk's word sets glare
//
// THE CARD SAYS WHAT IT IS.  This unit holds no jumper that says "port p is a
// trunk" or "p faces east".  Those are the trunk card's own, in its word
// (baseband_card.v; extensions.md 2.2), and read off /HW when needed.  What is
// strapped here is what is this exchange's: its code e b, the guard's tap, and
// the ring jumper, one a direction (network.md 3.3).
//
// ---- THE COST OF READING, AND WHY THE HUNT SWEEPS ----------------------------
// A read is a select on /WS in the port's own bit-time and the eight frames
// of /HW after it (word_rx.v): nine frames, and no cable B.  It can only
// START at its port's turn, so a hunt that took ports in number order would
// wait most of a pass between reads -- a millisecond a port.  So THE SWEEP
// VISITS PORTS ON A STRIDE OF 9: a read ends eight frames after its select,
// and the port nine on is the next one round.  9 is odd, so 64 steps visit
// every port once.  A sweep is 64 x 9 frames, 9 ms, whatever the exchange
// holds.
//
// EVERY PORT IS READ, free or not.  A port's M and BUSY are sampled in the
// same bit-time as its select, so the sweep cannot know a port is free until
// it has named it; it keeps that bit-time's M and BUSY with the word that
// follows, and a port that was not free is no candidate.  The sweep does not
// find ports in order, so it keeps the lowest (or, with glare, the highest)
// candidate a direction, and a final pass checks each candidate is still free
// before it is written (groups.md 2.2: take the port at the visit that finds
// it free).
//
// The sweep is most of every transit's hop, and the guard is what a hop is
// measured against.  With a pointing word on cable B a read was sixteen
// frames, a sweep 17 ms, and the 128 ms tap covered about six hops; at 9 ms
// it covers about ten, the documents' figure.  Joel accepted the 17 ms on
// 2026-09-25, and took the pointing word off the bus the same day.
//
// ---- WHAT THE MARKER SEES ------------------------------------------------------
//   /NET        grounded here: a unit is fitted
//   flood_go    in: key 1 consumed; the register holds the caller
//   restart     out: own e b -- begin the store again (ORed with the key's)
//   local       out: the call is local from here
//   done        out: caller <-> trunk is written; free the register
//   nogo        out: cannot-complete: no trunk, 8 or 9 in the code, the guard,
//               no claim 2 s after b, or b not in 5 s
//   att + port  out, a LEVEL held until att_ack: a claimed trunk wants the
//               register.  Raised only once the CLAIM word has gone out, so
//               the marker's refusal, if it must refuse, lands after it
//
// ---- WHAT IT DOES NOT DO ----------------------------------------------------
// One origin bank, because the mini marker has one register; a register pool
// wants one bank a register.  One forwarder: a seizure arriving while it is
// hunting is held and watched but not passed on.  No card-word secondary.
//
//   network.md 1.1, 3, 3.1-3.3, 4; monitor.md 2-4; common-control.md 2;
//   extensions.md 2.2; groups.md 2.2; baseband.md 3
`timescale 1ns/1ps
`include "exch.vh"

module net_unit #(
    // ---- straps: this exchange's own facts ------------------------------------
    parameter [2:0]   OWN_E   = 3'd2,      // the code's two digits, octal jumpers
    parameter [2:0]   OWN_B   = 3'd2,
    parameter [3:0]   STRAP_N = 4'b0000,   // the ring jumper, one a direction N S E W
    parameter [1:0]   GUARD   = 2'd0,      // the guard's tap: 128, 256 or 512 ms
    // ---- stuffing ----------------------------------------------------------------
    parameter integer NMON    = 2,         // monitor cells (monitor.md 4)
    parameter integer NRES    = 2,         // resolvers: forwards held at once
    // ---- the counter taps, in ms.  A bench scales them; the board has taps ----
    parameter [8:0]   HIT     = 9'd8,      // the monitors' windows (register.md 2)
    parameter [8:0]   ID      = 9'd128,
    parameter [8:0]   CLR     = 9'd256,
    parameter [15:0]  T_GUARD0 = 16'd128,  // the guard's first tap
    parameter [15:0]  T_KEY   = 16'd5000,  // b not in: network.md 4
    parameter [15:0]  T_CLAIM = 16'd2000,  // no claim after b: network.md 3
    // the ports' fM detector: M must stand this long before a port can ever
    // release itself (port.v).  A hold written on a seizure that dies sooner
    // has no edge to be cleared by, so this card clears it
    parameter [8:0]   T_ARM   = 9'd16,
    // master ticks /UREQ is held before this card drives: longer than the
    // marker's longest transaction.  Since reads left cable B that is one
    // written word -- 17 bit-times, 545 ticks, and two more to hand the '244
    // back.  It was a read, about 1030 ticks, when this was 1152
    parameter [11:0]  WAIT    = 12'd640
)(
    input                   clk,
    input                   rst_n,

    // ---- the bus: timing, scan and the planes ------------------------------
    input      [2:0]        slotq,
    input                   cap_stb,
    input                   frame_stb,
    input      [`SCANW-1:0] scan,
    input                   ha_n,
    input                   hb_n,

    // ---- the bus: the control lines, as the higher-ranked master -------------
    output                  sdata,
    output                  sclk,
    output                  wr,
    output                  b_oe,
    input                   hw_n,          // /HW, for the word reads
    input                   ws_n,          // /WS as received: anybody's select
    output                  ws_pd,         // this card's select, onto /WS
    output                  ureq_n,        // the unit's request line

    // ---- the marker's ribbon ----------------------------------------------------
    output                  net_n,         // grounded: this card is fitted
    input                   flood_go,
    output reg              restart,
    output reg              local_go,
    output reg              done,
    output reg              nogo,
    output reg              att,
    output reg [`PW-1:0]    att_port,
    input                   att_ack,

    // ---- the register's ribbon, tapped (common-control.md 2.1) ---------------
    input                   r_busy,
    input      [`PW-1:0]    r_port,        // the caller
    input      [2:0]        r_ndig,
    input      [15:0]       r_digits,
    input                   r_brk,         // one tick
    input                   r_gone,
    input                   r_nodig,

    // ---- for a bench -----------------------------------------------------------
    output     [3:0]        dirs_held,     // directions an origin call of ours holds
    output     [NRES-1:0]   res_busy,      // resolvers holding a forward
    output     [NMON-1:0]   mon_held,      // monitor cells counting
    output                  claimed_o,     // the origin call has its claim
    output                  hunting,       // a sweep is running
    output                  q_ovf,         // the queue refused a write.  Must never light
    output reg [7:0]        n_glare,       // glare seen by the origin, inside the guard
    output reg [7:0]        n_nofwd        // seizures held but not forwarded
);
    // TICK is SCAN5's fall, and the bus carries no line of its own for it: the
    // 1 ms time base is the pass boundary, one gate on SCAN and the frame edge
    wire tick_1k = frame_stb && (scan == {`SCANW{1'b0}});

    localparam [`PW-1:0] P00        = 6'o00;
    localparam [`PW-1:0] EV_GLARE   = 6'o04;   // counters.md: the event codes
    localparam [`PW-1:0] EV_NOTRUNK = 6'o10;
    localparam [`PW-1:0] STRIDE     = 6'd9;

    wire [15:0] t_guard = T_GUARD0 << GUARD;

    assign net_n = 1'b0;

    // A flood trunk says so in its primary octet: 11 01 0, then g, then dd.
    function is_trunk(input [4:0] w); is_trunk = (w == 5'b01011); endfunction

    // protocol.md 5 / network.md 2: e and b are 0-7, ten pulses is 0, and
    // 8, 9 and 11-15 are reserved.
    function [2:0] oct(input [3:0] c);  oct  = c[3] ? 3'd0 : c[2:0]; endfunction
    function       isvc(input [3:0] c); isvc = (c == 4'd8) || (c == 4'd9) || (c > 4'd10); endfunction

    function [2:0] popc(input [3:0] m); popc = {2'd0, m[0]} + {2'd0, m[1]} + {2'd0, m[2]} + {2'd0, m[3]}; endfunction

    function [14:0] ent(input [`PW-1:0] d, input [`PW-1:0] s, input b, input c);
        ent = {1'b1, c, b, s, d};
    endfunction
    function [14:0] evw(input [`PW-1:0] d, input [`PW-1:0] code);
        evw = {1'b0, 1'b1, 1'b0, code, d};           // G = 0: an event word
    endfunction

    // ======================================================================
    // THE PROBE -- this card's own, on SCAN
    // ======================================================================
    wire           sp_m, sp_busy, sp_fresh;
    wire [`PW-1:0] sp_port;
    probe u_sp (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .cap_stb(cap_stb),
        .frame_stb(frame_stb), .scan(scan), .ha_n(ha_n), .hb_n(hb_n),
        .port(scan), .m(sp_m), .busy(sp_busy), .port_q(sp_port), .fresh(sp_fresh));

    // ======================================================================
    // CABLE B -- five slots a tick: a CLAIM and four drops is the most
    // ======================================================================
    reg  [4:0]     push_v;
    reg  [74:0]    push_d;
    wire [4:0]     room;
    wire           q_empty, q_pending, q_sent;
    reg            granted;

    ctl_queue #(.DEPTH(16), .NP(5), .EV_ROOM(6)) u_q (
        .clk(clk), .rst_n(rst_n),
        .sdata(sdata), .sclk(sclk), .wr(wr), .oe(b_oe),
        .go(granted), .pending(q_pending), .empty(q_empty),
        .push_v(push_v), .push_d(push_d), .room(room), .ovf(q_ovf),
        .sent(q_sent));

    // ---- the request line.  No grant: hold /UREQ low longer than the marker's
    // longest transaction and the bus is this card's until it lets go.  It is
    // held only while this card has words to write.  A sweep needs no bus at
    // all: its reads are selects on /WS, and a marker's write passing between
    // them moves nothing on /HW.
    localparam [2:0] H_IDLE = 3'd0, H_SWEEP = 3'd1, H_CONFIRM = 3'd2;
    reg  [2:0]  hst;
    wire        want_bus = !q_empty;
    reg  [11:0] wcnt;
    assign ureq_n  = !want_bus;
    assign hunting = (hst != H_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin granted <= 1'b0; wcnt <= 12'd0; end
        else if (!want_bus) begin granted <= 1'b0; wcnt <= 12'd0; end
        else if (!granted) begin
            if (wcnt == WAIT - 12'd1) granted <= 1'b1;
            else                      wcnt    <= wcnt + 12'd1;
        end
    end

    // ======================================================================
    // THE WORD READER -- a select on /WS, and eight frames of /HW
    // ======================================================================
    // One read at a time; the classifier's before the sweep's.
    reg            rd_req;
    reg  [`PW-1:0] rd_port;
    wire           rd_done, rd_busy;
    wire [7:0]     rd_word;
    word_rx u_rd (
        .clk(clk), .rst_n(rst_n),
        .slotq(slotq), .cap_stb(cap_stb), .frame_stb(frame_stb), .scan(scan),
        .hw_n(hw_n), .ws_n(ws_n), .ws_pd(ws_pd),
        .rd_req(rd_req), .rd_port(rd_port), .busy(rd_busy), .done(rd_done),
        .word(rd_word));

    wire rd_free = !rd_busy && !rd_req;
    reg  rd_own;                                 // 0 the classifier, 1 the sweep

    // ======================================================================
    // THE CLASSIFIER
    // ======================================================================
    localparam [2:0] C_IDLE = 3'd0, C_READ = 3'd1, C_ACT = 3'd2, C_HOLD = 3'd3,
                     C_UNHOLD = 3'd4, C_WAIT = 3'd5;
    reg [2:0]      cst;
    reg [`PW-1:0]  cls_port;
    reg [1:0]      cls_dir;
    reg [8:0]      cls_ms;          // ms since the hold was written

    // DEALT WITH, AND M HAS STOOD SINCE: a bit a port.  Set when this card
    // takes the port for a read -- at once, or kept until the reader is free
    // -- or sees the port BUSY with M up; cleared when it sees M down.  A port
    // is taken only with its bit clear, so:
    //   a line left waiting for the register is read ONCE, not once a pass --
    //     two of them alternating every pass could hold the read path at the
    //     sweep's turn for as long as they waited, with /UREQ low throughout;
    //   a trunk whose BUSY falls while M still stands (the called party hung
    //     up first, and its port released under the far caller's M) is NOT a
    //     fresh seizure -- read as one, it was held and flooded onward;
    //   a rise the classifier was too busy to take is still clear, and is
    //     read at a later pass.
    // It is monitor.md 4's "low at the last visit", kept for every port.  On
    // the board a 64-stage delay line clocked at the frame edge -- eight '164
    // -- read at its head and written at its tail in each port's own turn.
    reg [63:0]     st;

    // M and BUSY clear: an incoming seizure or a caller, and only the card
    // knows which.  Port 00 is never fitted.  A port this card has seized for
    // its own call is neither, whatever its BUSY says yet (`mine`, below).
    reg  mine;
    wire cls_seen  = (cst == C_IDLE) && sp_fresh && sp_m && !sp_busy &&
                     !mine && (sp_port != P00) && !st[sp_port];

    // THE CLASSIFIER'S BEFORE THE SWEEP'S.  A sweep keeps the reader busy from
    // one select to the next, a select every nine frames, so a seizure seen
    // while it runs would find the reader busy at every sample and wait out
    // the whole sweep.  So it is KEPT (C_WAIT: its port in cls_port) and read
    // the moment the reader is free, ahead of the sweep's next step -- which
    // then waits a pass for its port to come round again.
    wire           cls_issue = rd_free && (cls_seen || (cst == C_WAIT));
    wire [`PW-1:0] cls_rport = (cst == C_WAIT) ? cls_port : sp_port;

    // ======================================================================
    // THE MONITORS
    // ======================================================================
    localparam [1:0] M_WANT_E = 2'd1, M_WANT_B = 2'd2, M_DONE = 2'd3;
    reg  [NMON-1:0]      m_held, m_armed, m_want;
    reg  [NMON*`PW-1:0]  m_port;
    reg  [NMON*2-1:0]    m_st;
    wire [NMON-1:0]      mp_m, mp_fresh, d_stb, d_clr;
    wire [NMON*`PW-1:0]  mp_port;
    wire [NMON*4-1:0]    d_cnt;

    genvar g;
    generate for (g = 0; g < NMON; g = g + 1) begin : mon
        wire mp_busy_u, cnt_u, brk_u, stdy_u;
        // one '688 and half a '74: this cell's own probe, tied to its trunk
        probe u_mp (
            .clk(clk), .rst_n(rst_n), .slotq(slotq), .cap_stb(cap_stb),
            .frame_stb(frame_stb), .scan(scan), .ha_n(ha_n), .hb_n(hb_n),
            .port(m_port[g*`PW +: `PW]), .m(mp_m[g]), .busy(mp_busy_u),
            .port_q(mp_port[g*`PW +: `PW]), .fresh(mp_fresh[g]));
        // register.md 2's three windows, on that M
        pulse_rx #(.HIT(HIT), .ID(ID), .CLR(CLR)) u_mrx (
            .clk(clk), .rst_n(rst_n), .tick_1k(tick_1k),
            .arm(m_armed[g]), .m(mp_m[g]),
            .cnt(d_cnt[g*4 +: 4]), .dig_stb(d_stb[g]), .clear(d_clr[g]),
            .counting(cnt_u), .brk_stb(brk_u), .steady(stdy_u));
        wire _unused_cell = &{1'b0, mp_busy_u, cnt_u, brk_u, stdy_u, 1'b0};
    end endgenerate

    assign mon_held = m_held;

    // the first free cell, and the first that wants to claim
    integer mk;
    reg              m_free_any, m_want_any;
    reg [NMON-1:0]   m_free1, m_want1;
    reg [`PW-1:0]    m_want_port;
    always @* begin
        m_free_any = 1'b0; m_want_any = 1'b0;
        m_free1 = {NMON{1'b0}}; m_want1 = {NMON{1'b0}}; m_want_port = P00;
        for (mk = 0; mk < NMON; mk = mk + 1) begin
            if (!m_held[mk] && !m_free_any) begin m_free_any = 1'b1; m_free1[mk] = 1'b1; end
            if (m_want[mk] && !m_want_any) begin
                m_want_any = 1'b1; m_want1[mk] = 1'b1; m_want_port = m_port[mk*`PW +: `PW];
            end
        end
    end

    // ======================================================================
    // THE RESOLVERS -- a forward held until a leg claims or the caller goes
    // ======================================================================
    localparam [1:0] R_NONE = 2'd0, R_LEG = 2'd1, R_GONE = 2'd2;
    reg  [NRES-1:0]      rs_busy, rs_two;
    reg  [NRES*`PW-1:0]  rs_in;
    reg  [NRES*4*`PW-1:0] rs_leg;
    reg  [NRES*4-1:0]    rs_held;
    reg  [NRES*2-1:0]    rs_act;
    reg  [NRES*2-1:0]    rs_cl;                // which leg claimed
    assign res_busy = rs_busy;

    reg              rs_free_any, rs_act_any;
    reg [NRES-1:0]   rs_free1, rs_act1;
    reg [NRES-1:0]   rs_mine;                  // resolvers holding the claimed port
    integer rv;
    always @* begin
        rs_free_any = 1'b0; rs_act_any = 1'b0;
        rs_free1 = {NRES{1'b0}}; rs_act1 = {NRES{1'b0}}; rs_mine = {NRES{1'b0}};
        for (rv = 0; rv < NRES; rv = rv + 1) begin
            if (!rs_busy[rv] && !rs_free_any) begin rs_free_any = 1'b1; rs_free1[rv] = 1'b1; end
            if (rs_busy[rv] && (rs_act[rv*2 +: 2] != R_NONE) && !rs_act_any) begin
                rs_act_any = 1'b1; rs_act1[rv] = 1'b1;
            end
            if (rs_busy[rv] && (rs_in[rv*`PW +: `PW] == m_want_port)) rs_mine[rv] = 1'b1;
        end
    end

    // ======================================================================
    // THE FORWARDER
    // ======================================================================
    localparam [1:0] F_IDLE = 2'd0, F_WANT = 2'd1, F_HUNT = 2'd2, F_WRITE = 2'd3;
    reg [1:0]       fst;
    reg             f_cancel;      // the seizure it is sweeping for died
    reg [`PW-1:0]   f_in;
    reg [3:0]       f_mask;
    reg [3:0]       f_ok;
    reg [4*`PW-1:0] f_cand;

    // ======================================================================
    // THE ORIGIN BANK
    // ======================================================================
    localparam [3:0] N_IDLE = 4'd0, N_WANT = 4'd1, N_HUNT = 4'd2, N_SEIZE = 4'd3,
                     N_NET = 4'd4, N_WAITCL = 4'd5, N_DONE = 4'd6, N_DROP = 4'd7,
                     N_END = 4'd8;
    localparam [1:0] O_NONE = 2'd0, O_NOGO = 2'd1, O_LOCAL = 2'd2;
    reg [3:0]       nst;
    reg [1:0]       o_after;
    reg [`PW-1:0]   caller;
    reg [3:0]       d_held, dmo;
    reg [4*`PW-1:0] d_trunk;
    // THE SWEEP'S ANSWER IS COPIED THE TICK IT IS GIVEN.  The sweep is shared,
    // and a forward waiting for it starts on that same tick and clears it --
    // read later, the origin would seize nothing (the forwarder copies too).
    reg [3:0]       o_ok;
    reg [4*`PW-1:0] o_cand;
    reg [`PW-1:0]   trunk;
    reg             claimed, f1, f2;
    reg [15:0]      tmr;
    reg             ev_glare, ev_notrunk;
    assign dirs_held = d_held;
    assign claimed_o = claimed;

    wire [3:0] dg0 = r_digits[3:0];
    wire [3:0] dg1 = r_digits[7:4];
    wire [3:0] dg2 = r_digits[11:8];
    // the number is in: h s, or a one-key number after the code -- 0, or 9
    // (network.md 3: "h s, or 0, or 9") -- which the far end answers at once
    wire       o_last = (r_ndig >= 3'd4) || ((r_ndig == 3'd3) && (oct(dg2) == 3'd0));
    wire       guarding = !f2 && (tmr < t_guard);
    wire       o_net   = (nst == N_NET) || (nst == N_WAITCL);
    wire       o_gone  = r_gone || r_nodig || !r_busy;

    // MINE: the port on the probe is one this card has seized -- an origin
    // trunk or a forward's leg, from the sweep's answer until it is let go.
    // Its own seizure makes the port BUSY only once the word is out and the
    // port's turn comes round, a pass or two, and a far end seizing the same
    // channel inside that window shows M with BUSY clear.  That is glare: the
    // far M is the origin's claim, or the resolver's (network.md 1, "residual
    // glare joins two callers"), and the classifier must not ALSO hold the
    // port as an incoming seizure -- listening to 00 over this card's own
    // write -- and give it a monitor.  The origin and the resolvers already
    // compare the probe's port with every trunk and leg they hold (the claim
    // watches below); this ORs them, with the sweep's answer until it is
    // written.  tb_lfull 5 found it: one caller heard the other, and the
    // other heard cannot-complete.
    integer mn, mr;
    always @* begin
        mine = 1'b0;
        for (mn = 0; mn < 4; mn = mn + 1) begin
            if ((nst == N_SEIZE) && o_ok[mn] && (sp_port == o_cand[mn*`PW +: `PW])) mine = 1'b1;
            if (d_held[mn] && (sp_port == d_trunk[mn*`PW +: `PW]))                  mine = 1'b1;
            if ((fst == F_WRITE) && f_ok[mn] && (sp_port == f_cand[mn*`PW +: `PW])) mine = 1'b1;
            for (mr = 0; mr < NRES; mr = mr + 1)
                if (rs_held[mr*4 + mn] && (sp_port == rs_leg[(mr*4 + mn)*`PW +: `PW])) mine = 1'b1;
        end
    end

    // ======================================================================
    // THE SWEEP
    // ======================================================================
    reg             h_owner;                   // 0 the origin, 1 the forwarder
    reg [3:0]       h_mask, h_ok, h_g;
    reg [4*`PW-1:0] h_cand;
    reg [`PW-1:0]   h_idx;
    reg [6:0]       h_n;
    reg             h_reading;
    reg             h_m, h_b;                  // h_idx's M and BUSY at its select
    reg             h_done;
    // Asked for the moment the last read is in, while h_idx's turn is still to
    // come; the reader selects at that turn.  That is the whole of the stride.
    wire            h_issue = (hst == H_SWEEP) && !h_reading && (h_idx != P00) &&
                              rd_free && !cls_issue;

    // ======================================================================
    // THE CLAIM HANDLER
    // ======================================================================
    localparam [1:0] CL_IDLE = 2'd0, CL_WAIT = 2'd1, CL_ACK = 2'd2;
    reg [1:0]  cl_st;

    // ======================================================================
    // WHO WRITES THIS TICK.  One pusher a tick, in this order, and only if
    // the queue has room for all it has to say; the others wait -- every one
    // of them is waiting on a level, not a strobe.
    // ======================================================================
    reg [2:0] cnt_claim, cnt_orig, cnt_fwd, cnt_res;
    reg       w_claim, w_cls, w_orig, w_fwd, w_res, w_ev;
    integer   wu;
    always @* begin
        // the claim: CLAIM, and every leg of a forward of the same trunk
        cnt_claim = 3'd1;
        for (wu = 0; wu < NRES; wu = wu + 1)
            if (rs_mine[wu]) cnt_claim = cnt_claim + popc(rs_held[wu*4 +: 4]);
        // the origin
        case (nst)
        N_SEIZE: cnt_orig = popc(o_ok);
        N_DONE:  cnt_orig = 3'd1;
        N_DROP:  cnt_orig = popc(d_held);
        default: cnt_orig = popc(dmo);
        endcase
        // the forwarder: a leg a direction, and the way back if there is one
        cnt_fwd = popc(f_ok) + ((popc(f_ok) == 3'd1) ? 3'd1 : 3'd0);
        // a resolver acting: at most the way back and three drops
        cnt_res = 3'd4;

        w_claim = (m_want_any && (cl_st == CL_IDLE)) && (room >= {2'd0, cnt_claim});
        w_cls   = !w_claim && ((cst == C_ACT) || (cst == C_UNHOLD)) && (room >= 5'd1);
        w_orig  = !w_claim && !w_cls &&
                  ((nst == N_SEIZE) || (nst == N_DONE) || (nst == N_DROP) ||
                   (o_net && (dmo != 4'd0))) && (room >= {2'd0, cnt_orig});
        w_fwd   = !w_claim && !w_cls && !w_orig && (fst == F_WRITE) &&
                  rs_free_any && (room >= {2'd0, cnt_fwd});
        w_res   = !w_claim && !w_cls && !w_orig && !w_fwd && rs_act_any &&
                  (room >= {2'd0, cnt_res});
        w_ev    = !w_claim && !w_cls && !w_orig && !w_fwd && !w_res &&
                  (ev_glare || ev_notrunk);
    end

    // ======================================================================
    // ONE CLOCKED BLOCK: every register on the card
    // ======================================================================
    // "held but not passed on": a seizure the forwarder could not take, and a
    // forward that found no trunk.  They can fall on one tick, so they sum.
    wire [3:0] fwd_mask = ~STRAP_N & ~(4'd1 << cls_dir);
    wire nf_busy  = w_cls && (cst == C_ACT) && !STRAP_N[cls_dir] && (fwd_mask != 4'd0) &&
                    !((fst == F_IDLE) && rs_free_any);
    wire nf_empty = (fst == F_HUNT) && h_done && h_owner && !f_cancel && (h_ok == 4'd0);

    integer i, j2, u, v;
    // the sweep's current best for the direction a word just read faces
    wire [1:0]     rdir  = rd_word[7:6];
    wire [4:0]     sbase = {1'b0, rdir, 2'b00} + {2'b00, rdir, 1'b0};    // 6 x rdir
    wire [`PW-1:0] sidx  = h_cand[sbase +: `PW];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            push_v <= 5'd0; push_d <= 75'd0;
            rd_req <= 1'b0; rd_port <= P00; rd_own <= 1'b0;
            restart <= 1'b0; local_go <= 1'b0; done <= 1'b0; nogo <= 1'b0;
            att <= 1'b0; att_port <= P00; cl_st <= CL_IDLE;
            cst <= C_IDLE; cls_port <= P00; cls_dir <= 2'd0; cls_ms <= 9'd0;
            st <= 64'd0; f_cancel <= 1'b0; o_ok <= 4'd0; o_cand <= {4*`PW{1'b0}};
            m_held <= {NMON{1'b0}}; m_armed <= {NMON{1'b0}}; m_want <= {NMON{1'b0}};
            m_port <= {NMON*`PW{1'b0}}; m_st <= {NMON*2{1'b0}};
            rs_busy <= {NRES{1'b0}}; rs_two <= {NRES{1'b0}};
            rs_in <= {NRES*`PW{1'b0}}; rs_leg <= {NRES*4*`PW{1'b0}};
            rs_held <= {NRES*4{1'b0}}; rs_act <= {NRES*2{1'b0}}; rs_cl <= {NRES*2{1'b0}};
            fst <= F_IDLE; f_in <= P00; f_mask <= 4'd0; f_ok <= 4'd0; f_cand <= {4*`PW{1'b0}};
            nst <= N_IDLE; o_after <= O_NONE; caller <= P00;
            d_held <= 4'd0; dmo <= 4'd0; d_trunk <= {4*`PW{1'b0}}; trunk <= P00;
            claimed <= 1'b0; f1 <= 1'b0; f2 <= 1'b0; tmr <= 16'd0;
            ev_glare <= 1'b0; ev_notrunk <= 1'b0;
            hst <= H_IDLE; h_owner <= 1'b0; h_mask <= 4'd0; h_ok <= 4'd0; h_g <= 4'd0;
            h_cand <= {4*`PW{1'b0}}; h_idx <= P00; h_n <= 7'd0; h_reading <= 1'b0;
            h_m <= 1'b0; h_b <= 1'b0;
            h_done <= 1'b0; n_glare <= 8'd0; n_nofwd <= 8'd0;
        end else begin
            push_v   <= 5'd0;
            rd_req   <= 1'b0;
            restart  <= 1'b0;
            local_go <= 1'b0;
            done     <= 1'b0;
            nogo     <= 1'b0;
            h_done   <= 1'b0;
            n_nofwd  <= n_nofwd + {7'd0, nf_busy} + {7'd0, nf_empty};

            // ==================================================================
            // the reads: issue, and route the answer
            // ==================================================================
            if (cls_issue) begin
                rd_req <= 1'b1; rd_port <= cls_rport; rd_own <= 1'b0;
                cls_port <= cls_rport; cst <= C_READ;
            end else if (cls_seen) begin
                // the reader is the sweep's just now: keep the seizure
                cls_port <= sp_port; cst <= C_WAIT;
            end else if (h_issue) begin
                rd_req <= 1'b1; rd_port <= h_idx; rd_own <= 1'b1;
                h_reading <= 1'b1;
            end

            // ==================================================================
            // the classifier
            // ==================================================================
            // the bit a port: cleared by M down, set by M up under BUSY, and
            // set by the read below.  A read's set is the later assignment.
            if (sp_fresh) begin
                if (!sp_m)        st[sp_port] <= 1'b0;
                else if (sp_busy) st[sp_port] <= 1'b1;
            end
            if (cls_seen) st[sp_port] <= 1'b1;

            if (cst == C_READ && rd_done && !rd_own) begin
                if (is_trunk(rd_word[4:0])) begin cls_dir <= rd_word[7:6]; cst <= C_ACT; end
                else cst <= C_IDLE;
            end

            // WATCH THE HOLD THROUGH THE PORT'S ARMING TIME.  The port clears
            // its own latch only on a FALL of its M or E detector, and its M
            // detector rises only after M has stood T_ARM.  A seizure that dies
            // sooner -- the far origin's guard abandoning, glare, a bounce --
            // leaves a hold with no edge to clear it, and the trunk BUSY for
            // good.  So for T_ARM this card watches, and if M falls it writes
            // the hold away itself, and calls off the forward.
            if (cst == C_HOLD) begin
                if (tick_1k) cls_ms <= cls_ms + 9'd1;
                if (sp_fresh && (sp_port == cls_port) && !sp_m) cst <= C_UNHOLD;
                else if (cls_ms > T_ARM + 9'd1)                   cst <= C_IDLE;
            end

            if (w_cls && (cst == C_UNHOLD)) begin
                push_v <= 5'b00001;
                push_d <= {60'd0, ent(cls_port, P00, 1'b0, 1'b0)};
                if ((fst != F_IDLE) && (f_in == cls_port)) f_cancel <= 1'b1;
                cst <= C_IDLE;
            end else if (w_cls) begin
                // ---- an incoming seizure ----------------------------------
                // HOLD IT: listening to 00, BUSY, so the marker never takes
                // its M and nothing hunts it.  Then a monitor, if one is free
                // -- "none free: the seizure goes unwatched here, for good"
                // (monitor.md 4) -- and a forward, unless the link it came in
                // on is jumpered: never forwarded ONWARD from a strapped link
                // (network.md 3.3).
                //
                // THE MONITOR SEES THE RISE.  It is attached at the read that
                // found the trunk, a millisecond or two after the rise, and
                // the first break cannot come sooner than the guard allows:
                // the origin abandons any that does.  That is rule 1 on this
                // card (monitor.md 3): nothing has gone by.
                push_v <= 5'b00001;
                push_d <= {60'd0, ent(cls_port, P00, 1'b1, 1'b0)};
                cst    <= C_HOLD; cls_ms <= 9'd0;
                for (i = 0; i < NMON; i = i + 1) if (m_free1[i]) begin
                    m_held[i] <= 1'b1; m_armed[i] <= 1'b0; m_want[i] <= 1'b0;
                    m_port[i*`PW +: `PW] <= cls_port; m_st[i*2 +: 2] <= M_WANT_E;
                end
                if (!STRAP_N[cls_dir] && (fst == F_IDLE) && rs_free_any &&
                    ((~STRAP_N & ~(4'd1 << cls_dir)) != 4'd0)) begin
                    f_in <= cls_port; f_mask <= ~STRAP_N & ~(4'd1 << cls_dir);
                    f_cancel <= 1'b0;
                    fst  <= F_WANT;
                end
            end

            // ==================================================================
            // the monitors
            // ==================================================================
            for (i = 0; i < NMON; i = i + 1) begin
                // arm the counter once the cell's probe has the new port:
                // until then its M is the last port's, and a stale 0 is a break
                if (m_held[i] && !m_armed[i] && mp_fresh[i] &&
                    (mp_port[i*`PW +: `PW] == m_port[i*`PW +: `PW]))
                    m_armed[i] <= 1'b1;
                if (m_held[i] && d_stb[i]) begin
                    case (m_st[i*2 +: 2])
                    M_WANT_E: if (isvc(d_cnt[i*4 +: 4]) || oct(d_cnt[i*4 +: 4]) != OWN_E) begin
                                  m_held[i] <= 1'b0; m_armed[i] <= 1'b0;
                              end else m_st[i*2 +: 2] <= M_WANT_B;
                    M_WANT_B: if (isvc(d_cnt[i*4 +: 4]) || oct(d_cnt[i*4 +: 4]) != OWN_B) begin
                                  m_held[i] <= 1'b0; m_armed[i] <= 1'b0;
                              end else begin
                                  m_want[i] <= 1'b1; m_st[i*2 +: 2] <= M_DONE;  // two digits and no more
                              end
                    default: ;
                    endcase
                end
                // the trunk released: 256 ms of break
                if (m_held[i] && d_clr[i]) begin
                    m_held[i] <= 1'b0; m_armed[i] <= 1'b0; m_want[i] <= 1'b0;
                end
            end

            // ==================================================================
            // the claim: CLAIM on the trunk, the forward's legs dropped, then
            // -- once the word is out -- ask the marker for the register
            // ==================================================================
            if (w_claim) begin
                push_v <= 5'b00001;
                push_d <= {60'd0, ent(m_want_port, P00, 1'b1, 1'b1)};
                for (u = 0; u < NRES; u = u + 1) if (rs_mine[u]) begin
                    for (j2 = 0; j2 < 4; j2 = j2 + 1) if (rs_held[u*4 + j2]) begin
                        push_v[j2 + 1] <= 1'b1;
                        push_d[(j2 + 1)*15 +: 15] <= ent(rs_leg[(u*4 + j2)*`PW +: `PW], P00, 1'b0, 1'b0);
                    end
                    rs_busy[u] <= 1'b0; rs_held[u*4 +: 4] <= 4'd0; rs_act[u*2 +: 2] <= R_NONE;
                end
                for (i = 0; i < NMON; i = i + 1) if (m_want1[i]) begin
                    m_want[i] <= 1'b0; m_held[i] <= 1'b0; m_armed[i] <= 1'b0;
                end
                att_port <= m_want_port;
                cl_st    <= CL_WAIT;
            end
            case (cl_st)
            CL_WAIT: if (q_empty && !w_claim) begin att <= 1'b1; cl_st <= CL_ACK; end
            CL_ACK:  if (att_ack) begin att <= 1'b0; cl_st <= CL_IDLE; end
            default: ;
            endcase

            // ==================================================================
            // the resolvers: watch every leg and the caller, once a pass
            // ==================================================================
            for (v = 0; v < NRES; v = v + 1)
                if (rs_busy[v] && sp_fresh && (rs_act[v*2 +: 2] == R_NONE)) begin
                    for (j2 = 0; j2 < 4; j2 = j2 + 1)
                        if (rs_held[v*4 + j2] && sp_m &&
                            (sp_port == rs_leg[(v*4 + j2)*`PW +: `PW])) begin
                            rs_act[v*2 +: 2] <= R_LEG; rs_cl[v*2 +: 2] <= j2[1:0];
                        end
                    if ((sp_port == rs_in[v*`PW +: `PW]) && !sp_busy)
                        rs_act[v*2 +: 2] <= R_GONE;
                end
            if (w_res) begin
                for (v = 0; v < NRES; v = v + 1) if (rs_act1[v]) begin
                    for (j2 = 0; j2 < 4; j2 = j2 + 1)
                        if (rs_held[v*4 + j2] &&
                            ((rs_act[v*2 +: 2] == R_GONE) || (rs_cl[v*2 +: 2] != j2[1:0]))) begin
                            push_v[j2] <= 1'b1;
                            push_d[j2*15 +: 15] <= ent(rs_leg[(v*4 + j2)*`PW +: `PW], P00, 1'b0, 1'b0);
                        end
                    // a leg claimed: the caller listens to it -- unless the
                    // forward was one leg and already both ways
                    if ((rs_act[v*2 +: 2] == R_LEG) && !rs_two[v]) begin
                        push_v[4] <= 1'b1;
                        push_d[4*15 +: 15] <= ent(rs_in[v*`PW +: `PW],
                                                  rs_leg[(v*4 + {30'd0, rs_cl[v*2 +: 2]})*`PW +: `PW], 1'b1, 1'b0);
                    end
                    rs_busy[v] <= 1'b0; rs_held[v*4 +: 4] <= 4'd0; rs_act[v*2 +: 2] <= R_NONE;
                end
            end

            // ==================================================================
            // the forwarder
            // ==================================================================
            case (fst)
            F_WANT: if (f_cancel) fst <= F_IDLE;
                    else if ((hst == H_IDLE) && (nst != N_WANT)) begin
                hst <= H_SWEEP; h_owner <= 1'b1; h_mask <= f_mask;
                h_ok <= 4'd0; h_g <= 4'd0; h_idx <= 6'd1; h_n <= 7'd0; h_reading <= 1'b0;
                fst <= F_HUNT;
            end
            F_HUNT: if (h_done && h_owner) begin
                f_ok <= h_ok; f_cand <= h_cand;
                if (f_cancel || (h_ok == 4'd0)) fst <= F_IDLE;
                else                            fst <= F_WRITE;
            end
            F_WRITE: if (w_fwd) begin
                for (j2 = 0; j2 < 4; j2 = j2 + 1) if (f_ok[j2]) begin
                    push_v[j2] <= 1'b1;
                    push_d[j2*15 +: 15] <= ent(f_cand[j2*`PW +: `PW], f_in, 1'b1, 1'b0);
                end
                // one leg: patch it both ways now and forget the way back
                // (network.md 3: "one found: patch it, two latches")
                if (popc(f_ok) == 3'd1)
                    for (j2 = 0; j2 < 4; j2 = j2 + 1) if (f_ok[j2]) begin
                        push_v[4] <= 1'b1;
                        push_d[4*15 +: 15] <= ent(f_in, f_cand[j2*`PW +: `PW], 1'b1, 1'b0);
                    end
                for (v = 0; v < NRES; v = v + 1) if (rs_free1[v]) begin
                    rs_busy[v] <= 1'b1; rs_two[v] <= (popc(f_ok) == 3'd1);
                    rs_in[v*`PW +: `PW] <= f_in; rs_leg[v*4*`PW +: 4*`PW] <= f_cand;
                    rs_held[v*4 +: 4] <= f_ok; rs_act[v*2 +: 2] <= R_NONE;
                end
                fst <= F_IDLE;
            end
            default: ;
            endcase

            // ==================================================================
            // the sweep
            // ==================================================================
            case (hst)
            H_SWEEP: begin
                if (h_reading) begin
                    // The port's M and BUSY come off this card's probe at the
                    // end of the select's bit-time -- the last sample of that
                    // port before its word is in -- and are kept with it.
                    if (sp_fresh && (sp_port == h_idx)) begin h_m <= sp_m; h_b <= sp_busy; end
                    if (rd_done && rd_own) begin
                        // the card says what it is; free at its select, or no candidate
                        if (!h_m && !h_b && is_trunk(rd_word[4:0]) && h_mask[rdir]) begin
                            if (!h_ok[rdir] ||
                                ( rd_word[5] && (h_idx > sidx)) ||
                                (!rd_word[5] && (h_idx < sidx))) begin
                                h_ok[rdir] <= 1'b1;
                                h_g [rdir] <= rd_word[5];
                                h_cand[sbase +: `PW] <= h_idx;
                            end
                        end
                        h_reading <= 1'b0;
                        h_idx <= h_idx + STRIDE; h_n <= h_n + 7'd1;
                        if (h_n == 7'd63) begin hst <= H_CONFIRM; h_n <= 7'd0; end
                    end
                end else if (sp_fresh && (sp_port == P00) && (h_idx == P00)) begin
                    // 00 is never fitted: its step, at its turn, costs no read
                    h_idx <= h_idx + STRIDE; h_n <= h_n + 7'd1;
                    if (h_n == 7'd63) begin hst <= H_CONFIRM; h_n <= 7'd0; end
                end
            end
            // one more pass: is each candidate still free at its own turn?
            H_CONFIRM: if (sp_fresh) begin
                for (j2 = 0; j2 < 4; j2 = j2 + 1)
                    if (h_ok[j2] && (sp_port == h_cand[j2*`PW +: `PW]) && (sp_m || sp_busy))
                        h_ok[j2] <= 1'b0;
                h_n <= h_n + 7'd1;
                if (h_n == 7'd63) begin hst <= H_IDLE; h_done <= 1'b1; end
            end
            default: ;
            endcase

            // ==================================================================
            // the origin
            // ==================================================================
            if (o_net && tick_1k && (tmr != 16'hFFFF)) tmr <= tmr + 16'd1;

            // a claim comes back: M rising on a trunk this call holds
            if (o_net && sp_fresh && sp_m && !claimed)
                for (j2 = 0; j2 < 4; j2 = j2 + 1)
                    if (d_held[j2] && (sp_port == d_trunk[j2*`PW +: `PW])) begin
                        claimed <= 1'b1; trunk <= sp_port;
                        // release the others AT THE CLAIM (network.md 3)
                        dmo <= d_held & ~(4'd1 << j2);
                        // inside the guard it was the far end seizing the same
                        // channel: glare, taken as the claim, and counted
                        if (guarding) begin ev_glare <= 1'b1; n_glare <= n_glare + 8'd1; end
                    end

            if (w_orig) begin
                case (nst)
                N_SEIZE: begin
                    // one trunk every way, each listening to the CALLER, so
                    // the rest of the dial goes down them live
                    for (j2 = 0; j2 < 4; j2 = j2 + 1) if (o_ok[j2]) begin
                        push_v[j2] <= 1'b1;
                        push_d[j2*15 +: 15] <= ent(o_cand[j2*`PW +: `PW], caller, 1'b1, 1'b0);
                    end
                    d_held <= o_ok; d_trunk <= o_cand; tmr <= 16'd0;
                    nst <= N_NET;
                end
                N_DONE: begin
                    push_v <= 5'b00001;
                    push_d <= {60'd0, ent(caller, trunk, 1'b1, 1'b0)};
                    done <= 1'b1; nst <= N_IDLE; d_held <= 4'd0;
                end
                N_DROP: begin
                    for (j2 = 0; j2 < 4; j2 = j2 + 1) if (d_held[j2]) begin
                        push_v[j2] <= 1'b1;
                        push_d[j2*15 +: 15] <= ent(d_trunk[j2*`PW +: `PW], P00, 1'b0, 1'b0);
                    end
                    d_held <= 4'd0; dmo <= 4'd0;
                    nst <= N_END;
                end
                default: begin                    // the others, at the claim
                    for (j2 = 0; j2 < 4; j2 = j2 + 1) if (dmo[j2]) begin
                        push_v[j2] <= 1'b1;
                        push_d[j2*15 +: 15] <= ent(d_trunk[j2*`PW +: `PW], P00, 1'b0, 1'b0);
                    end
                    d_held <= d_held & ~dmo; dmo <= 4'd0;
                end
                endcase
            end

            case (nst)
            N_IDLE: if (flood_go) begin
                caller <= r_port; claimed <= 1'b0; f1 <= 1'b0; f2 <= 1'b0;
                d_held <= 4'd0; dmo <= 4'd0; o_after <= O_NONE; tmr <= 16'd0;
                nst <= N_WANT;
            end
            N_WANT: if (o_gone) begin o_after <= O_NONE; nst <= N_END; end
                    else if (hst == H_IDLE) begin
                hst <= H_SWEEP; h_owner <= 1'b0; h_mask <= 4'b1111;
                h_ok <= 4'd0; h_g <= 4'd0; h_idx <= 6'd1; h_n <= 7'd0; h_reading <= 1'b0;
                nst <= N_HUNT;
            end
            N_HUNT: if (h_done && !h_owner) begin
                if (o_gone)             begin o_after <= O_NONE; nst <= N_END; end
                else if (h_ok == 4'd0)  begin ev_notrunk <= 1'b1; o_after <= O_NOGO; nst <= N_END; end
                else begin o_ok <= h_ok; o_cand <= h_cand; nst <= N_SEIZE; end
            end
            N_NET, N_WAITCL: begin
                if (o_gone) begin o_after <= O_NONE; nst <= N_DROP; end
                // the origin's guard: a break inside it and the far end may
                // have lost a pulse -- abandon, never a wrong number
                else if (guarding && r_brk) begin o_after <= O_NOGO; nst <= N_DROP; end
                else if (nst == N_NET) begin
                    if (!f1 && (r_ndig >= 3'd1)) begin
                        if (isvc(dg0)) begin o_after <= O_NOGO; nst <= N_DROP; end
                        else f1 <= 1'b1;
                    end else if (f1 && !f2 && (r_ndig >= 3'd2)) begin
                        if (isvc(dg1)) begin o_after <= O_NOGO; nst <= N_DROP; end
                        else if ((oct(dg0) == OWN_E) && (oct(dg1) == OWN_B)) begin
                            // our own code: the call is local after all
                            o_after <= O_LOCAL; nst <= N_DROP;
                        end else begin
                            // b is in: the 2 s claim wait starts now
                            f2 <= 1'b1; tmr <= 16'd0; nst <= N_WAITCL;
                        end
                    end else if (!f2 && (tmr >= T_KEY)) begin
                        // network.md 4: b not in 5 s after the key
                        o_after <= O_NOGO; nst <= N_DROP;
                    end
                end else begin
                    if (claimed && o_last && (dmo == 4'd0)) nst <= N_DONE;
                    else if (!claimed && (tmr >= T_CLAIM)) begin o_after <= O_NOGO; nst <= N_DROP; end
                end
            end
            N_END: begin
                case (o_after)
                O_NOGO:  nogo <= 1'b1;
                O_LOCAL: begin restart <= 1'b1; local_go <= 1'b1; end
                default: ;
                endcase
                nst <= N_IDLE;
            end
            default: ;
            endcase

            // ==================================================================
            // the events, when nothing else is being written
            // ==================================================================
            if (w_ev) begin
                push_v <= 5'b00001;
                if (ev_glare) begin
                    push_d <= {60'd0, evw(trunk, EV_GLARE)}; ev_glare <= 1'b0;
                end else begin
                    push_d <= {60'd0, evw(P00, EV_NOTRUNK)}; ev_notrunk <= 1'b0;
                end
            end
        end
    end

    // the store's last two digits are the far register's business, h s
    wire _unused = &{1'b0, q_pending, q_sent, h_g, r_digits[15:8], 1'b0};
endmodule

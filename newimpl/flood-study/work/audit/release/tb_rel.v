// tb_rel -- AUDIT (release / stuck-state slice).  A HANG-UP SWEEP across a
// network call, three exchanges, many trials in one simulation.
//
//     A 2 2  ==11,12==  11,12  X 3 3  13,15  ==11,12==  B 1 1
//            faces E          faces W  faces E           faces W
//                                      30 faces S: a STUB link -- its far end
//                                      is a bench wire that never answers
//
// X is a transit with two onward directions when the stub link is up, so a
// seizure from A fans out (two legs, a resolver, the way back written at the
// claim); with the stub down it is a chain transit (one leg, patched both ways
// at once, the resolver still watching).  A20 dials 1 1 1 2 1 and B21 rings.
//
// A TRIAL is one call, set up from idle, with ONE disturbance at a chosen
// instant: A20 hangs up, B21 hangs up, B21 lifts, or both hang up.  The instant
// is an ANCHOR event of a reference call (trial 0 of the run, undisturbed) plus
// an offset, and every trial starts on A's tick, so the timeline repeats to the
// clock (each trial prints its own anchors to show it).  After the disturbance
// the bench puts every phone on-hook, waits for all three exchanges to idle --
// every port !BUSY, every socket's M low, every latch pointing at 00, the
// register, the marker, the unit's classifier, origin, forwarder, sweep,
// monitors, resolvers and att all idle -- and says LEAK with the whole state
// if that has not happened +lim ms after the last phone went down.  After a
// leak it lifts the stuck phone once (what does its subscriber hear?), then
// resets all three exchanges.
//
// Per trial it also says PHANTOM if any phone but B21 is rung, or B21 is rung
// by a call that should not reach it, and LATE if B21 still rings 120 ms after
// its caller went.
//
// Families (+fams=bitmask; +stub=0 takes the S link down for the whole run):
//   0  A20 hangs up, lift + 3 ms + k * 7.37 ms          (coarse, whole call)
//   1  A20 hangs up around A's seizure                  (-2 .. +14 ms, 0.5)
//   2  A20 hangs up around X's forward                  (-1 .. +9, 0.5)
//   3  A20 hangs up around B's CLAIM                    (-2 .. +12, 0.5)
//   4  A20 hangs up around B's connect                  (-3 .. +9, 0.5)
//   5  B21 LIFTS around B's connect                     (-4 .. +8, 0.5)
//   6  B21 hangs up after it answered, A20 stays 150 ms (0 .. 29, 1.37)
//   7  both hang up around B's connect                  (-2 .. +9, 1)
//   8  1 3 2 (nobody): A20 hangs up T_REL before A's T_CLAIM  (0.25 steps)
//   9  1 alone: A20 hangs up T_REL before A's T_KEY          (0.5 steps)
//  10  1 1 1 and stop: A20 hangs up T_REL before B's NODIG  (0.5 steps)
//
// Timers scaled by 8 as tb_net / tb_chain (T_ARM 2, T_REL 32, HIT 1, ID 16,
// CLR 32, NODIG 1250, guard 16, T_KEY 625, T_CLAIM 250); dial 12/8 ms, 100 ms
// after the key and 60 ms between the other digits.
`timescale 1ns/1ps
`include "exch.vh"

module tb_rel;
    reg clk_a = 1'b0, clk_x = 1'b0, clk_b = 1'b0;
    reg rst_a = 1'b0, rst_x = 1'b0, rst_b = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_x = ~clk_x; end
    initial begin #90; forever #122.070 clk_b = ~clk_b; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21;
    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, T13 = 6'o13, T15 = 6'o15, T30 = 6'o30;
    localparam [7:0] WE0 = {2'd2, 1'b0, 3'b010, 2'b11};     // facing E
    localparam [7:0] WW1 = {2'd3, 1'b1, 3'b010, 2'b11};     // facing W, glare
    localparam [7:0] WS0 = {2'd1, 1'b0, 3'b010, 2'b11};     // facing S
    localparam [511:0] TW_A = ({504'd0, WE0} << (8*T11)) | ({504'd0, WE0} << (8*T12));
    localparam [511:0] TW_X = ({504'd0, WW1} << (8*T11)) | ({504'd0, WW1} << (8*T12)) |
                              ({504'd0, WE0} << (8*T13)) | ({504'd0, WE0} << (8*T15)) |
                              ({504'd0, WS0} << (8*T30));
    localparam [511:0] TW_B = ({504'd0, WW1} << (8*T11)) | ({504'd0, WW1} << (8*T12));

    reg  [63:0] hook_a = 0, tx_a = 0, hook_x = 0, tx_x = 0, hook_b = 0, tx_b = 0;
    wire [63:0] rx_a, e_a, rx_x, e_x, rx_b, e_b, busy_a, busy_x, busy_b;
    wire [63:0] ac, aa, ak, xc, xa, xk, bc, ba, bk, up_a, up_x, up_b;
    reg  [63:0] ac_i, aa_i, ak_i, xc_i, xa_i, xk_i, bc_i, ba_i, bk_i;
    wire        fs_a, fs_x, fs_b, t1k_a, t1k_x, t1k_b, rc_a, rc_x, rc_b;
    wire        sd_a, sc_a, wr_a, cl_a, sd_x, sc_x, wr_x, cl_x, sd_b, sc_b, wr_b, cl_b;
    wire        reg_a, reg_x, reg_b, mo_a, mo_x, mo_b, cla_a, cla_x, cla_b;
    wire        hu_a, hu_x, hu_b, uo_a, uo_x, uo_b;
    wire [2:0]  ms_a, ms_x, ms_b;
    wire [3:0]  dirs_a, dirs_x, dirs_b;
    wire [1:0]  res_a, res_x, res_b, mon_a, mon_x, mon_b;
    wire [7:0]  gl_a, gl_x, gl_b, nf_a, nf_x, nf_b;

// +define+TRELP=9'd28: the ports' release RC 12 % faster than the registers'
// CLR -- inside the +-20 % the documents draw the detectors with (mvp.md)
`ifndef TRELP
`define TRELP 9'd32
`endif
`define SITE_PARAMS .PHONES(64'h0000_0000_0003_0000), \
        .T_ARM(9'd2), .T_REL(`TRELP), .RING_ON(13'd64), .RING_OFF(13'd128), \
        .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250), \
        .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)

    site_net #(`SITE_PARAMS, .TRUNKS((64'd1 << T11) | (64'd1 << T12)), .TWORD(TW_A),
               .OWN_E(3'd2), .OWN_B(3'd2)) A (
        .clk(clk_a), .rst_n(rst_a), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(ac), .a_out(aa), .clk_out(ak), .c_in(ac_i), .a_in(aa_i), .clk_in(ak_i),
        .link_up(up_a), .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a),
        .port_busy(busy_a), .b_sdata(sd_a), .b_sclk(sc_a), .b_wr(wr_a), .b_clash(cl_a),
        .reg_busy(reg_a), .mk_state(ms_a), .mk_ovf(mo_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(hu_a),
        .un_ovf(uo_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(`SITE_PARAMS,
               .TRUNKS((64'd1 << T11) | (64'd1 << T12) | (64'd1 << T13) | (64'd1 << T15) |
                       (64'd1 << T30)),
               .TWORD(TW_X), .OWN_E(3'd3), .OWN_B(3'd3)) X (
        .clk(clk_x), .rst_n(rst_x), .hook(hook_x), .tx(tx_x), .rx(rx_x), .e(e_x),
        .c_out(xc), .a_out(xa), .clk_out(xk), .c_in(xc_i), .a_in(xa_i), .clk_in(xk_i),
        .link_up(up_x), .frame_stb(fs_x), .tick_1k(t1k_x), .ring_cad_n(rc_x),
        .port_busy(busy_x), .b_sdata(sd_x), .b_sclk(sc_x), .b_wr(wr_x), .b_clash(cl_x),
        .reg_busy(reg_x), .mk_state(ms_x), .mk_ovf(mo_x), .dirs_held(dirs_x),
        .res_busy(res_x), .mon_held(mon_x), .claimed(cla_x), .hunting(hu_x),
        .un_ovf(uo_x), .n_glare(gl_x), .n_nofwd(nf_x));

    site_net #(`SITE_PARAMS, .TRUNKS((64'd1 << T11) | (64'd1 << T12)), .TWORD(TW_B),
               .OWN_E(3'd1), .OWN_B(3'd1)) B (
        .clk(clk_b), .rst_n(rst_b), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(bc), .a_out(ba), .clk_out(bk), .c_in(bc_i), .a_in(ba_i), .clk_in(bk_i),
        .link_up(up_b), .frame_stb(fs_b), .tick_1k(t1k_b), .ring_cad_n(rc_b),
        .port_busy(busy_b), .b_sdata(sd_b), .b_sclk(sc_b), .b_wr(wr_b), .b_clash(cl_b),
        .reg_busy(reg_b), .mk_state(ms_b), .mk_ovf(mo_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(hu_b),
        .un_ovf(uo_b), .n_glare(gl_b), .n_nofwd(nf_b));

    // ---- the cables: A11-X11, A12-X12, X13-B11, X15-B12, X30-stub ----------
    reg stub_up = 1'b1;
    always @* begin
        ac_i = 0; aa_i = 0; ak_i = 0; xc_i = 0; xa_i = 0; xk_i = 0;
        bc_i = 0; ba_i = 0; bk_i = 0;
        ac_i[T11] = xc[T11]; aa_i[T11] = xa[T11]; ak_i[T11] = xk[T11];
        xc_i[T11] = ac[T11]; xa_i[T11] = aa[T11]; xk_i[T11] = ak[T11];
        ac_i[T12] = xc[T12]; aa_i[T12] = xa[T12]; ak_i[T12] = xk[T12];
        xc_i[T12] = ac[T12]; xa_i[T12] = aa[T12]; xk_i[T12] = ak[T12];
        xc_i[T13] = bc[T11]; xa_i[T13] = ba[T11]; xk_i[T13] = bk[T11];
        bc_i[T11] = xc[T13]; ba_i[T11] = xa[T13]; bk_i[T11] = xk[T13];
        xc_i[T15] = bc[T12]; xa_i[T15] = ba[T12]; xk_i[T15] = bk[T12];
        bc_i[T12] = xc[T15]; ba_i[T12] = xa[T15]; bk_i[T12] = xk[T15];
        // the stub: a far end that is alive (its clock runs) and never answers
        xc_i[T30] = 1'b0; xa_i[T30] = 1'b0; xk_i[T30] = stub_up && xk[T30];
    end

    // ---- hierarchical names -------------------------------------------------
`define UA A.u_x.u_net
`define UX X.u_x.u_net
`define UB B.u_x.u_net
`define PT(S, BK, PS) S.u_x.u_exch.pos[BK].u_blk.u_port``PS

    // one port's latch and detectors, for a leak report
`define PDUMP(NM, PR) $display("        %s addr=%o bsy=%0d clm=%0d  m=%0d fm=%0d  e=%0d fe=%0d  BUSY=%0d  rb=%0d", \
        NM, PR.addr, PR.bsy, PR.clm, PR.m, PR.fm, PR.e, PR.fe, PR.busy, PR.rb)

    // every latch this bench can see, pointing at 00
    wire addr0_a = (`PT(A,2,0).addr == 0) && (`PT(A,2,1).addr == 0) &&
                   (`PT(A,1,1).addr == 0) && (`PT(A,1,2).addr == 0);
    wire addr0_x = (`PT(X,2,0).addr == 0) && (`PT(X,2,1).addr == 0) &&
                   (`PT(X,1,1).addr == 0) && (`PT(X,1,2).addr == 0) &&
                   (`PT(X,1,3).addr == 0) && (`PT(X,1,5).addr == 0) &&
                   (`PT(X,3,0).addr == 0);
    wire addr0_b = (`PT(B,2,0).addr == 0) && (`PT(B,2,1).addr == 0) &&
                   (`PT(B,1,1).addr == 0) && (`PT(B,1,2).addr == 0);

    wire un_idle_a = (`UA.cst == 0) && (`UA.fst == 0) && (`UA.nst == 0) && (`UA.cl_st == 0) &&
                     !`UA.att && (`UA.hst == 0);
    wire un_idle_x = (`UX.cst == 0) && (`UX.fst == 0) && (`UX.nst == 0) && (`UX.cl_st == 0) &&
                     !`UX.att && (`UX.hst == 0);
    wire un_idle_b = (`UB.cst == 0) && (`UB.fst == 0) && (`UB.nst == 0) && (`UB.cl_st == 0) &&
                     !`UB.att && (`UB.hst == 0);

    wire idle_a = (busy_a == 0) && (A.s_a == 0) && !reg_a && (ms_a == 0) && (dirs_a == 0) &&
                  (res_a == 0) && (mon_a == 0) && addr0_a && un_idle_a;
    wire idle_x = (busy_x == 0) && (X.s_a == 0) && !reg_x && (ms_x == 0) && (dirs_x == 0) &&
                  (res_x == 0) && (mon_x == 0) && addr0_x && un_idle_x;
    wire idle_b = (busy_b == 0) && (B.s_a == 0) && !reg_b && (ms_b == 0) && (dirs_b == 0) &&
                  (res_b == 0) && (mon_b == 0) && addr0_b && un_idle_b;
    wire idle_all = idle_a && idle_x && idle_b;

    // ---- being rung: the ports' own RB ---------------------------------------
    wire rb_a20 = `PT(A,2,0).rb, rb_a21 = `PT(A,2,1).rb;
    wire rb_x20 = `PT(X,2,0).rb, rb_x21 = `PT(X,2,1).rb;
    wire rb_b20 = `PT(B,2,0).rb, rb_b21 = `PT(B,2,1).rb;

    // ---- the anchors -----------------------------------------------------------
    localparam integer NEV = 16;
    realtime ev   [0:NEV-1];     // this trial, from its lift; -1 = not seen
    realtime ref_t[0:NEV-1];     // the reference trial's
    realtime t_lift;
    reg      tr_on = 1'b0;       // a trial is running: record anchors
    integer  q;

    // 0 lift  1 A flood_go  2 A seize  3 X hold  4 X forward  5 B hold  6 A f2
    // 7 B CLAIM  8 A claimed  9 X resolver free  10 B att_ack  11 A done
    // 12 B connect (WATCH)  13 B21 rung  14 B WATCH ends  15 B21 answers
    task mark(input integer k);
        begin if (tr_on && ev[k] < 0.0) ev[k] = $realtime - t_lift; end
    endtask
    reg res_x_seen = 1'b0;
    always @(posedge clk_a) if (tr_on) begin
        if (A.u_x.u_mk.flood_go)            mark(1);
        if (dirs_a != 0)                    mark(2);
        if (`UA.f2)                         mark(6);
        if (cla_a)                          mark(8);
        if (`UA.done)                       mark(11);
    end
    always @(posedge clk_x) if (tr_on) begin
        if (`UX.cst == 3'd3)                mark(3);
        if (res_x != 0) begin mark(4); res_x_seen = 1'b1; end
        if (res_x_seen && res_x == 0)       mark(9);
    end
    always @(posedge clk_b) if (tr_on) begin
        if (`UB.cst == 3'd3)                mark(5);
        if (`UB.cl_st != 0)                 mark(7);
        if (B.u_x.u_mk.att_ack)             mark(10);
        if (ms_b == 3'd7)                   mark(12);
        if (rb_b21)                         mark(13);
        if (ev[12] >= 0.0 && ms_b != 3'd7)  mark(14);
    end

    // ---- safety: who is rung, and when --------------------------------------
    integer  rb_other;           // ticks any phone but B21 was being rung
    realtime rb21_last;
    always @(posedge clk_a) if (tr_on) begin
        if (rb_a20 || rb_a21 || rb_x20 || rb_x21 || rb_b20) rb_other = rb_other + 1;
        if (rb_b21) rb21_last = $realtime;
    end

    integer clash = 0;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_x) if (cl_x) clash = clash + 1;
    always @(posedge clk_b) if (cl_b) clash = clash + 1;

    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask

    // ---- the phones -------------------------------------------------------------
    reg a_hung = 1'b0, b_hung = 1'b0, b_up = 1'b0, b_ans_ok = 1'b1;
    realtime t_ahang, t_bhang;

    task a20(input v); begin if (!a_hung) hook_a[P20] = v; end endtask

    // a wait inside the call's script: cut short once the caller is gone and
    // nothing more is to happen (actors 0 and 3)
    reg cut_short = 1'b0;
    task pw(input integer n);
        integer i;
        begin for (i = 0; i < n && !(cut_short && a_hung); i = i + 1) ms(1); end
    endtask

    task dial(input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                a20(1'b0); pw(12); a20(1'b1); pw(8);
            end
        end
    endtask

    // ---- the disturbance ------------------------------------------------------
    // actor 0 A20 hangs up, 1 B21 hangs up, 2 B21 lifts, 3 both hang up
    task hang_a; begin if (!a_hung) begin a_hung = 1'b1; hook_a[P20] = 1'b0; t_ahang = $realtime; end end endtask
    task hang_b; begin if (!b_hung) begin b_hung = 1'b1; hook_b[P21] = 1'b0; t_bhang = $realtime; end end endtask

    integer  actor;
    realtime t_dist;              // absolute
    reg      dist_done;
    always @(posedge clk_a) if (tr_on && !dist_done && $realtime >= t_dist) begin
        dist_done = 1'b1;
        case (actor)
        0: hang_a;
        1: hang_b;
        2: begin b_up = 1'b1; if (!b_hung) hook_b[P21] = 1'b1; end
        default: begin hang_a; hang_b; end
        endcase
    end

    // B21 answers ANS ms after B's connect, if nothing has happened to it and
    // its caller is still there; in family 5 it lifts at the disturbance instead
    integer ans_ms = 10;
    always @(posedge clk_b) if (tr_on && b_ans_ok && !b_up && !b_hung && !a_hung &&
                                ev[12] >= 0.0 && ($realtime - t_lift) >= ev[12] + ans_ms * 1.0e6) begin
        b_up = 1'b1; hook_b[P21] = 1'b1; mark(15);
    end

    // ---- one trial --------------------------------------------------------------
    // pattern 0: 1 1 1 2 1, answered, talk, A20 hangs up; 1: 1 3 2; 2: 1; 3: 1 1 1
    integer lim_ms = 800;
    reg     talk_ok;
    integer n_trial = 0, n_leak = 0, n_phantom = 0, n_late = 0, n_glare0;
    integer tfam, tk;
    real    td_us;
    reg     leaked;

    task wait_idle(output reg ok, output integer took);
        integer stable, t;
        begin
            stable = 0; t = 0; ok = 1'b0;
            while (t < lim_ms && stable < 40) begin
                ms(1); t = t + 1;
                if (idle_all) stable = stable + 1; else stable = 0;
            end
            ok = (stable >= 40);
            took = t - stable;
        end
    endtask

    task dump_state;
        begin
            $display("      A: busy=%o M=%o reg=%0d mk=%0d dirs=%b res=%b mon=%b cst=%0d fst=%0d nst=%0d hst=%0d cl=%0d att=%0d",
                     busy_a, A.s_a, reg_a, ms_a, dirs_a, res_a, mon_a, `UA.cst, `UA.fst, `UA.nst, `UA.hst, `UA.cl_st, `UA.att);
            $display("      X: busy=%o M=%o reg=%0d mk=%0d dirs=%b res=%b mon=%b cst=%0d fst=%0d nst=%0d hst=%0d cl=%0d att=%0d",
                     busy_x, X.s_a, reg_x, ms_x, dirs_x, res_x, mon_x, `UX.cst, `UX.fst, `UX.nst, `UX.hst, `UX.cl_st, `UX.att);
            $display("      B: busy=%o M=%o reg=%0d mk=%0d dirs=%b res=%b mon=%b cst=%0d fst=%0d nst=%0d hst=%0d cl=%0d att=%0d",
                     busy_b, B.s_a, reg_b, ms_b, dirs_b, res_b, mon_b, `UB.cst, `UB.fst, `UB.nst, `UB.hst, `UB.cl_st, `UB.att);
            `PDUMP("A20", `PT(A,2,0)); `PDUMP("A21", `PT(A,2,1));
            `PDUMP("A11", `PT(A,1,1)); `PDUMP("A12", `PT(A,1,2));
            `PDUMP("X20", `PT(X,2,0)); `PDUMP("X21", `PT(X,2,1));
            `PDUMP("X11", `PT(X,1,1)); `PDUMP("X12", `PT(X,1,2));
            `PDUMP("X13", `PT(X,1,3)); `PDUMP("X15", `PT(X,1,5)); `PDUMP("X30", `PT(X,3,0));
            `PDUMP("B20", `PT(B,2,0)); `PDUMP("B21", `PT(B,2,1));
            `PDUMP("B11", `PT(B,1,1)); `PDUMP("B12", `PT(B,1,2));
            $display("      mon cells: A %o/%o X %o/%o B %o/%o   res: X in=%o legs=%o held=%b act=%b",
                     `UA.m_port[5:0], `UA.m_port[11:6], `UX.m_port[5:0], `UX.m_port[11:6],
                     `UB.m_port[5:0], `UB.m_port[11:6], `UX.rs_in, `UX.rs_leg, `UX.rs_held, `UX.rs_act);
        end
    endtask

    task do_reset;
        begin
            rst_a = 1'b0; rst_x = 1'b0; rst_b = 1'b0;
            hook_a = 0; hook_x = 0; hook_b = 0;
            repeat (40) @(posedge clk_a);
            rst_a = 1'b1; rst_x = 1'b1; rst_b = 1'b1;
            ms(20);
        end
    endtask

    // the stuck phone's subscriber lifts: what does it hear, does it get dial tone?
    integer  j; reg s0, s1;
    task hear(input integer site, input [`PW-1:0] p);
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 16; j = j + 1) begin
                @(posedge fs_a); @(posedge clk_a);
                if (((site == 0) ? rx_a[p] : (site == 1) ? rx_x[p] : rx_b[p])) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask
    task probe_phone(input integer site, input [`PW-1:0] p, input [8*4-1:0] nm);
        reg was_busy;
        begin
            was_busy = (site == 0) ? busy_a[p] : (site == 1) ? busy_x[p] : busy_b[p];
            if (site == 0) hook_a[p] = 1'b1; else if (site == 1) hook_x[p] = 1'b1; else hook_b[p] = 1'b1;
            ms(20); hear(site, p);
            $display("      LIFT %0s (BUSY %0d): hears %0s, marker %0d, reg %0d", nm, was_busy,
                     (s1 && !s0) ? "ones (01, dial tone)" : (s0 && !s1) ? "zeros (03 or 00)" : "alternating (FILL/00)",
                     (site == 0) ? ms_a : (site == 1) ? ms_x : ms_b,
                     (site == 0) ? reg_a : (site == 1) ? reg_x : reg_b);
            if (site == 0) hook_a[p] = 1'b0; else if (site == 1) hook_x[p] = 1'b0; else hook_b[p] = 1'b0;
            ms(80);
            $display("      ... hung up again: BUSY now %0d", (site == 0) ? busy_a[p] : (site == 1) ? busy_x[p] : busy_b[p]);
        end
    endtask

    task run_trial(input integer pattern, input integer act, input integer anchor,
                   input real d_us, input reg is_ref);
        reg ok; integer took; realtime t_end; integer ph;
        begin
            // from idle, on A's tick
            wait_idle(ok, took);
            if (!ok) begin
                $display("  !! not idle before trial %0d: resetting", n_trial);
                dump_state; do_reset;
            end
            @(posedge t1k_a); @(posedge clk_a);
            for (q = 0; q < NEV; q = q + 1) ev[q] = -1.0;
            a_hung = 1'b0; b_hung = 1'b0; b_up = 1'b0; b_ans_ok = (act != 2);
            res_x_seen = 1'b0; rb_other = 0; rb21_last = -1.0;
            n_glare0 = gl_a + gl_x + gl_b;
            actor = act; dist_done = is_ref;
            t_lift = $realtime;
            t_dist = t_lift + ((anchor == 0) ? 0.0 : ref_t[anchor]) + d_us * 1000.0;
            if (!is_ref && anchor != 0 && ref_t[anchor] < 0.0) begin
                $display("  -- anchor %0d not in the reference: trial skipped", anchor);
                dist_done = 1'b1;
            end
            tr_on = 1'b1; mark(0);
            cut_short = !is_ref && (act == 0 || act == 3);
            hook_a[P20] = 1'b1; pw(10);
            // the dial.  Each step stops being acted on once A20 is gone
            dial(1); pw(100);
            case (pattern)
            0: begin dial(1); pw(60); dial(1); pw(60); dial(2); pw(60); dial(1);
                     pw(60);
                     if (is_ref) begin
                         // the talk path, both ways, once
                         tx_b[P21] = 1'b1; ms(4); talk_ok = (rx_a[P20] === 1'b1);
                         tx_b[P21] = 1'b0; ms(4); talk_ok = talk_ok && (rx_a[P20] === 1'b0);
                         tx_a[P20] = 1'b1; ms(4); talk_ok = talk_ok && (rx_b[P21] === 1'b1);
                         tx_a[P20] = 1'b0; ms(4); talk_ok = talk_ok && (rx_b[P21] === 1'b0);
                         $display("  REF talk path A20 <-> B21: %0s", talk_ok ? "ok" : "BROKEN");
                         ms(24);
                     end else pw(40);
                     // the called party hung up: the caller stays on under it
                     if (act == 1) ms(150);
               end
            1: begin dial(3); pw(60); dial(2); pw(300); end  // T_CLAIM + margin
            2: begin pw(700); end                             // T_KEY + margin
            3: begin dial(1); pw(60); dial(1); pw(1320); end  // NODIG + margin
            default: ;
            endcase
            // the end of the call: A20 goes, then B21
            if (!dist_done) begin
                // a disturbance still to come: wait for it
                while (!dist_done) ms(1);
                ms(2);
            end
            ms(1); hang_a; ms(50); hang_b; b_ans_ok = 1'b0;
            if (hook_b[P21]) begin hook_b[P21] = 1'b0; end
            t_end = $realtime;
            wait_idle(ok, took);
            tr_on = 1'b0;
            if (is_ref) for (q = 0; q < NEV; q = q + 1) ref_t[q] = ev[q];

            ph = 0;
            if (rb_other != 0) ph = 1;
            if (pattern != 0 && rb21_last >= 0.0) ph = 1;
            $display("T fam=%0d k=%0d act=%0d d=%0.2f  hangA=%0.3f hangB=%0.3f  %0s  idle+%0dms  ev:%0.2f %0.2f %0.2f %0.2f %0.2f %0.2f %0.2f %0.2f %0.2f %0.2f %0.2f %0.2f %0.2f %0.2f %0.2f  glare+%0d%0s%0s",
                     tfam, tk, act, d_us / 1000.0,
                     a_hung ? (t_ahang - t_lift) / 1.0e6 : -1.0, b_hung ? (t_bhang - t_lift) / 1.0e6 : -1.0,
                     ok ? "OK  " : "LEAK", took,
                     ev[1] / 1.0e6, ev[2] / 1.0e6, ev[3] / 1.0e6, ev[4] / 1.0e6, ev[5] / 1.0e6,
                     ev[6] / 1.0e6, ev[7] / 1.0e6, ev[8] / 1.0e6, ev[9] / 1.0e6, ev[10] / 1.0e6,
                     ev[11] / 1.0e6, ev[12] / 1.0e6, ev[13] / 1.0e6, ev[14] / 1.0e6, ev[15] / 1.0e6,
                     gl_a + gl_x + gl_b - n_glare0,
                     ph ? "  PHANTOM" : "",
                     (rb21_last >= 0.0 && a_hung && rb21_last > t_ahang + 120.0e6) ? "  LATE" : "");
            if (ph) n_phantom = n_phantom + 1;
            if (rb21_last >= 0.0 && a_hung && rb21_last > t_ahang + 120.0e6) n_late = n_late + 1;
            n_trial = n_trial + 1;
            if (!ok) begin
                n_leak = n_leak + 1;
                $display("    LEAK: still held %0d ms after the last phone went down", lim_ms);
                dump_state;
                // what the subscriber of a stuck phone gets on the next lift
                if (busy_a[P20]) probe_phone(0, P20, "A20");
                if (busy_b[P21]) probe_phone(2, P21, "B21");
                ms(200);
                $display("    after the lifts, 200 ms more:");
                dump_state;
                do_reset;
            end
            $fflush();
        end
    endtask

    // ---- the families ---------------------------------------------------------------
    integer fams, bph, xph;
    integer f_pat, f_act, f_anc, f_n;
    real    f_d0, f_st;
    task fam_def(input integer f);
        begin
            f_act = 0; f_pat = 0;
            case (f)
            0:  begin f_anc = 0;  f_d0 = 3000.0;     f_st = 7370.0; f_n = 70; end
            1:  begin f_anc = 2;  f_d0 = -2000.0;    f_st = 500.0;  f_n = 33; end
            2:  begin f_anc = 4;  f_d0 = -1000.0;    f_st = 500.0;  f_n = 21; end
            3:  begin f_anc = 7;  f_d0 = -2000.0;    f_st = 500.0;  f_n = 29; end
            4:  begin f_anc = 12; f_d0 = -3000.0;    f_st = 500.0;  f_n = 25; end
            5:  begin f_anc = 12; f_d0 = -4000.0;    f_st = 500.0;  f_n = 25; f_act = 2; end
            6:  begin f_anc = 15; f_d0 = 0.0;        f_st = 1370.0; f_n = 22; f_act = 1; end
            7:  begin f_anc = 12; f_d0 = -2000.0;    f_st = 1000.0; f_n = 12; f_act = 3; end
            8:  begin f_anc = 6;  f_d0 = 215000.0;   f_st = 250.0;  f_n = 25; f_pat = 1; end
            9:  begin f_anc = 2;  f_d0 = 590000.0;   f_st = 500.0;  f_n = 13; f_pat = 2; end
            10: begin f_anc = 10; f_d0 = 1208000.0;  f_st = 500.0;  f_n = 24; f_pat = 3; end
            default: begin f_anc = 0; f_d0 = 0.0; f_st = 0.0; f_n = 0; end
            endcase
        end
    endtask

    integer f, k, nmax, kfirst, ov;
    integer have_ref [0:3];
    initial begin
        if (!$value$plusargs("fams=%d", fams)) fams = 1;
        if (!$value$plusargs("lim=%d", lim_ms)) lim_ms = 800;
        if (!$value$plusargs("stub=%d", k)) k = 1;
        stub_up = (k != 0);
        if (!$value$plusargs("nmax=%d", nmax)) nmax = 1000;
        if (!$value$plusargs("kfirst=%d", kfirst)) kfirst = 0;
        if (!$value$plusargs("bph=%d", bph)) bph = 0;       // B's reset later by this many A clocks
        if (!$value$plusargs("xph=%d", xph)) xph = 0;
        for (q = 0; q < 4; q = q + 1) have_ref[q] = 0;
        $display("\n  tb_rel -- hang-up sweep: fams=%b stub=%0d lim=%0d bph=%0d xph=%0d port T_REL=%0d\n",
                 fams, stub_up, lim_ms, bph, xph, `TRELP);
        repeat (20) @(posedge clk_a);
        rst_a = 1'b1;
        fork
            begin repeat (xph) @(posedge clk_a); rst_x = 1'b1; end
            begin repeat (bph) @(posedge clk_a); rst_b = 1'b1; end
        join
        ms(20);
        if (!(up_a[T11] && up_x[T11] && up_x[T13] && up_b[T11]))
            $display("  !! links not up");
        $display("  stub link %0s", up_x[T30] ? "UP (X fans out: two legs)" : "DOWN (X is a chain transit: one leg)");

        for (f = 0; f < 11; f = f + 1) if (fams[f]) begin
            fam_def(f);
            if ($value$plusargs("d0us=%d", ov)) f_d0 = ov;
            if ($value$plusargs("stus=%d", ov)) f_st = ov;
            if ($value$plusargs("n=%d", ov))    f_n  = ov;
            if (!have_ref[f_pat]) begin
                tfam = -1; tk = f_pat;
                run_trial(f_pat, 0, 0, 0.0, 1'b1);
                have_ref[f_pat] = 1;
                $display("  REF pattern %0d: flood_go %0.2f seize %0.2f Xhold %0.2f Xfwd %0.2f Bhold %0.2f f2 %0.2f CLAIM %0.2f claimed %0.2f Xres0 %0.2f att_ack %0.2f done %0.2f connect %0.2f rung %0.2f watch_end %0.2f answer %0.2f",
                         f_pat, ref_t[1]/1.0e6, ref_t[2]/1.0e6, ref_t[3]/1.0e6, ref_t[4]/1.0e6, ref_t[5]/1.0e6,
                         ref_t[6]/1.0e6, ref_t[7]/1.0e6, ref_t[8]/1.0e6, ref_t[9]/1.0e6, ref_t[10]/1.0e6,
                         ref_t[11]/1.0e6, ref_t[12]/1.0e6, ref_t[13]/1.0e6, ref_t[14]/1.0e6, ref_t[15]/1.0e6);
            end
            $display("  -- family %0d: pattern %0d actor %0d anchor %0d d0 %0.2f ms step %0.3f ms n %0d",
                     f, f_pat, f_act, f_anc, f_d0 / 1000.0, f_st / 1000.0, f_n);
            for (k = kfirst; k < f_n && k < kfirst + nmax; k = k + 1) begin
                tfam = f; tk = k; td_us = f_d0 + k * f_st;
                run_trial(f_pat, f_act, f_anc, td_us, 1'b0);
            end
        end

        $display("\n  %0d trials: %0d LEAK, %0d PHANTOM, %0d LATE; cable-B clashes %0d; ovf %0d%0d%0d %0d%0d%0d",
                 n_trial, n_leak, n_phantom, n_late, clash, mo_a, mo_x, mo_b, uo_a, uo_x, uo_b);
        $finish;
    end

    // watchdog: simulated time
    integer wd_s;
    initial begin
        if (!$value$plusargs("wd=%d", wd_s)) wd_s = 200;
        #(wd_s * 1.0e9);
        $display("  WATCHDOG at %0d s simulated", wd_s); $finish;
    end

    wire _unused = &{1'b0, rc_a, rc_x, rc_b, t1k_x, t1k_b, sd_a, sc_a, wr_a, sd_x, sc_x, wr_x,
                     sd_b, sc_b, wr_b, cla_x, cla_b, hu_a, hu_x, hu_b, nf_a, nf_x, nf_b,
                     e_a, e_x, e_b, up_b, fs_x, fs_b, tx_a, tx_x, tx_b, 1'b0};
endmodule

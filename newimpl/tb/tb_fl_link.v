// tb_fl_link -- two exchanges on one link: the flood study's fixes that need
// no third exchange.  newimpl/flood-study/REPORT.md §5, C01/C02, C06, C07,
// C15, C17; network.md §2, §4.1; register.md §3; trunks.md §2, §3.
//
// Exchange A is code 2 1 and exchange B is code 2 3.  Each is top_net with
// phones at 20, 21 and 22 and tone sources at 01 and 03.  Two baseband trunks
// join them, A's 11 and 12 to B's 11 and 12, and a local eight-channel trunk
// on block 3 of each, A30-37 to B30-37.  A's cards face east, B's west with
// glare, so A's key takes A11, the lowest trunk facing east, and B's takes
// B37, the highest facing west.  The baseband cables are cut for the two
// local-trunk scenarios, so that A's key takes A30 there.
//
//   C07  AN OUTAGE IS A RELEASE, NEVER A PULSE
//    1  in b      A20 dials 1 2 2 . 2 1 (22: nobody); 6 ms of outage, both
//                 ways, in the pause after b.  It must not be B's third pulse
//                 of b: nobody claims, B21 never rings
//    2  long      A20 dials 1 4 2 3 2 1 (42: nobody); the cable out 110 ms
//                 from e's first break into e's pause.  Coming back, A20's M
//                 must not be a fresh seizure at B, counted from b: 2 3 is
//                 B's own code, and 2 1 would ring B21
//    3  one way   A20 dials 1 2 2 2 3; 6 ms of outage in b's pause, A to B
//                 only.  B's card poisons and A's does not; B's must stay
//                 poisoned while A20's M is still on its input, or it hands
//                 B A20's h s as a fresh e b -- 2 3, B's own.  h s come 40 ms
//                 apart, so that at this scale they land inside A's claim wait
//    4  LTU, b    scenario 1 on the local trunk: A30 carries the flood
//    5  LTU, one  A20 keys 1 and holds A30; 6 ms of outage A to B.  B's
//       channel   channel 0 stays poisoned while A20's M stands on it; the other
//                 seven clear, and B20 calls A21 through B37 meanwhile
//   C17  NO CANNOT-COMPLETE WRITE AFTER THE CALLER'S PORT RELEASED
//    6  NODIG     A21 lifts, dials nothing, hangs up 30 ms before its no-digit
//                 time: its port releases before the timeout, the register
//                 hears the hang-up after it
//    7  T_KEY     A20 keys 1 and hangs up 30 ms before the 5 s rule
//    8  T_CLAIM   A20 dials 1 3 3 (nobody) and hangs up 30 ms before the
//                 claim wait runs out
//    9  far end   A20 dials 1 2 3 2 and stops; B's claim register waits for
//                 s.  A20 hangs up 31 ms before that register's no-digit
//                 time: B11 releases first.  A write of 03 with CLAIM on the
//                 released B11 would hold it BUSY for good and put backward A
//                 on A11 -- a phantom seizure at A
//   C06  A20 keys 1 with a 20 ms make, so a one-pulse e breaks inside the
//   10   sweep, before the seizure is written.  B would count A's b as its e:
//        1 1 2 3 2 1 at A is 2 3 2 1 at B.  Cannot-complete instead
//   C15  A20 dials 1 2 3 2 1 and B20, 150 ms behind, 1 2 1 2 2: crossing
//   11   calls.  A20's claim reaches B while B20 still dials e on B's line
//        register; the claim register takes it.  Neither is refused, A22 and
//        B21 ring.  (Not both b's together: with connect at the claim each
//        origin frees its register at the far CLAIM word, so even one register
//        an exchange no longer deadlocks there.)
//   C01/C02  B20 calls B21 and its line chatters, holding B's marker in WATCH
//   12   A20 dials 1 2 3 2 2 meanwhile: the claim register takes the claim at
//        once and collects 2 2; the connect waits for the watch; B22 rings
//   13   the same, and A20 hangs up the moment B claims: after the watch
//        nothing is left BUSY or held, and nothing rings
//
// Timers scaled by 8 through the straps, as tb_net's: the register's windows
// HIT 1, ID 16, CLR 32 ms, the ports' T_ARM 2, the guard 16, the 5 s rule
// 625, the claim wait 250 ms, NODIG 1250; a dial at 50 pps 60/40 with 100 ms
// between digits.  EVERY PORT'S T_REL IS 26, NOT 32: an RC 20 % short against
// the registers' exact CLR (flood-study C17 notes).  With equal timers the
// C17 windows are about 1.75 ms wide; at 26 against 32 they are about 7, and
// each C17 scenario lands in the middle of its window and checks that it did.
// The cards' outage timing is not scaled: RIDE is 4 ms, the poison's clear
// is scaled with CLR (baseband 37.5 ms idle, local trunk four 16 ms strobes).
//
// Wall time: 280 s under Verilator for 17 s simulated (254 s run, 30-100 s
// build), up to 13 minutes on a loaded machine.  69 checks.
//
// Does not cover: an outage between HIT and RIDE, which at scale 8 (HIT 1 ms)
// is still a pulse and at real timers (HIT 8 ms) cannot be; an outage during
// a transit's forward (C10); C17's WATCH form (ten seconds of chatter); the
// class marker's C17 gates (marker.v, top_max); the ring (C19) and every
// finding that needs a third exchange.
`timescale 1ns/1ps
`include "exch.vh"

module tb_fl_link;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*80-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_b = ~clk_b; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21, P22 = 6'o22;
    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, L30 = 6'o30, L37 = 6'o37;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};      // facing E, no glare
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};      // facing W, glare
    localparam [511:0] TW_A = ({504'd0, WE} << (8*T11)) | ({504'd0, WE} << (8*T12));
    localparam [511:0] TW_B = ({504'd0, WW} << (8*T11)) | ({504'd0, WW} << (8*T12));
    localparam [63:0]  PH   = (64'd1 << P20) | (64'd1 << P21) | (64'd1 << P22);
    localparam [63:0]  TRK  = (64'd1 << T11) | (64'd1 << T12) | (64'hFF << L30);
    localparam [15:0]  NODIG = 16'd1250;
    localparam [15:0]  T_KEY = 16'd625, T_CLAIM = 16'd250;

    // ---- the two sites -------------------------------------------------------
    reg  [63:0] hook_a = 64'd0, tx_a = 64'd0, hook_b = 64'd0, tx_b = 64'd0;
    wire [63:0] rx_a, e_a, rx_b, e_b, busy_a, busy_b;
    wire [63:0] ac_out, aa_out, ak_out, bc_out, ba_out, bk_out, up_a, up_b;
    reg  [63:0] ac_in, aa_in, ak_in, bc_in, ba_in, bk_in;
    wire [7:0]  lc_a, la_a, lh_a, lk_a, lc_b, la_b, lh_b, lk_b, lup_a, lup_b;
    wire        fs_a, fs_b, t1k_a, t1k_b, rc_a, rc_b;
    wire        sd_a, sc_a, wr_a, cl_a, sd_b, sc_b, wr_b, cl_b;
    wire        reg_a, reg_b, mko_a, mko_b, cla_a, cla_b, hunt_a, hunt_b, uno_a, uno_b;
    wire        creg_a, creg_b;   // the claim registers
    wire [2:0]  mks_a, mks_b;
    wire [3:0]  dirs_a, dirs_b;
    wire [1:0]  res_a, res_b, mon_a, mon_b;
    wire [7:0]  gl_a, gl_b, nf_a, nf_b;

    // ---- the cables ------------------------------------------------------------
    // cut_bb opens every conductor of both baseband cables, both ways; cut_ab
    // only B's receivers -- one side's pins of a lifted connector.  The local
    // trunk's cable likewise, with receivers whose failsafe reads 1 on an open
    // line (tb_lnet's).
    reg cut_bb = 1'b0, cut_ab = 1'b0, lt_cut = 1'b0, lt_cut_ab = 1'b0;
    wire cb  = cut_bb || cut_ab;
    wire lcb = lt_cut || lt_cut_ab;
    always @* begin
        ac_in = 64'd0; aa_in = 64'd0; ak_in = 64'd0;
        bc_in = 64'd0; ba_in = 64'd0; bk_in = 64'd0;
        ac_in[T11] = !cut_bb && bc_out[T11]; aa_in[T11] = !cut_bb && ba_out[T11];
        ak_in[T11] = !cut_bb && bk_out[T11];
        ac_in[T12] = !cut_bb && bc_out[T12]; aa_in[T12] = !cut_bb && ba_out[T12];
        ak_in[T12] = !cut_bb && bk_out[T12];
        bc_in[T11] = !cb && ac_out[T11]; ba_in[T11] = !cb && aa_out[T11]; bk_in[T11] = !cb && ak_out[T11];
        bc_in[T12] = !cb && ac_out[T12]; ba_in[T12] = !cb && aa_out[T12]; bk_in[T12] = !cb && ak_out[T12];
    end
    wire [7:0] lc_ai = {4'd0, lt_cut | lc_b[3], 3'd0}, la_ai = {4'd0, lt_cut | la_b[3], 3'd0};
    wire [7:0] lh_ai = {4'd0, lt_cut | lh_b[3], 3'd0}, lk_ai = {4'd0, lt_cut | lk_b[3], 3'd0};
    wire [7:0] lc_bi = {4'd0, lcb | lc_a[3], 3'd0},    la_bi = {4'd0, lcb | la_a[3], 3'd0};
    wire [7:0] lh_bi = {4'd0, lcb | lh_a[3], 3'd0},    lk_bi = {4'd0, lcb | lk_a[3], 3'd0};

    site_net #(.PHONES(PH), .TRUNKS((64'd1 << T11) | (64'd1 << T12)), .TWORD(TW_A),
               .LTU(8'b0000_1000), .LTWORD({32'd0, WE, 24'd0}),
               .OWN_E(3'd2), .OWN_B(3'd1),
               .T_ARM(9'd2), .T_REL(9'd26), .RING_ON(13'd64), .RING_OFF(13'd128),
               .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(NODIG),
               .T_GUARD0(16'd16), .T_KEY(T_KEY), .T_CLAIM(T_CLAIM)) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(ac_out), .a_out(aa_out), .clk_out(ak_out),
        .c_in(ac_in), .a_in(aa_in), .clk_in(ak_in), .link_up(up_a),
        .lt_c_out(lc_a), .lt_a_out(la_a), .lt_h_out(lh_a), .lt_k_out(lk_a),
        .lt_c_in(lc_ai), .lt_a_in(la_ai), .lt_h_in(lh_ai), .lt_k_in(lk_ai), .lt_up(lup_a),
        .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a), .port_busy(busy_a),
        .b_sdata(sd_a), .b_sclk(sc_a), .b_wr(wr_a), .b_clash(cl_a),
        .reg_busy(reg_a), .creg_busy(creg_a), .mk_state(mks_a), .mk_ovf(mko_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(hunt_a),
        .un_ovf(uno_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(.PHONES(PH), .TRUNKS((64'd1 << T11) | (64'd1 << T12)), .TWORD(TW_B),
               .LTU(8'b0000_1000), .LTWORD({32'd0, WW, 24'd0}),
               .OWN_E(3'd2), .OWN_B(3'd3),
               .T_ARM(9'd2), .T_REL(9'd26), .RING_ON(13'd64), .RING_OFF(13'd128),
               .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(NODIG),
               .T_GUARD0(16'd16), .T_KEY(T_KEY), .T_CLAIM(T_CLAIM)) B (
        .clk(clk_b), .rst_n(rst_n), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(bc_out), .a_out(ba_out), .clk_out(bk_out),
        .c_in(bc_in), .a_in(ba_in), .clk_in(bk_in), .link_up(up_b),
        .lt_c_out(lc_b), .lt_a_out(la_b), .lt_h_out(lh_b), .lt_k_out(lk_b),
        .lt_c_in(lc_bi), .lt_a_in(la_bi), .lt_h_in(lh_bi), .lt_k_in(lk_bi), .lt_up(lup_b),
        .frame_stb(fs_b), .tick_1k(t1k_b), .ring_cad_n(rc_b), .port_busy(busy_b),
        .b_sdata(sd_b), .b_sclk(sc_b), .b_wr(wr_b), .b_clash(cl_b),
        .reg_busy(reg_b), .creg_busy(creg_b), .mk_state(mks_b), .mk_ovf(mko_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(hunt_b),
        .un_ovf(uno_b), .n_glare(gl_b), .n_nofwd(nf_b));

    // ---- inside the boards, WATCHED ONLY: to time a scenario and to read the
    // cards' poison.  Nothing here is forced. -----------------------------------
    // (the sockets are numbered in decimal: 9 and 10 are ports 11 and 12)
    wire       pz_a11 = A.sock[9].trunk.u_card.poison, pz_a12 = A.sock[10].trunk.u_card.poison;
    wire       pz_b11 = B.sock[9].trunk.u_card.poison, pz_b12 = B.sock[10].trunk.u_card.poison;
    wire [7:0] pz_la  = A.blk[3].ltu.u_ltu.poison,      pz_lb  = B.blk[3].ltu.u_ltu.poison;
    wire [3:0] nst_a  = A.u_x.u_net.nst;
    wire [15:0] tmr_a = A.u_x.u_net.tmr;
    wire       f2_a   = A.u_x.u_net.f2;
    wire [15:0] ndt_a = A.u_x.u_mk.u_reg.nd_t;       // the line register's no-digit timer
    wire [15:0] ndt_cb = B.u_x.u_creg.nd_t;          // B's claim register's
    wire       brk_a  = A.u_x.u_mk.reg_brk;
    wire       rel_a20 = A.u_x.u_exch.pos[2].u_blk.u_port0.rel;
    wire       rel_a21 = A.u_x.u_exch.pos[2].u_blk.u_port1.rel;
    wire       rel_b11 = B.u_x.u_exch.pos[1].u_blk.u_port1.rel;
    wire       nodig_a = A.u_x.u_mk.reg_nodig, nogo_a = A.u_x.u_net.nogo;
    wire       nodig_cb = B.u_x.u_creg.nodig;

    // ---- what rang, what was claimed, what was refused ---------------------------
    // A phone RINGS when its E is up while it is on-hook: the port gates E with
    // the cadence only then.  On-hook means for 40 ms, past T_REL: a dial
    // break is not on-hook, and a caller connected at the claim hears the far
    // trunk's backward A through every break of h s.
    reg [63:0] rg_a = 64'd0, rg_b = 64'd0;
    integer lo_a [0:63], lo_b [0:63];
    integer ph;
    initial for (ph = 0; ph < 64; ph = ph + 1) begin lo_a[ph] = 0; lo_b[ph] = 0; end
    always @(posedge t1k_a) begin : ra
        integer q;
        for (q = 16; q < 19; q = q + 1) begin
            lo_a[q] = hook_a[q] ? 0 : lo_a[q] + 1;
            if ((lo_a[q] > 40) && e_a[q]) rg_a[q] = 1'b1;
        end
    end
    always @(posedge t1k_b) begin : rb
        integer q;
        for (q = 16; q < 19; q = q + 1) begin
            lo_b[q] = hook_b[q] ? 0 : lo_b[q] + 1;
            if ((lo_b[q] > 40) && e_b[q]) rg_b[q] = 1'b1;
        end
    end
    reg cr_b_seen = 1'b0, cr_a_seen = 1'b0;      // a claim register was given a trunk
    always @(posedge clk_a) if (creg_a) cr_a_seen = 1'b1;
    always @(posedge clk_b) if (creg_b) cr_b_seen = 1'b1;
    task clear_watch; begin rg_a = 64'd0; rg_b = 64'd0; cr_a_seen = 1'b0; cr_b_seen = 1'b0; end endtask

    // A refusal is a trunk written to 03 with CLAIM: a listener on each bus.
    // G = 1 is a write; DST is bits 13-8, SRC bits 7-2, BSY bit 1, CLM bit 0.
    reg [15:0] sh_a = 16'd0, sh_b = 16'd0;
    reg sc_a_d = 1'b0, wr_a_d = 1'b0, sc_b_d = 1'b0, wr_b_d = 1'b0;
    integer refused = 0;
    always @(posedge clk_a) begin
        sc_a_d <= sc_a; wr_a_d <= wr_a;
        if (sc_a && !sc_a_d) sh_a <= {sh_a[14:0], sd_a};
        if (wr_a && !wr_a_d && sh_a[15] && (sh_a[7:2] == 6'o03) && sh_a[0] && TRK[sh_a[13:8]])
            refused = refused + 1;
    end
    always @(posedge clk_b) begin
        sc_b_d <= sc_b; wr_b_d <= wr_b;
        if (sc_b && !sc_b_d) sh_b <= {sh_b[14:0], sd_b};
        if (wr_b && !wr_b_d && sh_b[15] && (sh_b[7:2] == 6'o03) && sh_b[0] && TRK[sh_b[13:8]])
            refused = refused + 1;
    end

    // ---- the C17 boundary: when the port released and when the timer fired,
    // against the hang-up.  The register hears a hang-up CLR after it, so a
    // timer inside (release, hang-up + CLR) is the window.  Measured whatever
    // the marker then does, so the check holds with the fix out too.  `c17`
    // picks whose: 1 A21 and the line register's NODIG, 2 A20 and the unit's
    // nogo, 3 B11 and B's claim register's NODIG ----------------------------------
    localparam real CLR_NS = 32.0e6;
    integer c17 = 0;
    real t_hang = -1.0, t_rel = -1.0, t_act = -1.0;
    always @(posedge clk_a) begin
        if (((c17 == 1) && rel_a21) || ((c17 == 2) && rel_a20))
            if (t_rel < 0.0) t_rel = $realtime;
        if (((c17 == 1) && nodig_a) || ((c17 == 2) && nogo_a))
            if (t_act < 0.0) t_act = $realtime;
    end
    always @(posedge clk_b) if (c17 == 3) begin
        if (rel_b11  && (t_rel < 0.0)) t_rel = $realtime;
        if (nodig_cb && (t_act < 0.0)) t_act = $realtime;
    end
    task c17_arm(input integer k);
        begin c17 = k; t_hang = $realtime; t_rel = -1.0; t_act = -1.0; end
    endtask
    wire c17_window = (t_rel > 0.0) && (t_act > t_rel) && (t_act - t_hang < CLR_NS);

    // ---- C06: did e's break come while the key's sweep was running? -------------
    reg brk_sweep = 1'b0;
    always @(posedge clk_a)
        if (brk_a && ((nst_a == 4'd1) || (nst_a == 4'd2) || (nst_a == 4'd3))) brk_sweep = 1'b1;

    // ---- two '244s on one wire, at either exchange -------------------------------
    integer clash = 0;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_b) if (cl_b) clash = clash + 1;

    // ---- the bench's hands: tb_net's ----------------------------------------------
    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask
    task ms_b(input integer n); begin repeat (n) @(posedge t1k_b); end endtask

    // a digit's pulses, 60/40, ending on its last make, with no pause after
    task pulses_a(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; ms(12);
                hook_a[p] = 1'b1; ms(8);
            end
        end
    endtask
    task dial_a(input [`PW-1:0] p, input integer d); begin pulses_a(p, d); ms(100); end endtask
    task pulses_b(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_b[p] = 1'b0; ms_b(12);
                hook_b[p] = 1'b1; ms_b(8);
            end
        end
    endtask
    task dial_b(input [`PW-1:0] p, input integer d); begin pulses_b(p, d); ms_b(100); end endtask

    // What is this port hearing?  01 sends a steady 1 and 03 a steady 0.
    integer j; reg s0, s1;
    task hear_a(input [`PW-1:0] p);
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 8; j = j + 1) begin
                @(posedge fs_a); @(posedge clk_a);
                if (rx_a[p]) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask

    // wait up to n ms for a port to ring
    integer w;
    task ring_wait_a(input [`PW-1:0] p, input integer n);
        begin for (w = 0; (w < n) && !rg_a[p]; w = w + 1) @(posedge t1k_a); end
    endtask
    task ring_wait_b(input [`PW-1:0] p, input integer n);
        begin for (w = 0; (w < n) && !rg_b[p]; w = w + 1) @(posedge t1k_a); end
    endtask

    // B20's chattering line (flood study C01): 1 ms breaks, 2 ms makes.  Never
    // `settled` (SETTLE is 4 ms here), never `gone`, and no digit: a break of
    // one sample never reaches HIT's second.
    reg chat = 1'b0;
    always begin
        @(posedge t1k_b);
        if (chat) begin hook_b[P20] = 1'b0; ms_b(1); hook_b[P20] = 1'b1; ms_b(1); end
    end

    // A line left BUSY with no edge to clear it is freed by its owner lifting
    // and hanging up (flood-study C17 notes): after a C17 check has failed, so
    // that the scenarios after it still test what they say.
    task unstick(input [`PW-1:0] p);
        if (busy_a[p]) begin hook_a[p] = 1'b1; ms(40); hook_a[p] = 1'b0; ms(60); end
    endtask

    // every port, register, unit and card idle, and every card's poison clear
    task idle_all(input [8*80-1:0] what);
        begin
            ms(300);
            ck(busy_a == 64'd0 && busy_b == 64'd0 && !reg_a && !reg_b && !creg_a && !creg_b &&
               mks_a == 3'd0 && mks_b == 3'd0 && dirs_a == 4'd0 && dirs_b == 4'd0 &&
               mon_a == 2'd0 && mon_b == 2'd0 && res_a == 2'd0 && res_b == 2'd0 &&
               !pz_a11 && !pz_a12 && !pz_b11 && !pz_b12 && pz_la == 8'd0 && pz_lb == 8'd0, what);
            if (!(busy_a == 64'd0 && busy_b == 64'd0 && mon_a == 2'd0 && mon_b == 2'd0))
                $display("          busy_a %h busy_b %h mon %b %b poison %b%b%b%b %h %h",
                         busy_a, busy_b, mon_a, mon_b, pz_a11, pz_a12, pz_b11, pz_b12, pz_la, pz_lb);
        end
    endtask

    integer k;
    reg c15_hit;
    initial begin
        $display("\n  tb_fl_link -- two exchanges, one link: the flood study's fixes");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(20);
        ck(up_a[T11] && up_a[T12] && up_b[T11] && up_b[T12] && lup_a[3] && lup_b[3],
           "every link is up: both baseband trunks and the local trunk");

        // ================= C07 1.  an outage in b ==============================
        $display("  C07 1. A20 dials 1 2 2 2 1; 6 ms outage in b's pause");
        clear_watch;
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2);
        ck(busy_a[T11] === 1'b1 && busy_b[T11] === 1'b1, "the key seized A11, and B holds it");
        pulses_a(P20, 2); ms(4);
        cut_bb = 1'b1; ms(6);
        ck(pz_a11 && pz_b11, "the outage poisoned both cards of the seized trunk");
        cut_bb = 1'b0; ms(98);
        dial_a(P20, 2); dial_a(P20, 1);
        ms(300);
        ck(!cla_a && !cr_b_seen, "outage in b: nobody claims a call dialled to exchange 22");
        ck(!rg_b[P21] && !rg_b[P22] && !rg_b[P20], "outage in b: nothing rings at B, B21 least of all");
        hear_a(P20); ck(s0 && !s1, "A20 hears cannot-complete: the outage was a release");
        hook_a[P20] = 1'b0;
        idle_all("C07 1: idle again, every poison cleared");

        // ================= C07 2.  a long outage, back mid-dial ================
        $display("  C07 2. A20 dials 1 4 2 3 2 1; the cable out 110 ms around e");
        clear_watch;
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1);
        fork
            begin dial_a(P20, 4); dial_a(P20, 2); dial_a(P20, 3); dial_a(P20, 2); dial_a(P20, 1); end
            begin ms(2); cut_bb = 1'b1; ms(110); cut_bb = 1'b0; end
        join
        ms(300);
        ck(!cla_a && !cr_b_seen, "link back mid-dial: nobody claims a call dialled to exchange 42");
        ck(!rg_b[P21] && !rg_b[P22] && !rg_b[P20], "link back mid-dial: B21 (23-21, never dialled) does not ring");
        hear_a(P20); ck(s0 && !s1, "and A20 hears cannot-complete");
        hook_a[P20] = 1'b0;
        idle_all("C07 2: idle again, every poison cleared");

        // ================= C07 3.  a one-way outage ============================
        $display("  C07 3. A20 dials 1 2 2 2 3; 6 ms outage A to B only, in b's pause");
        clear_watch;
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2);
        pulses_a(P20, 2); ms(4);
        cut_ab = 1'b1; ms(6); cut_ab = 1'b0;
        ms(55);
        ck(pz_b11 && !pz_a11, "one way: A's card never poisoned; B's stays so while A20's M is on it");
        // h s follow closer than a dial's pause, so that at this scale h s land
        // inside A's claim wait: a card that cleared 37.5 ms after the link came
        // back would give B a fresh seizure 20 ms before h, and 2 3 at B
        ms(5);
        pulses_a(P20, 2); ms(40); pulses_a(P20, 3);
        ms(400);
        ck(!cla_a && !cr_b_seen, "one-way outage in b: nobody claims -- not 1 2 2, and not h s as 2 3");
        ck(rg_b == 64'd0, "one-way outage in b: nothing rings at B");
        hook_a[P20] = 1'b0;
        idle_all("C07 3: idle again, every poison cleared");

        // ================= C07 4.  an outage in b, on the local trunk ==========
        $display("  C07 4. the baseband cables cut; A20 dials 1 2 2 2 1, 6 ms LTU outage in b's pause");
        cut_bb = 1'b1; ms(10);
        clear_watch;
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2);
        ck(busy_a[L30] === 1'b1 && busy_b[L30] === 1'b1, "the key seized A30, the local trunk's channel 0");
        pulses_a(P20, 2); ms(4);
        lt_cut = 1'b1; ms(6);
        ck(pz_la == 8'hFF && pz_lb == 8'hFF, "the outage poisoned all eight channels at both ends");
        lt_cut = 1'b0; ms(98);
        ck(pz_la[0], "A's channel 0 stays poisoned while A20's M stands on it");
        ck(pz_la[7:1] == 7'd0 && pz_lb == 8'd0, "every other channel, at both ends, cleared");
        dial_a(P20, 2); dial_a(P20, 1);
        ms(300);
        ck(!cla_a && !cr_b_seen, "LTU outage in b: nobody claims a call dialled to exchange 22");
        ck(rg_b == 64'd0, "LTU outage in b: nothing rings at B");
        hook_a[P20] = 1'b0;
        ms(200);
        ck(pz_la == 8'd0 && pz_lb == 8'd0, "every channel cleared once nothing was held");

        // ================= C07 5.  one channel held, the others cleared =========
        $display("  C07 5. A20 keys 1 and holds A30; 6 ms LTU outage A to B; B20 dials 1 2 1 2 1");
        clear_watch;
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1);
        ck(busy_a[L30] === 1'b1, "A20's key holds A30");
        lt_cut_ab = 1'b1; ms(6); lt_cut_ab = 1'b0;
        ms(100);
        ck(pz_la == 8'd0, "one way: A's unit never poisoned");
        ck(pz_lb[0], "B's channel 0 stays poisoned while A20's M still stands on it");
        ck(pz_lb[7:1] == 7'd0, "and B's other seven channels cleared: one held channel keeps no other dead");
        hook_b[P20] = 1'b1; ms_b(10);
        dial_b(P20, 1);
        ck(busy_b[L37] === 1'b1, "B20's key took B37, a cleared channel");
        dial_b(P20, 2); dial_b(P20, 1); dial_b(P20, 2); dial_b(P20, 1);
        ring_wait_a(P21, 300);
        ck(rg_a[P21], "A21 rings from B20, through the local trunk, while B30 is poisoned");
        hook_a[P20] = 1'b0; hook_b[P20] = 1'b0;
        cut_bb = 1'b0;
        idle_all("C07 5: idle again, every poison cleared");

        // ================= C17 6.  NODIG, the caller's port released ===========
        $display("  C17 6. A21 lifts, dials nothing, hangs up 30 ms before NODIG");
        c17_arm(0);
        hook_a[P21] = 1'b1;
        fork wait (reg_a === 1'b1 && A.u_x.u_mk.reg_port == P21); ms(100); join_any
        disable fork;
        fork wait (ndt_a == NODIG - 16'd30); ms(1400); join_any
        disable fork;
        c17_arm(1);
        hook_a[P21] = 1'b0;
        ms(96);
        ck(c17_window, "C17 6: NODIG came after A21's port released, under CLR after the hang-up");
        ck(busy_a[P21] === 1'b0, "A21 hung up at the no-digit time: its port is not left BUSY");
        unstick(P21);
        c17_arm(0);
        idle_all("C17 6: idle again");

        // ================= C17 7.  T_KEY - T_REL ===============================
        $display("  C17 7. A20 keys 1, hangs up 30 ms before the 5 s rule");
        hook_a[P20] = 1'b1; ms(10);
        pulses_a(P20, 1);
        fork wait (nst_a == 4'd4 && tmr_a == T_KEY - 16'd30); ms(800); join_any
        disable fork;
        c17_arm(2);
        hook_a[P20] = 1'b0;
        ms(96);
        ck(c17_window, "C17 7: the 5 s rule came after A20's port released, under CLR after the hang-up");
        ck(busy_a[P20] === 1'b0, "A20 hung up at the 5 s rule: its port is not left BUSY");
        unstick(P20);
        c17_arm(0);
        idle_all("C17 7: idle again");

        // ================= C17 8.  T_CLAIM =====================================
        $display("  C17 8. A20 dials 1 3 3, hangs up 30 ms before the claim wait ends");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 3); pulses_a(P20, 3);
        fork wait (nst_a == 4'd5 && f2_a && tmr_a == T_CLAIM - 16'd30); ms(400); join_any
        disable fork;
        c17_arm(2);
        hook_a[P20] = 1'b0;
        ms(96);
        ck(c17_window, "C17 8: the claim wait ended after A20's port released, under CLR after it");
        ck(busy_a[P20] === 1'b0, "A20 hung up at the claim wait: its port is not left BUSY");
        unstick(P20);
        c17_arm(0);
        idle_all("C17 8: idle again");

        // ================= C17 9.  the far end's claim register =================
        $display("  C17 9. A20 dials 1 2 3 2, stops; hangs up 31 ms before B's claim register's NODIG");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 3); pulses_a(P20, 2);
        ck(cla_a === 1'b1 && creg_b === 1'b1, "B claimed on B11, and its claim register collects h s");
        fork wait (creg_b === 1'b1 && ndt_cb == NODIG - 16'd31); ms(1400); join_any
        disable fork;
        c17_arm(3);
        hook_a[P20] = 1'b0;
        ms(96);
        ck(c17_window, "C17 9: B's claim NODIG came after B11 released, under CLR after the hang-up");
        ck(busy_b[T11] === 1'b0, "B11 is not left BUSY with CLAIM on a released port");
        ms(200);
        ck(busy_a[T11] === 1'b0 && mon_a == 2'd0,
           "and A holds no phantom seizure on A11: no backward A was left standing");
        c17_arm(0);
        idle_all("C17 9: idle again");

        // ================= C06 10.  a break before the seizure =================
        $display("  C06 10. A20 keys 1 with a 20 ms make; e = 1 breaks inside the sweep");
        clear_watch; brk_sweep = 1'b0;
        hook_a[P20] = 1'b1; ms(10);
        hook_a[P20] = 1'b0; ms(12); hook_a[P20] = 1'b1; ms(20);   // the key: ID is 16
        dial_a(P20, 1);                                             // e, breaking in the sweep
        ck(brk_sweep, "e's break was counted while the key's sweep ran: the window");
        dial_a(P20, 2); dial_a(P20, 3); dial_a(P20, 2); dial_a(P20, 1);
        ms(100);
        ck(!cla_a && !cr_b_seen, "a call dialled to 12 is never claimed by 23");
        ck(rg_b == 64'd0, "and nothing rings at B: B21 was never dialled");
        hear_a(P20); ck(s0 && !s1, "A20 hears cannot-complete");
        hook_a[P20] = 1'b0;
        idle_all("C06 10: idle again");

        // ================= C15 11.  crossing calls =============================
        $display("  C15 11. A20 dials 1 2 3 2 1; B20, 150 ms behind, dials 1 2 1 2 2");
        clear_watch; refused = 0; c15_hit = 1'b0;
        fork
            begin hook_a[P20] = 1'b1; ms(10);
                  dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 3); dial_a(P20, 2); dial_a(P20, 1); end
            begin ms_b(150); hook_b[P20] = 1'b1; ms_b(10);
                  dial_b(P20, 1); dial_b(P20, 2); dial_b(P20, 1); dial_b(P20, 2); dial_b(P20, 2); end
            begin wait (creg_b === 1'b1); c15_hit = reg_b && !cla_b; end
        join
        ck(c15_hit, "A20's claim reached B while B20 held B's line register, and was taken");
        ck(cla_a === 1'b1 && cla_b === 1'b1, "both calls were claimed, each at the other exchange");
        ck(refused == 0, "and neither claim was refused: each took the far claim register");
        ring_wait_b(P21, 300); ring_wait_a(P22, 300);
        ck(rg_b[P21], "B21 rings, from A20");
        ck(rg_a[P22], "A22 rings, from B20");
        ck((rg_a & ~(64'd1 << P22)) == 64'd0 && (rg_b & ~(64'd1 << P21)) == 64'd0,
           "and nothing else rings");
        hook_a[P20] = 1'b0; hook_b[P20] = 1'b0;
        idle_all("C15 11: idle again");

        // ================= C01/C02 12.  a claim during WATCH ====================
        $display("  C01 12. B20 calls B21 and chatters in WATCH; A20 dials 1 2 3 2 2");
        clear_watch; refused = 0;
        hook_b[P20] = 1'b1; ms_b(10);
        dial_b(P20, 2); pulses_b(P20, 1);
        fork wait (mks_b == 3'd7); ms(300); join_any
        disable fork;
        chat = 1'b1;
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2); pulses_a(P20, 3);
        for (k = 0; (k < 100) && !cr_b_seen; k = k + 1) @(posedge t1k_a);
        ck(cr_b_seen && mks_b == 3'd7,
           "B's claim register took the claim at once, B's marker still in WATCH");
        ms(100);
        dial_a(P20, 2); pulses_a(P20, 2); ms(40);
        ck(mks_b == 3'd7 && busy_b[P22] === 1'b0,
           "h s collected while B20 chatters; the connect waits for the watch");
        chat = 1'b0; ms_b(3); hook_b[P20] = 1'b1;
        ring_wait_b(P22, 300);
        ck(rg_b[P22], "the watch over, the claim completes: B22 rings for A20");
        ck(refused == 0, "and the claim was never refused");
        ck((rg_b & ~((64'd1 << P21) | (64'd1 << P22))) == 64'd0 && rg_a == 64'd0,
           "nothing rings that nobody dialled");
        hook_a[P20] = 1'b0; hook_b[P20] = 1'b0;
        idle_all("C01 12: idle again");

        // ================= C01/C02 13.  the far caller gives up ==================
        $display("  C01 13. the same; A20 hangs up the moment B claims, B20 chatters 150 ms more");
        clear_watch;
        hook_b[P20] = 1'b1; ms_b(10);
        dial_b(P20, 2); pulses_b(P20, 1);
        fork wait (mks_b == 3'd7); ms(300); join_any
        disable fork;
        chat = 1'b1;
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2); pulses_a(P20, 3);
        for (k = 0; (k < 100) && !cr_b_seen; k = k + 1) @(posedge t1k_a);
        ck(cr_b_seen && mks_b == 3'd7, "the claim taken at once, in WATCH, again");
        hook_a[P20] = 1'b0;
        ms_b(150);
        ck(mks_b == 3'd7, "B's marker still watches, past B11's own release");
        chat = 1'b0; ms_b(3); hook_b[P20] = 1'b1;
        ms(40);
        ck(busy_b[T11] === 1'b0 && busy_a[T11] === 1'b0,
           "after the watch neither end of the trunk is left BUSY");
        ck(mon_a == 2'd0 && mon_b == 2'd0 && !creg_b, "no monitor and no claim register held");
        ck(rg_b[P22] === 1'b0 && rg_a == 64'd0, "and nothing rings that nobody dialled");
        hook_b[P20] = 1'b0;
        idle_all("C01 13: idle again");

        // ================= throughout ===========================================
        ck(clash == 0, "cable B never had two masters driving at once");
        ck(!mko_a && !mko_b && !uno_a && !uno_b, "no queue on either exchange refused a write");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #60_000_000_000; $display("  TIMEOUT"); $fatal(1); end

    wire _unused = &{1'b0, rc_a, rc_b, fs_b, rx_b, tx_b, hunt_a, hunt_b, gl_a, gl_b,
                     nf_a, nf_b, cr_a_seen, 1'b0};
endmodule

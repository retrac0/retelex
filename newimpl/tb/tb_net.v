// tb_net -- two exchanges on one link, and calls that are DIALLED.
// network.md §1, §3, §4; register.md §3; analysis/monitor-rules.md §1.
//
// Exchange A is code 2 2 and exchange B is code 2 3.  Each is top_net: the
// mini marker with its one register, a network unit, phones at 20 and 21,
// tone sources at 01 and 03.  Two baseband trunks join them, A's 11 and 12 to
// B's 11 and 12; A's cards face east, B's face west with glare.  A also has a
// trunk card at 25 whose cable is looped to itself, so that a DIALLED trunk
// has a live word to be refused on.  Neither exchange is told where the other
// is: each knows its own code, and its trunk cards say which way they face.
//
//   1  local     A20 dials 2 1: no trunk is touched
//   2  flood     A20 dials 1 2 3 2 1: B's monitor hears e then b and claims;
//                B's marker gives the trunk its register, which reads 2 1
//   3  own code  A20 dials 1 2 2 2 1: the trunk is let go, the call is local
//   4  nobody    A20 dials 1 2 4: no claim 2 s after b -> cannot-complete
//   5  reserved  1 8 and 1 2 9: cannot-complete, and nothing else happens
//   6  5 s rule  A20 dials 1 and stops: the trunk goes, cannot-complete
//   7  guard     a break inside the guard of the seizure: abandoned
//   8  no reg    B's register is busy when B claims: B points the trunk at
//                its cannot-complete, AFTER the CLAIM word, and A20 hears it
//   9  trunk     A20 dials 2 5, a trunk: cannot-complete, never connected
//  10  no trunk  every trunk's link cut: the hunt finds none, cannot-complete,
//                and EV_NOTRUNK goes out on A's cable B
//  11  stops     A20 dials 1 2 3 and stops: B has claimed, h s never come,
//                and only A's no-digit timeout can free the trunk -- the
//                register's `nodig`, not its `gone`, which is CLR only
//  12  waiting   A22 and A24 wait for A's one register while A20 floods: each
//                is read once, not every pass, and the sweep is not starved
//  13  one key   A20 dials 1 2 3 0: a one-key number after the code is
//                connected at three digits, and A20 hears B's answer to it
//  14  blip      0.9 ms of A on the cable into B11, just after a tick: long
//                enough for B to read and hold it, too short for B's port to
//                arm -- so B must write its own hold away, or 11 stays BUSY
//  15  key twice A20 dials 1 2 2 1: its own code turned the call local, and
//                a 1 now is highway 1 -- trunks -- not a second key: refused
//  16  two calls A20's call up through A11; A22 dials 1 2 3 2 0 meanwhile:
//                the sweep reads every port, the busy A11 too, and passes it
//                by -- it was not free at its select -- so the key takes A12
//  17  both B20 calls B21 while a seizure reaches B12, five times, a pass
//      masters   apart: once, B's marker is mid-word when B's unit wants the
//                bus, and the unit must wait the word out -- no clash
//
// Scenario 2 ends with the CALLED party hanging up first: B's trunk port then
// releases under A20's still-standing M, and must not be taken for a new
// seizure -- nor by B's marker for a call, which only its read of the trunk's
// word stops there: a listener on each bus counts every word that gives a
// trunk dial tone, and there must be none.  Scenario 7's break comes at once,
// so the far end's hold is written on a seizure that dies before B's port can
// arm -- and must still be cleared.
//
// Timers scaled by 8 through the straps, so a run is seconds: the register's
// windows HIT 1, ID 16, CLR 32 ms; the port's detectors 2 and 32 ms; the
// guard 16, the 5 s rule 625, the claim wait 250 ms; a dial at 50 pps 60/40.
// THE WORD READS AND THE SWEEP ARE NOT SCALED -- they are cable timing, 9 ms
// a sweep -- so at this scale the guard covers less than one hop, and the
// pause between digits (100 ms) is what keeps the flood ahead of the dial.
// Scenario 7 tests the guard's mechanism, not its reach.
//
// Does not cover: glare (EV_GLARE is not provoked), a transit (tb_chain), two
// floods at once on one exchange (16's second begins after the first is up),
// a relayed pulse at real speed, or MF8.
`timescale 1ns/1ps
`include "exch.vh"

module tb_net;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*72-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_b = ~clk_b; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21, P22 = 6'o22, P24 = 6'o24;
    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, T25 = 6'o25;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};      // facing E, no glare
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};      // facing W, glare
    localparam [511:0] TW_A = ({504'd0, WE} << (8*T11)) | ({504'd0, WE} << (8*T12)) |
                              ({504'd0, WE} << (8*T25));
    localparam [511:0] TW_B = ({504'd0, WW} << (8*T11)) | ({504'd0, WW} << (8*T12));

    // ---- the two sites -------------------------------------------------------
    reg  [63:0] hook_a = 64'd0, tx_a = 64'd0, hook_b = 64'd0, tx_b = 64'd0;
    wire [63:0] rx_a, e_a, rx_b, e_b, busy_a, busy_b;
    wire [63:0] ac_out, aa_out, ak_out, bc_out, ba_out, bk_out, up_a, up_b;
    reg  [63:0] ac_in, aa_in, ak_in, bc_in, ba_in, bk_in;
    wire        fs_a, fs_b, t1k_a, t1k_b, rc_a, rc_b;
    wire        sd_a, sc_a, wr_a, cl_a, sd_b, sc_b, wr_b, cl_b;
    wire        reg_a, reg_b, mko_a, mko_b, cla_a, cla_b, hunt_a, hunt_b, uno_a, uno_b;
    wire [2:0]  mks_a, mks_b;
    wire [3:0]  dirs_a, dirs_b;
    wire [1:0]  res_a, res_b, mon_a, mon_b;
    wire [7:0]  gl_a, gl_b, nf_a, nf_b;

    site_net #(.PHONES(64'h0000_0000_0017_0000), .TRUNKS((64'd1 << T11) | (64'd1 << T12) | (64'd1 << T25)),
               .TWORD(TW_A), .OWN_E(3'd2), .OWN_B(3'd2),
               .T_ARM(9'd2), .T_REL(9'd32), .RING_ON(13'd64), .RING_OFF(13'd128),
               .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250),
               .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(ac_out), .a_out(aa_out), .clk_out(ak_out),
        .c_in(ac_in), .a_in(aa_in), .clk_in(ak_in), .link_up(up_a),
        .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a), .port_busy(busy_a),
        .b_sdata(sd_a), .b_sclk(sc_a), .b_wr(wr_a), .b_clash(cl_a),
        .reg_busy(reg_a), .mk_state(mks_a), .mk_ovf(mko_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(hunt_a),
        .un_ovf(uno_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(.PHONES(64'h0000_0000_0003_0000), .TRUNKS((64'd1 << T11) | (64'd1 << T12)),
               .TWORD(TW_B), .OWN_E(3'd2), .OWN_B(3'd3),
               .T_ARM(9'd2), .T_REL(9'd32), .RING_ON(13'd64), .RING_OFF(13'd128),
               .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250),
               .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)) B (
        .clk(clk_b), .rst_n(rst_n), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(bc_out), .a_out(ba_out), .clk_out(bk_out),
        .c_in(bc_in), .a_in(ba_in), .clk_in(bk_in), .link_up(up_b),
        .frame_stb(fs_b), .tick_1k(t1k_b), .ring_cad_n(rc_b), .port_busy(busy_b),
        .b_sdata(sd_b), .b_sclk(sc_b), .b_wr(wr_b), .b_clash(cl_b),
        .reg_busy(reg_b), .mk_state(mks_b), .mk_ovf(mko_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(hunt_b),
        .un_ovf(uno_b), .n_glare(gl_b), .n_nofwd(nf_b));

    // ---- the cables: A11-B11, A12-B12, and A25 looped to itself ---------------
    reg cut = 1'b0, cut25 = 1'b0, blip = 1'b0, blip12 = 1'b0;
    always @* begin
        ac_in = 64'd0; aa_in = 64'd0; ak_in = 64'd0;
        bc_in = 64'd0; ba_in = 64'd0; bk_in = 64'd0;
        ac_in[T11] = !cut && bc_out[T11]; aa_in[T11] = !cut && ba_out[T11]; ak_in[T11] = !cut && bk_out[T11];
        ac_in[T12] = !cut && bc_out[T12]; aa_in[T12] = !cut && ba_out[T12]; ak_in[T12] = !cut && bk_out[T12];
        bc_in[T11] = !cut && ac_out[T11]; ba_in[T11] = blip || (!cut && aa_out[T11]);
        bk_in[T11] = !cut && ak_out[T11];
        bc_in[T12] = !cut && ac_out[T12]; ba_in[T12] = blip12 || (!cut && aa_out[T12]); bk_in[T12] = !cut && ak_out[T12];
        ac_in[T25] = !cut25 && ac_out[T25]; aa_in[T25] = !cut25 && aa_out[T25];
        ak_in[T25] = !cut25 && ak_out[T25];
    end

    // ---- a listener on A's cable B: the event words -----------------------------
    // Sixteen bits shifted on SCLK, the word taken at WR: what a counter card
    // on the bus does (proposed/counters.md §5).  G = 0 is an event; SRC is
    // its code.
    reg [15:0] sh_a = 16'd0; reg sc_a_d = 1'b0, wr_a_d = 1'b0;
    integer ev_notrunk = 0, ev_other = 0;
    always @(posedge clk_a) begin
        sc_a_d <= sc_a; wr_a_d <= wr_a;
        if (sc_a && !sc_a_d) sh_a <= {sh_a[14:0], sd_a};
        if (wr_a && !wr_a_d && !sh_a[15]) begin
            if (sh_a[7:2] == 6'o10) ev_notrunk = ev_notrunk + 1;
            else                    ev_other   = ev_other + 1;
        end
    end

    // ---- a listener on each bus: a trunk given dial tone -------------------------
    // A trunk's M is never a call (marker.md §3), so no word ever writes a
    // trunk to listen to 01.  A claimed trunk is given the register with no
    // dial tone.  G = 1 is a write; DST is bits 13-8, SRC bits 7-2.
    reg [15:0] sh_b = 16'd0; reg sc_b_d = 1'b0, wr_b_d = 1'b0;
    integer trunk_tone = 0;
    always @(posedge clk_a)
        if (wr_a && !wr_a_d && sh_a[15] && (sh_a[7:2] == 6'o01) &&
            ((sh_a[13:8] == T11) || (sh_a[13:8] == T12) || (sh_a[13:8] == T25)))
            trunk_tone = trunk_tone + 1;
    always @(posedge clk_b) begin
        sc_b_d <= sc_b; wr_b_d <= wr_b;
        if (sc_b && !sc_b_d) sh_b <= {sh_b[14:0], sd_b};
        if (wr_b && !wr_b_d && sh_b[15] && (sh_b[7:2] == 6'o01) &&
            ((sh_b[13:8] == T11) || (sh_b[13:8] == T12)))
            trunk_tone = trunk_tone + 1;
    end

    // ---- B's monitors, while nothing should be seizing B ------------------------
    reg watch_mb = 1'b0; integer mb_seen = 0;
    always @(posedge clk_b) if (watch_mb && mon_b != 2'd0) mb_seen = mb_seen + 1;

    // ---- two '244s on one wire, at either exchange -------------------------------
    integer clash = 0;
    integer k17, bad17;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_b) if (cl_b) clash = clash + 1;

    // ---- the bench's hands -------------------------------------------------------
    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask

    task dial_a(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; ms(12);
                hook_a[p] = 1'b1; ms(8);
            end
            ms(100);
        end
    endtask
    task dial_b(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_b[p] = 1'b0; ms(12);
                hook_b[p] = 1'b1; ms(8);
            end
            ms(100);
        end
    endtask

    // What is this port hearing?  01 sends a steady 1 and 03 a steady 0;
    // FILL, and silence on 00, alternate.
    integer j; reg s0, s1;
    task hear_a(input [`PW-1:0] p);
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 8; j = j + 1) begin
                @(posedge fs_a); @(posedge clk_a);
                if (rx_a[p]) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask
    task hear_b(input [`PW-1:0] p);
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 8; j = j + 1) begin
                @(posedge fs_b); @(posedge clk_b);
                if (rx_b[p]) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask

    integer hi, lo;
    task rings_b(input [`PW-1:0] p);
        integer i;
        begin hi = 0; lo = 0;
            for (i = 0; i < 400; i = i + 1) begin
                @(posedge t1k_b); if (e_b[p]) hi = hi + 1; else lo = lo + 1;
            end
        end
    endtask
    task rings_a(input [`PW-1:0] p);
        integer i;
        begin hi = 0; lo = 0;
            for (i = 0; i < 400; i = i + 1) begin
                @(posedge t1k_a); if (e_a[p]) hi = hi + 1; else lo = lo + 1;
            end
        end
    endtask

    task idle_all(input [8*72-1:0] what);
        begin
            ms(400);
            ck(busy_a == 64'd0 && busy_b == 64'd0 && !reg_a && !reg_b &&
               mks_a == 3'd0 && mks_b == 3'd0 && dirs_a == 4'd0 && res_b == 2'd0, what);
        end
    endtask

    initial begin
        $display("\n  tb_net -- two exchanges, one link, calls that are dialled");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(20);
        ck(up_a[T11] && up_a[T12] && up_b[T11] && up_b[T12] && up_a[T25],
           "every trunk's fifth conductor is running: the links are up");

        // ================= 1.  a local call, and no trunk touched ==============
        $display("  1. A20 dials 2 1");
        hook_a[P20] = 1'b1; ms(10);
        hear_a(P20); ck(s1 && !s0, "A20 read as a line and given dial tone");
        dial_a(P20, 2); dial_a(P20, 1); ms(20);
        rings_a(P21); ck(hi > 50 && lo > 50, "A21 rings, in cadence");
        ck(busy_a[T11] === 1'b0 && busy_a[T12] === 1'b0 && busy_b == 64'd0,
           "and no trunk was touched: a local call floods nothing");
        hook_a[P21] = 1'b1; ms(20);
        tx_a[P21] = 1'b1; ms(3); ck(rx_a[P20] === 1'b1, "A20 hears A21");
        tx_a[P21] = 1'b0; ms(3); ck(rx_a[P20] === 1'b0, "and follows it");
        hook_a[P20] = 1'b0; hook_a[P21] = 1'b0;
        idle_all("1: every port, register and unit idle again");

        // ================= 2.  the pulse flood =================================
        $display("  2. A20 dials 1 2 3 2 1");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1);                                      // the key
        ck(busy_a[T11] === 1'b1 && dirs_a == 4'b0100,
           "the key seized one trunk, the lowest facing E: A11");
        ck(busy_b[T11] === 1'b1, "B holds the seizure: its 11 is BUSY");
        ck(reg_b === 1'b0, "and B's marker did NOT take the trunk's M as a call");
        ck(mon_b != 2'd0, "a monitor at B counts from the rise");
        dial_a(P20, 2);                                      // e: B's, read on
        dial_a(P20, 3);                                      // b: B's -- claim
        ck(cla_a === 1'b1, "the claim came back: backward A at the origin");
        ck(reg_b === 1'b1, "B gave the claimed trunk its register");
        ck(mon_b == 2'd0, "and B's monitor is free: two digits and no more");
        dial_a(P20, 2); dial_a(P20, 1); ms(20);
        rings_b(P21); ck(hi > 50 && lo > 50, "B21 rings, from a caller on A");
        ck(reg_a === 1'b0 && reg_b === 1'b0, "both registers are free: the call is up");
        hook_b[P21] = 1'b1; ms(20);
        tx_a[P20] = 1'b1; ms(4); ck(rx_b[P21] === 1'b1, "B21 hears A20 across the link");
        tx_a[P20] = 1'b0; ms(4); ck(rx_b[P21] === 1'b0, "and follows it");
        tx_b[P21] = 1'b1; ms(4); ck(rx_a[P20] === 1'b1, "A20 hears B21: the other way");
        tx_b[P21] = 1'b0; ms(4); ck(rx_a[P20] === 1'b0, "and follows it");
        // B21 hangs up FIRST.  B11 releases 32 ms later, while A20's M still
        // stands on it -- M up and BUSY down, for a while, and it never rose.
        watch_mb = 1'b1;
        hook_b[P21] = 1'b0; ms(150);
        watch_mb = 1'b0;
        ck(mb_seen == 0, "the called party hung up first: B took no phantom seizure");
        hook_a[P20] = 1'b0;
        idle_all("2: release ran through every patch, both exchanges idle");

        // ================= 3.  our own code ====================================
        $display("  3. A20 dials 1 2 2 2 1");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 2);
        ms(60);
        ck(busy_a[T11] === 1'b0 && dirs_a == 4'd0, "own code: the trunk is let go");
        ck(reg_a === 1'b1 && reg_b === 1'b0, "and A's register reads on; B holds nothing");
        dial_a(P20, 2); dial_a(P20, 1); ms(20);
        rings_a(P21); ck(hi > 50 && lo > 50, "A21 rings: the call carried on locally");
        hook_a[P20] = 1'b0;
        idle_all("3: idle again");

        // ================= 4.  nobody claims ===================================
        $display("  4. A20 dials 1 2 4");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 4);
        ms(150);
        ck(dirs_a == 4'b0100, "no claim yet: the trunk is still held, 150 ms after b");
        ms(150);
        hear_a(P20); ck(s0 && !s1, "no claim 250 ms after b: cannot-complete");
        ck(dirs_a == 4'd0, "and the trunk is let go");
        hook_a[P20] = 1'b0;
        idle_all("4: idle again");

        // ================= 5.  8 and 9 in the code =============================
        $display("  5. A20 dials 1 8, then 1 2 9");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 8); ms(10);
        hear_a(P20); ck(s0 && !s1, "an e of 8 is reserved: cannot-complete at once");
        ck(dirs_a == 4'd0, "and the trunk is let go");
        hook_a[P20] = 1'b0; ms(300);
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 9); ms(10);
        hear_a(P20); ck(s0 && !s1, "a b of 9 is reserved: cannot-complete");
        hook_a[P20] = 1'b0;
        idle_all("5: idle again");

        // ================= 6.  the 5 s rule ====================================
        $display("  6. A20 dials 1, and stops");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1);
        ms(400);
        ck(busy_a[T11] === 1'b1, "400 ms after the key the trunk is still held");
        ms(300);
        ck(dirs_a == 4'd0, "b not in by 625 ms: the trunk is let go");
        hear_a(P20); ck(s0 && !s1, "and the caller hears cannot-complete");
        hook_a[P20] = 1'b0;
        idle_all("6: idle again");

        // ================= 7.  the guard ======================================
        $display("  7. a break inside the guard");
        hook_a[P20] = 1'b1; ms(10);
        hook_a[P20] = 1'b0; ms(12); hook_a[P20] = 1'b1;     // the key, one pulse
        while (busy_a[T11] !== 1'b1) @(posedge clk_a);       // the seizure
        hook_a[P20] = 1'b0; ms(4); hook_a[P20] = 1'b1;       // a break AT ONCE
        ms(30);
        ck(dirs_a == 4'd0, "a break inside the guard: the trunk is let go at once");
        hear_a(P20); ck(s0 && !s1, "and the call is abandoned: never a wrong number");
        ms(100);
        ck(busy_b[T11] === 1'b0,
           "B's hold on a seizure that died before its port armed is cleared");
        hook_a[P20] = 1'b0;
        idle_all("7: idle again");

        // ================= 8.  B's register is busy ============================
        $display("  8. B's register busy when B claims");
        hook_b[P20] = 1'b1; ms(10);
        dial_b(P20, 2);                                       // B20 holds B's register
        ck(reg_b === 1'b1, "B20 holds B's only register, waiting for its s");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 3);
        ck(cla_a === 1'b1, "B still claims: backward A reaches A");
        hear_b(T11); ck(s0 && !s1, "B's trunk listens to 03, not 00: the refusal came AFTER CLAIM");
        dial_a(P20, 2); dial_a(P20, 1); ms(20);
        hear_a(P20); ck(s0 && !s1, "A20 hears B's cannot-complete through the path");
        ck(busy_a[T11] === 1'b1, "and A's trunk is still up: the tone is B's, not A's own");
        hook_a[P20] = 1'b0; hook_b[P20] = 1'b0;
        idle_all("8: idle again");

        // ================= 9.  a dialled trunk =================================
        $display("  9. A20 dials 2 5, a trunk");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 2); dial_a(P20, 5); ms(20);
        hear_a(P20); ck(s0 && !s1, "25 says it is a trunk: cannot-complete");
        ck(busy_a[T25] === 1'b0, "and 25 was never written");
        hook_a[P20] = 1'b0;
        idle_all("9: idle again");

        // ================= 10.  no trunk ======================================
        $display("  10. every link cut");
        cut = 1'b1; cut25 = 1'b1; ms(5);
        ck(!up_a[T11] && !up_a[T12] && !up_a[T25], "A's trunks read their links down");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); ms(40);
        hear_a(P20); ck(s0 && !s1, "no trunk reads as one: cannot-complete");
        ck(ev_notrunk >= 1, "and EV_NOTRUNK went out on A's cable B");
        hook_a[P20] = 1'b0;
        cut = 1'b0; cut25 = 1'b0;
        idle_all("10: idle again");

        // ================= 11.  a caller who stops after b ======================
        $display("  11. A20 dials 1 2 3, and stops");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 3);
        ck(cla_a === 1'b1, "B claimed");
        ms(1000);
        ck(dirs_a == 4'b0100, "a second after b the trunk is still held, waiting for h s");
        ms(400);
        ck(dirs_a == 4'd0, "at the no-digit timeout the register goes, and the trunk with it");
        hear_a(P20); ck(s0 && !s1, "and the caller hears cannot-complete");
        hook_a[P20] = 1'b0;
        idle_all("11: idle again");

        // ================= 12.  two lines waiting while A floods ================
        $display("  12. A22 and A24 wait while A20 dials 1 2 3 2 1");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1);
        hook_a[P22] = 1'b1; hook_a[P24] = 1'b1;              // no register for them
        dial_a(P20, 2); dial_a(P20, 3);
        ck(cla_a === 1'b1, "the flood got through: the sweep was not starved");
        dial_a(P20, 2); dial_a(P20, 1); ms(20);
        rings_b(P21); ck(hi > 50 && lo > 50, "B21 rings");
        hook_a[P20] = 1'b0; ms(300);
        ck(reg_a === 1'b1, "and a waiting line has the register now");
        hook_a[P22] = 1'b0; hook_a[P24] = 1'b0;
        idle_all("12: idle again");

        // ================= 13.  a one-key number after the code =================
        $display("  13. A20 dials 1 2 3 0");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 3); dial_a(P20, 0);
        ms(20);
        ck(reg_a === 1'b0 && busy_a[T11] === 1'b1,
           "0 after the code is a whole number: A connected at three digits");
        hear_a(P20); ck(s0 && !s1, "and A20 hears B's answer to it: B's cannot-complete");
        hook_a[P20] = 1'b0;
        idle_all("13: idle again");

        // ================= 14.  a seizure too short for the port to arm ========
        // Started just after one of B's ticks and over before the next, so
        // B's port 11 sees M on no tick and its M detector never rises: no
        // fall will ever come to clear a latch written on it.  The pass starts
        // at the tick, so 11's turn is well inside the blip.
        $display("  14. a 0.9 ms blip of A into B11");
        mb_seen = 0; watch_mb = 1'b1;
        @(posedge t1k_b); blip = 1'b1; #900_000; blip = 1'b0;
        ms(40);
        watch_mb = 1'b0;
        ck(mb_seen > 0, "B read the blip as a seizure: it held it and gave it a monitor");
        ck(busy_b[T11] === 1'b0,
           "a seizure shorter than T_ARM: B wrote its hold away, 11 is not BUSY");
        idle_all("14: idle again");

        // ================= 15.  a second key after the own code ==============
        $display("  15. A20 dials 1 2 2 1");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 2); dial_a(P20, 1);
        ms(40);
        ck(dirs_a == 4'd0 && !hunt_a, "after its own code a 1 floods nothing");
        hear_a(P20); ck(s0 && !s1, "and is refused: cannot-complete");
        hook_a[P20] = 1'b0;
        idle_all("15: idle again");

        // ================= 16.  a second flood while the first holds A11 =====
        // A's one register is free again once a call is up, so a second caller
        // may flood while the first still holds A11.  The sweep reads every
        // port, A11 included, and keeps a trunk only if M and BUSY were clear
        // at its select: A11 is BUSY there, so the second key must take A12.
        $display("  16. A20 up on B21 through A11; then A22 dials 1 2 3 2 0");
        hook_a[P20] = 1'b1; ms(10);
        dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 3); dial_a(P20, 2); dial_a(P20, 1);
        ms(20); hook_b[P21] = 1'b1; ms(20);
        ck(busy_a[T11] === 1'b1 && reg_a === 1'b0,
           "the first call is up through A11, and A's register is free again");
        hook_a[P22] = 1'b1; ms(10);
        dial_a(P22, 1);
        ck(busy_a[T12] === 1'b1 && dirs_a == 4'b0100,
           "the second key seized A12: the busy A11 was read and passed by");
        dial_a(P22, 2); dial_a(P22, 3);
        ck(cla_a === 1'b1, "and B claimed the second call, on its 12");
        dial_a(P22, 2); dial_a(P22, 0); ms(20);
        rings_b(P20); ck(hi > 50 && lo > 50, "B20 rings: two calls up through A at once");
        hook_b[P20] = 1'b1; ms(20);
        tx_a[P22] = 1'b1; ms(4); ck(rx_b[P20] === 1'b1, "B20 hears A22");
        tx_a[P22] = 1'b0; ms(4); ck(rx_b[P20] === 1'b0, "and follows it");
        tx_a[P20] = 1'b1; ms(4); ck(rx_b[P21] === 1'b1, "while B21 still hears A20");
        tx_a[P20] = 1'b0; ms(4); ck(rx_b[P21] === 1'b0, "and follows it");
        hook_a[P20] = 1'b0; hook_a[P22] = 1'b0; hook_b[P20] = 1'b0; hook_b[P21] = 1'b0;
        idle_all("16: both calls released, both exchanges idle");

        // ================= 17.  both masters want cable B at once ============
        // There is no grant: the unit waits out the marker's longest word
        // before it drives (WAIT).  Before /WS the key's own words made the two
        // meet in every flood; now a read asks for no bus, and only a
        // coincidence does, so make one.  B20 calls B21: B's marker connects
        // them at frame 18 of a pass, the moment 21's sample is out.  A seizure
        // on B12 is held by B's unit at frame 18 too, its read ending eight
        // frames after 12's turn.  Started a pass later each time, one attempt
        // of the five puts both in one pass, the unit's word wanted while the
        // marker's first is on the wire -- and there it must wait.
        $display("  17. B20 calls B21 while a seizure reaches B12, five times");
        bad17 = 0;
        for (k17 = 0; k17 < 5; k17 = k17 + 1) begin
            hook_b[P20] = 1'b1; ms(10);
            dial_b(P20, 2);
            @(posedge t1k_b); hook_b[P20] = 1'b0;             // 1: one break,
            repeat (12) @(posedge t1k_b); hook_b[P20] = 1'b1; // ended on a tick
            repeat (14 + k17) @(posedge t1k_b);               // round the digit's end
            blip12 = 1'b1; repeat (10) @(posedge t1k_b);
            if (busy_b[T12] !== 1'b1) bad17 = bad17 + 1;      // B held the seizure
            blip12 = 1'b0;
            ms(30);
            if (busy_b[P21] !== 1'b1) bad17 = bad17 + 1;      // and connected 20 to 21
            hook_b[P20] = 1'b0;
            ms(150);
        end
        ck(bad17 == 0, "each time B held the seizure on B12 and connected B20 to B21");
        ck(clash == 0, "a connect and a hold in one frame: the unit waited out the word");
        idle_all("17: idle again");

        // ================= throughout ===========================================
        ck(clash == 0, "cable B never had two masters driving at once");
        ck(!mko_a && !mko_b && !uno_a && !uno_b, "no queue on either exchange refused a write");
        ck(ev_other == 0, "and no event but EV_NOTRUNK was sent");
        ck(trunk_tone == 0, "no trunk was ever given dial tone: no marker took a trunk's M as a call");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #60_000_000_000; $display("  TIMEOUT"); $fatal(1); end

    wire _unused = &{1'b0, rc_a, rc_b, t1k_b, sd_b, sc_b, wr_b, cla_b, hunt_a, hunt_b,
                     res_a, mon_a, dirs_b, gl_a, gl_b, nf_a, nf_b, up_b, 1'b0};
endmodule

// tb_lfull -- two exchanges, sixteen lines each, a local eight-channel trunk
// between them, and the trunk FILLED.  trunks.md §3; network.md §1, §4.1, §5.
//
// Exchange A is code 2 2 and exchange B is code 2 3, each top_net with phones
// on blocks 2 and 3 (20-27, 30-37) and tone sources at 01 and 03.  Their only
// link is a local trunk unit on block 1 of each, as tb_lnet's: A's faces east,
// B's faces west with glare.  B's crystal runs 100 ppm fast.
//
//   1  local     five two-digit calls at A at once, ten lines -- 31, 32, 33,
//                30 (a 0, ten pulses) and 25 on its own block -- each pair
//                hearing each other and no one else, and no trunk touched
//   2  eight     A20-A27 dial 1 2 3 3 0 ... 1 2 3 3 7: each key takes the
//                lowest free channel, A10 to A17 in turn, and all eight calls
//                stand at once, each carrying only its own pair both ways
//   3  ninth     A30 keys 1 and B20 keys 1: no channel free at either end,
//                cannot-complete, and EV_NOTRUNK on each cable B
//   4  a gap     channel 3's call hangs up; B20 dials 1 2 2 3 0.  B hunts from
//                the top and passes seven busy channels to take B13, and A30
//                rings
//   5  glare     channel 3 alone free, A31 and B21 key 1 together.  Retried
//                at later offsets until both ends seize the one channel; every
//                try that does not glare must end with one seizure and one
//                cannot-complete.  When they glare, each origin counts it and
//                takes the other's M as its claim, EV_GLARE goes out on both
//                cables B naming the channel, and the two callers -- who
//                dialled other people -- are joined to each other and nobody
//                rings (network.md §5: "the two callers are joined").
//                Neither end may also take the channel it seized as an
//                incoming call.
//
// Scenario 5 was red when it was written (2026-09-25): it found a defect in
// net_unit.v.  When the far end's M reached a channel before this end's own
// seizure write had made it BUSY, the classifier -- which did not know the
// origin had just taken that port -- held it as an incoming seizure, wrote it
// listening to 00 over the origin's latch, and attached a monitor.  The
// monitor counted the far caller's digits, B's own code, and claimed, and the
// busy register was refused: B21 heard A31, and A31 heard cannot-complete.
// The classifier now leaves alone any port the unit has seized itself (`mine`
// in net_unit.v).  faults.py F35 puts the old rule back, and "neither end also
// took..." and "A31 hears B21" go red.
//
// Timers scaled by 8 through the straps, as tb_net's.  Does not cover: a
// transit (tb_lchain), a cut during a call, or glare on a group with more
// than one channel free -- the word's g bit is what keeps that from happening,
// and scenario 5 is its one way through.
`timescale 1ns/1ps
`include "exch.vh"

module tb_lfull;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*72-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #(122.070 * 1.0001) clk_b = ~clk_b; end

    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};      // facing E, no glare
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};      // facing W, glare
    localparam [63:0] PH = 64'h0000_0000_FFFF_0000;         // 20-27, 30-37

    // ---- the two sites -------------------------------------------------------
    reg  [63:0] hook_a = 64'd0, tx_a = 64'd0, hook_b = 64'd0, tx_b = 64'd0;
    wire [63:0] rx_a, e_a, rx_b, e_b, busy_a, busy_b;
    wire [7:0]  lc_a, la_a, lh_a, lk_a, lc_b, la_b, lh_b, lk_b, lup_a, lup_b;
    wire        fs_a, fs_b, t1k_a, t1k_b, rc_a, rc_b;
    wire        sd_a, sc_a, wr_a, cl_a, sd_b, sc_b, wr_b, cl_b;
    wire        reg_a, reg_b, mko_a, mko_b, cla_a, cla_b, hunt_a, hunt_b, uno_a, uno_b;
    wire [2:0]  mks_a, mks_b;
    wire [3:0]  dirs_a, dirs_b;
    wire [1:0]  res_a, res_b, mon_a, mon_b;
    wire [7:0]  gl_a, gl_b, nf_a, nf_b;

    wire [7:0] lc_ai = {6'd0, lc_b[1], 1'b0}, la_ai = {6'd0, la_b[1], 1'b0};
    wire [7:0] lh_ai = {6'd0, lh_b[1], 1'b0}, lk_ai = {6'd0, lk_b[1], 1'b0};
    wire [7:0] lc_bi = {6'd0, lc_a[1], 1'b0}, la_bi = {6'd0, la_a[1], 1'b0};
    wire [7:0] lh_bi = {6'd0, lh_a[1], 1'b0}, lk_bi = {6'd0, lk_a[1], 1'b0};

`define SITE_PARAMS .PHONES(PH), .TRUNKS(64'd0), .OWN_E(3'd2), \
        .T_ARM(9'd2), .T_REL(9'd32), .RING_ON(13'd64), .RING_OFF(13'd128), \
        .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250), \
        .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250), .LTU(8'b0000_0010)

    site_net #(`SITE_PARAMS, .LTWORD({56'd0, WE, 8'd0}), .OWN_B(3'd2)) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0),
        .link_up(),
        .lt_c_out(lc_a), .lt_a_out(la_a), .lt_h_out(lh_a), .lt_k_out(lk_a),
        .lt_c_in(lc_ai), .lt_a_in(la_ai), .lt_h_in(lh_ai), .lt_k_in(lk_ai), .lt_up(lup_a),
        .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a), .port_busy(busy_a),
        .b_sdata(sd_a), .b_sclk(sc_a), .b_wr(wr_a), .b_clash(cl_a),
        .reg_busy(reg_a), .mk_state(mks_a), .mk_ovf(mko_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(hunt_a),
        .un_ovf(uno_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(`SITE_PARAMS, .LTWORD({56'd0, WW, 8'd0}), .OWN_B(3'd3)) B (
        .clk(clk_b), .rst_n(rst_n), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0),
        .link_up(),
        .lt_c_out(lc_b), .lt_a_out(la_b), .lt_h_out(lh_b), .lt_k_out(lk_b),
        .lt_c_in(lc_bi), .lt_a_in(la_bi), .lt_h_in(lh_bi), .lt_k_in(lk_bi), .lt_up(lup_b),
        .frame_stb(fs_b), .tick_1k(t1k_b), .ring_cad_n(rc_b), .port_busy(busy_b),
        .b_sdata(sd_b), .b_sclk(sc_b), .b_wr(wr_b), .b_clash(cl_b),
        .reg_busy(reg_b), .mk_state(mks_b), .mk_ovf(mko_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(hunt_b),
        .un_ovf(uno_b), .n_glare(gl_b), .n_nofwd(nf_b));

    // ---- a listener on each cable B: the event words -----------------------------
    // tb_net's: sixteen bits on SCLK, taken at WR; G = 0 is an event, SRC its
    // code and DST the port it names.
    reg [15:0] sh_a = 16'd0, sh_b = 16'd0;
    reg sc_a_d = 1'b0, wr_a_d = 1'b0, sc_b_d = 1'b0, wr_b_d = 1'b0;
    integer nt_a = 0, nt_b = 0, eg_a = 0, eg_b = 0, ev_other = 0;
    reg [`PW-1:0] egp_a = 6'd0, egp_b = 6'd0;
    always @(posedge clk_a) begin
        sc_a_d <= sc_a; wr_a_d <= wr_a;
        if (sc_a && !sc_a_d) sh_a <= {sh_a[14:0], sd_a};
        if (wr_a && !wr_a_d && !sh_a[15]) begin
            if      (sh_a[7:2] == 6'o10) nt_a = nt_a + 1;
            else if (sh_a[7:2] == 6'o04) begin eg_a = eg_a + 1; egp_a = sh_a[13:8]; end
            else                         ev_other = ev_other + 1;
        end
    end
    always @(posedge clk_b) begin
        sc_b_d <= sc_b; wr_b_d <= wr_b;
        if (sc_b && !sc_b_d) sh_b <= {sh_b[14:0], sd_b};
        if (wr_b && !wr_b_d && !sh_b[15]) begin
            if      (sh_b[7:2] == 6'o10) nt_b = nt_b + 1;
            else if (sh_b[7:2] == 6'o04) begin eg_b = eg_b + 1; egp_b = sh_b[13:8]; end
            else                         ev_other = ev_other + 1;
        end
    end

    // ---- a monitor at either end while a glare try is running --------------------
    // In glare each end holds the channel as an ORIGIN; neither may also take
    // it as an incoming seizure, hold it and count the far caller's digits.
    reg watch_m = 1'b0; integer m_seen = 0;
    always @(posedge clk_a) if (watch_m && (mon_a != 2'd0 || mon_b != 2'd0)) m_seen = m_seen + 1;

    integer clash = 0;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_b) if (cl_b) clash = clash + 1;

    // ---- the bench's hands -------------------------------------------------------
    // Each dial waits on the tick itself, not through ms(): scenario 5 dials
    // at both ends at once, and a static task entered twice shares its count.
    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask

    task dial_a(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; repeat (12) @(posedge t1k_a);
                hook_a[p] = 1'b1; repeat (8)  @(posedge t1k_a);
            end
            repeat (100) @(posedge t1k_a);
        end
    endtask
    task dial_b(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_b[p] = 1'b0; repeat (12) @(posedge t1k_a);
                hook_b[p] = 1'b1; repeat (8)  @(posedge t1k_a);
            end
            repeat (100) @(posedge t1k_a);
        end
    endtask
    task number_a(input [`PW-1:0] p, input [15:0] ds, input integer nd);  // ds: first digit in the top nibble
        integer q;
        begin for (q = 0; q < nd; q = q + 1) dial_a(p, ds[15 - 4*q -: 4]); end
    endtask
    task number_b(input [`PW-1:0] p, input [15:0] ds, input integer nd);
        integer q;
        begin for (q = 0; q < nd; q = q + 1) dial_b(p, ds[15 - 4*q -: 4]); end
    endtask

    // What is this port hearing?  01 a steady 1, 03 a steady 0.
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

    // Does this port ring within 250 ms?  A cadence is 64 on, 128 off, scaled.
    reg rang;
    task ring_a(input [`PW-1:0] p);
        integer i;
        begin rang = 1'b0;
            for (i = 0; i < 250; i = i + 1) begin @(posedge t1k_a); if (e_a[p]) rang = 1'b1; end
        end
    endtask
    task ring_b(input [`PW-1:0] p);
        integer i;
        begin rang = 1'b0;
            for (i = 0; i < 250; i = i + 1) begin @(posedge t1k_a); if (e_b[p]) rang = 1'b1; end
        end
    endtask

    task idle_all(input [8*72-1:0] what);
        begin
            ms(400);
            ck(busy_a == 64'd0 && busy_b == 64'd0 && !reg_a && !reg_b &&
               mks_a == 3'd0 && mks_b == 3'd0 && dirs_a == 4'd0 && dirs_b == 4'd0 &&
               res_a == 2'd0 && res_b == 2'd0 && mon_a == 2'd0 && mon_b == 2'd0, what);
        end
    endtask

    // ---- scenario 1's pairs: caller, called, and the number dialled --------------
    localparam [`PW-1:0] L0 = 6'o20, L1 = 6'o21, L2 = 6'o22, L3 = 6'o23, L4 = 6'o24;
    localparam [`PW-1:0] M0 = 6'o31, M1 = 6'o32, M2 = 6'o33, M3 = 6'o30, M4 = 6'o25;
    reg [`PW-1:0] lc [0:4], ld [0:4];
    reg [63:0]    lset;
    initial begin
        lc[0] = L0; ld[0] = M0; lc[1] = L1; ld[1] = M1; lc[2] = L2; ld[2] = M2;
        lc[3] = L3; ld[3] = M3; lc[4] = L4; ld[4] = M4;
    end

    integer k, n_ok, n_rang, try, off;
    reg     glared;
    integer g0a, g0b, e0a, e0b;
    reg [`PW-1:0] ch;

    initial begin
        $display("\n  tb_lfull -- sixteen lines a side, a local trunk, all eight channels at once");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(20);
        ck(lup_a[1] && lup_b[1] && busy_a[15:8] === 8'd0 && busy_b[15:8] === 8'd0,
           "the link is up and all sixteen channels are free");

        // ================= 1.  five local calls at once ==========================
        $display("  1. five two-digit calls at A, ten lines");
        n_rang = 0; lset = 64'd0;
        for (k = 0; k < 5; k = k + 1) begin
            hook_a[lc[k]] = 1'b1; ms(10);
            dial_a(lc[k], ld[k][5:3]); dial_a(lc[k], ld[k][2:0]); ms(20);
            ring_a(ld[k]); if (rang) n_rang = n_rang + 1;
            hook_a[ld[k]] = 1'b1; ms(20);
            lset[lc[k]] = 1'b1; lset[ld[k]] = 1'b1;
        end
        ck(n_rang == 5, "31, 32, 33, 30 and 25 each rang: two digits, a 0 among them");
        ck(busy_a[15:8] === 8'd0 && busy_b == 64'd0 && dirs_a == 4'd0,
           "and no channel was touched: five local calls flood nothing");
        n_ok = 0;
        for (k = 0; k < 5; k = k + 1) begin
            tx_a[lc[k]] = 1'b1; ms(4);
            if ((rx_a & lset) === (64'd1 << ld[k])) n_ok = n_ok + 1;
            tx_a[lc[k]] = 1'b0;
            tx_a[ld[k]] = 1'b1; ms(4);
            if ((rx_a & lset) === (64'd1 << lc[k])) n_ok = n_ok + 1;
            tx_a[ld[k]] = 1'b0; ms(4);
        end
        ck(n_ok == 10, "each of the ten lines is heard by its partner and by no one else");
        hook_a = 64'd0;
        idle_all("1: all five released, both exchanges idle");

        // ================= 2.  eight calls on eight channels ====================
        $display("  2. A20-A27 dial 1 2 3 3 k: eight calls across");
        n_ok = 0; n_rang = 0;
        for (k = 0; k < 8; k = k + 1) begin
            hook_a[6'o20 + k] = 1'b1; ms(10);
            dial_a(6'o20 + k, 1);
            if (busy_a[15:8] === ((9'd1 << (k + 1)) - 9'd1) && dirs_a == 4'b0100) n_ok = n_ok + 1;
            number_a(6'o20 + k, {4'd2, 4'd3, 4'd3, k[3:0]}, 4); ms(20);
            ring_b(6'o30 + k); if (rang) n_rang = n_rang + 1;
            hook_b[6'o30 + k] = 1'b1; ms(20);
        end
        ck(n_ok == 8, "each key took the lowest free channel, A10 to A17 in turn");
        ck(n_rang == 8, "and B30 to B37 each rang");
        ck(busy_a[15:8] === 8'hFF && busy_b[15:8] === 8'hFF, "all eight channels busy at both ends");
        ck(!reg_a && !reg_b && dirs_a == 4'd0 && res_b == 2'd0 && mon_b == 2'd0,
           "and eight calls stand with every register, origin and monitor free");
        n_ok = 0;
        for (k = 0; k < 8; k = k + 1) begin
            tx_a[6'o20 + k] = 1'b1; ms(4);
            if (rx_b[31:24] === (8'd1 << k)) n_ok = n_ok + 1;
            tx_a[6'o20 + k] = 1'b0;
            tx_b[6'o30 + k] = 1'b1; ms(4);
            if (rx_a[23:16] === (8'd1 << k)) n_ok = n_ok + 1;
            tx_b[6'o30 + k] = 1'b0; ms(4);
        end
        ck(n_ok == 16, "each call carries its own pair both ways, and no other channel's");

        // ================= 3.  a ninth call, from either end =====================
        $display("  3. A30 and B20 key 1 with no channel free");
        hook_a[6'o30] = 1'b1; ms(10);
        dial_a(6'o30, 1); ms(40);
        ck(dirs_a == 4'd0, "A's key seized nothing");
        hear_a(6'o30); ck(s0 && !s1, "A30 hears cannot-complete");
        ck(nt_a == 1, "and EV_NOTRUNK went out on A's cable B");
        hook_a[6'o30] = 1'b0;
        hook_b[6'o20] = 1'b1; ms(10);
        dial_b(6'o20, 1); ms(40);
        ck(dirs_b == 4'd0, "B's key seized nothing either");
        hear_b(6'o20); ck(s0 && !s1, "B20 hears cannot-complete");
        ck(nt_b == 1, "and EV_NOTRUNK went out on B's cable B");
        hook_b[6'o20] = 1'b0; ms(100);
        ck(busy_a[15:8] === 8'hFF && busy_b[15:8] === 8'hFF, "the eight calls stood through it");

        // ================= 4.  one channel comes free ==========================
        $display("  4. channel 3 hangs up; B20 dials 1 2 2 3 0");
        hook_a[6'o23] = 1'b0; hook_b[6'o33] = 1'b0; ms(150);
        ck(busy_a[15:8] === 8'hF7 && busy_b[15:8] === 8'hF7, "channel 3 alone is free at both ends");
        hook_b[6'o20] = 1'b1; ms(10);
        dial_b(6'o20, 1);
        ck(busy_b[15:8] === 8'hFF && dirs_b == 4'b1000,
           "B hunts from the top, passes 17 to 14, and takes B13");
        number_b(6'o20, {4'd2, 4'd2, 4'd3, 4'd0}, 4); ms(20);
        ring_a(6'o30); ck(rang, "A30 rings, on the one channel there was");
        hook_a[6'o30] = 1'b1; ms(20);
        tx_b[6'o20] = 1'b1; ms(4); ck(rx_a[6'o30] === 1'b1, "A30 hears B20");
        tx_b[6'o20] = 1'b0; ms(4); ck(rx_a[6'o30] === 1'b0, "and follows it");
        hook_a[6'o30] = 1'b0; hook_b[6'o20] = 1'b0; ms(150);
        ck(busy_a[15:8] === 8'hF7 && busy_b[15:8] === 8'hF7, "released: channel 3 free again");

        // ================= 5.  glare on the last channel ==========================
        $display("  5. A31 and B21 key 1 together, one channel free");
        glared = 1'b0; ch = 6'o13;
        for (try = 0; try < 8 && !glared; try = try + 1) begin
            off = try * 250_000;                             // B's key a quarter ms later a try
            g0a = gl_a; g0b = gl_b; e0a = eg_a; e0b = eg_b; m_seen = 0; watch_m = 1'b1;
            hook_a[6'o31] = 1'b1; hook_b[6'o21] = 1'b1; ms(10);
            fork
                dial_a(6'o31, 1);
                begin #(off); dial_b(6'o21, 1); end
            join
            if (gl_a != g0a[7:0] || gl_b != g0b[7:0]) begin
                glared = 1'b1;
                $display("     glare at try %0d, B's key %0d us after A's", try, off / 1000);
                ck(gl_a == g0a[7:0] + 8'd1 && gl_b == g0b[7:0] + 8'd1,
                   "glare: both origins seized channel 3 unseen, and each counted it");
                ck(cla_a === 1'b1 && cla_b === 1'b1,
                   "each took the other's M as its claim, inside its guard");
                ck(busy_a[15:8] === 8'hFF && dirs_a == 4'b0100 && dirs_b == 4'b1000,
                   "each holds the one channel");
                ms(10);
                ck(eg_a == e0a + 1 && eg_b == e0b + 1 && egp_a == ch && egp_b == ch,
                   "EV_GLARE went out on both cables B, naming channel 3");
                ck(m_seen == 0,
                   "neither end also took its own seized channel as an incoming call");
                // each dials someone who is not the other
                fork
                    number_a(6'o31, {4'd2, 4'd3, 4'd2, 4'd2}, 4);
                    number_b(6'o21, {4'd2, 4'd2, 4'd3, 4'd2}, 4);
                join
                ms(20);
                ck(!reg_a && !reg_b && dirs_a == 4'd0 && dirs_b == 4'd0,
                   "both origins finished: registers free, nothing held");
                fork ring_a(6'o32); ring_b(6'o22); join
                ck(!e_a[6'o32] && !e_b[6'o22] && !rang, "neither number dialled rang");
                tx_a[6'o31] = 1'b1; ms(4); ck(rx_b[6'o21] === 1'b1, "B21 hears A31");
                tx_a[6'o31] = 1'b0; ms(4); ck(rx_b[6'o21] === 1'b0, "and follows it");
                tx_b[6'o21] = 1'b1; ms(4); ck(rx_a[6'o31] === 1'b1,
                   "A31 hears B21: residual glare joins the two callers");
                tx_b[6'o21] = 1'b0; ms(4); ck(rx_a[6'o31] === 1'b0, "and follows it");
            end else begin
                // one end saw the other's seizure first: one call, one refusal
                ck((dirs_a != 4'd0) != (dirs_b != 4'd0),
                   "no glare: exactly one origin holds the channel, the other refused");
                if (dirs_a == 4'd0) begin hear_a(6'o31); ck(s0 && !s1, "the loser, A31, hears cannot-complete"); end
                else                begin hear_b(6'o21); ck(s0 && !s1, "the loser, B21, hears cannot-complete"); end
            end
            watch_m = 1'b0;
            hook_a[6'o31] = 1'b0; hook_b[6'o21] = 1'b0; ms(200);
            ck(busy_a[15:8] === 8'hF7 && busy_b[15:8] === 8'hF7 && !reg_a && !reg_b &&
               dirs_a == 4'd0 && dirs_b == 4'd0 && res_a == 2'd0 && res_b == 2'd0,
               "after the try, channel 3 is free again and nothing is held");
        end
        ck(glared, "glare was provoked");

        // ================= all down ================================================
        hook_a = 64'd0; hook_b = 64'd0;
        idle_all("every call released, both exchanges idle");
        ck(clash == 0, "cable B never had two masters driving at once");
        ck(ev_other == 0, "and no event but EV_NOTRUNK and EV_GLARE was sent");
        ck(!mko_a && !mko_b && !uno_a && !uno_b, "no queue on either exchange refused a write");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #60_000_000_000; $display("  TIMEOUT"); $fatal(1); end

    wire _unused = &{1'b0, rc_a, rc_b, fs_b, t1k_b, hunt_a, hunt_b, nf_a, nf_b,
                     lc_a, la_a, lh_a, lk_a, lc_b, la_b, lh_b, lk_b, 1'b0};
endmodule

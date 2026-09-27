// SKEPTIC C13 copy: +cdly=N delays C20's dialling N ms after A20's; +p0=1 runs pass 1 only.
// tb_pchain -- AUDIT (protocol slice).  Three exchanges in a chain, and two
// things that happen BETWEEN them.  Scratch; not part of the tree.
//
//     A 2 2  ==11,12,13==  11,12,13  B 2 3  14  ==11==  C 2 4
//            faces E         faces W, g       faces E    faces W, g
//
// Baseband cards.  B is a transit.  The B-C link has ONE channel, so it is
// always "the last free channel".  Timers scaled by 8 (tb_chain's); the
// sweeps, the reads and cable B are not.
//
//   +sc bit0  GLARE BETWEEN A FORWARD AND AN ORIGIN.  A20 dials 1 2 3 2 1 (B21);
//             C20 keys 1 at the moment B forwards A's flood into B14, so C's
//             origin and B's forwarder seize the one channel from its two ends
//             unseen.  Two calibration keys measure when each end writes; the
//             tries then aim C's key at B's forward write.  Hypotheses, once
//             they glare:
//               - C's origin takes B14's E (A20's hook) as its claim; B's
//                 resolver takes C11's E (C20's hook) as ITS leg's claim, and,
//                 the forward being one leg, frees itself -- so A's origin
//                 also sees a "claim" (C20's hook) and counts glare on A11,
//                 a channel that never glared
//               - B's own monitor then claims A20's call (b = 3 is B's): the
//                 claim drops the legs of the resolver holding B11 -- there is
//                 none any more -- so B14 is left listening to B11
//               - A20 reaches B21 as dialled; C20, who dialled 2 2 2 1, is
//                 connected to B14 and HEARS A20's side of that call
//   +sc bit1  A SEIZURE WITH NOTHING BEHIND IT.  The A conductor of the A11-B11
//             channel sticks at 1 into B (an open conductor on a fail-safe-high
//             receiver, a driver stuck on) while its fifth conductor runs, so
//             the link reads up.  Hypotheses: B holds B11 for good, a monitor
//             at B and one at C for good, B's resolver for good and B14/C11 for
//             good -- nothing in the unit times a monitor or a resolver out, and
//             no origin exists to drop the seizure.  C is then cut off (its one
//             channel is held at both ends).  At A the channel looks FREE (B's
//             hold sends no backward A), so A's key keeps taking A11, the lowest
//             free channel facing E, into a far end that is already BUSY: every
//             network call from A fails, even to B.  B's calls to A still work
//             (B hunts W from the top).  When the conductor is mended,
//             everything is released.
//
// Every ck() states the DESIGN INTENT; a FAIL is a reproduction.  OBS lines
// are observations.
`timescale 1ns/1ps
`include "exch.vh"

module tb_pchain;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*88-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, clk_c = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_b = ~clk_b; end
    initial begin #90; forever #122.070 clk_c = ~clk_c; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21, P22 = 6'o22;
    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, T13 = 6'o13, T14 = 6'o14;
    localparam [7:0] WE0 = {2'd2, 1'b0, 3'b010, 2'b11};     // facing E
    localparam [7:0] WW1 = {2'd3, 1'b1, 3'b010, 2'b11};     // facing W, glare
    localparam [511:0] TW_A = ({504'd0, WE0} << (8*T11)) | ({504'd0, WE0} << (8*T12)) |
                              ({504'd0, WE0} << (8*T13));
    localparam [511:0] TW_B = ({504'd0, WW1} << (8*T11)) | ({504'd0, WW1} << (8*T12)) |
                              ({504'd0, WW1} << (8*T13)) | ({504'd0, WE0} << (8*T14));
    localparam [511:0] TW_C = ({504'd0, WW1} << (8*T11));

    reg  [63:0] hook_a = 0, tx_a = 0, hook_b = 0, tx_b = 0, hook_c = 0, tx_c = 0;
    wire [63:0] rx_a, e_a, rx_b, e_b, rx_c, e_c, busy_a, busy_b, busy_c;
    wire [63:0] ac, aa, ak, bc, ba, bk, cc, ca, ck_o, up_a, up_b, up_c;
    reg  [63:0] ac_i, aa_i, ak_i, bc_i, ba_i, bk_i, cc_i, ca_i, ck_i;
    wire        fs_a, fs_b, fs_c, t1k_a, t1k_b, t1k_c, rc_a, rc_b, rc_c;
    wire        sd_a, sc_a, wr_a, cl_a, sd_b, sc_b, wr_b, cl_b, sd_c, sc_c, wr_c, cl_c;
    wire        reg_a, reg_b, reg_c, mo_a, mo_b, mo_c, cla_a, cla_b, cla_c;
    wire        hu_a, hu_b, hu_c, uo_a, uo_b, uo_c;
    wire [2:0]  ms_a, ms_b, ms_c;
    wire [3:0]  dirs_a, dirs_b, dirs_c;
    wire [1:0]  res_a, res_b, res_c, mon_a, mon_b, mon_c;
    wire [7:0]  gl_a, gl_b, gl_c, nf_a, nf_b, nf_c;

`define SITE_PARAMS \
        .T_ARM(9'd2), .T_REL(9'd32), .RING_ON(13'd64), .RING_OFF(13'd128), \
        .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250), \
        .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)
`define SITE_PINS(X, x) \
        .clk(clk_``x), .rst_n(rst_n), .hook(hook_``x), .tx(tx_``x), .rx(rx_``x), .e(e_``x), \
        .lt_c_in(8'd0), .lt_a_in(8'd0), .lt_h_in(8'd0), .lt_k_in(8'd0), \
        .frame_stb(fs_``x), .tick_1k(t1k_``x), .ring_cad_n(rc_``x), \
        .port_busy(busy_``x), .b_sdata(sd_``x), .b_sclk(sc_``x), .b_wr(wr_``x), .b_clash(cl_``x), \
        .reg_busy(reg_``x), .mk_state(ms_``x), .mk_ovf(mo_``x), .dirs_held(dirs_``x), \
        .res_busy(res_``x), .mon_held(mon_``x), .claimed(cla_``x), .hunting(hu_``x), \
        .un_ovf(uo_``x), .n_glare(gl_``x), .n_nofwd(nf_``x)

    site_net #(`SITE_PARAMS, .PHONES((64'd1 << P20) | (64'd1 << P21)),
               .TRUNKS((64'd1 << T11) | (64'd1 << T12) | (64'd1 << T13)), .TWORD(TW_A),
               .OWN_E(3'd2), .OWN_B(3'd2)) A (`SITE_PINS(A, a),
        .c_out(ac), .a_out(aa), .clk_out(ak), .c_in(ac_i), .a_in(aa_i), .clk_in(ak_i),
        .link_up(up_a));

    site_net #(`SITE_PARAMS, .PHONES((64'd1 << P20) | (64'd1 << P21) | (64'd1 << P22)),
               .TRUNKS((64'd1 << T11) | (64'd1 << T12) | (64'd1 << T13) | (64'd1 << T14)),
               .TWORD(TW_B), .OWN_E(3'd2), .OWN_B(3'd3)) B (`SITE_PINS(B, b),
        .c_out(bc), .a_out(ba), .clk_out(bk), .c_in(bc_i), .a_in(ba_i), .clk_in(bk_i),
        .link_up(up_b));

    site_net #(`SITE_PARAMS, .PHONES((64'd1 << P20) | (64'd1 << P21)),
               .TRUNKS(64'd1 << T11), .TWORD(TW_C),
               .OWN_E(3'd2), .OWN_B(3'd4)) C (`SITE_PINS(C, c),
        .c_out(cc), .a_out(ca), .clk_out(ck_o), .c_in(cc_i), .a_in(ca_i), .clk_in(ck_i),
        .link_up(up_c));

    // ---- the cables: A11-B11, A12-B12, A13-B13, B14-C11 ------------------------
    // stuck11: the A conductor from A's 11 into B's 11 reads 1 whatever A sends
    reg stuck11 = 1'b0;
    integer q;
    always @* begin
        ac_i = 0; aa_i = 0; ak_i = 0; bc_i = 0; ba_i = 0; bk_i = 0;
        cc_i = 0; ca_i = 0; ck_i = 0;
        for (q = 9; q <= 11; q = q + 1) begin           // 11, 12, 13 octal
            ac_i[q] = bc[q]; aa_i[q] = ba[q]; ak_i[q] = bk[q];
            bc_i[q] = ac[q]; ba_i[q] = aa[q]; bk_i[q] = ak[q];
        end
        ba_i[T11] = stuck11 || aa[T11];
        bc_i[T14] = cc[T11]; ba_i[T14] = ca[T11]; bk_i[T14] = ck_o[T11];
        cc_i[T11] = bc[T14]; ca_i[T11] = ba[T14]; ck_i[T11] = bk[T14];
    end

    integer clash = 0;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_b) if (cl_b) clash = clash + 1;
    always @(posedge clk_c) if (cl_c) clash = clash + 1;

    // ---- taps, to REPORT only ---------------------------------------------------
    wire [`PW-1:0] b14_src = B.u_x.u_exch.pos[1].u_blk.u_port4.addr;
    wire           b14_bsy = B.u_x.u_exch.pos[1].u_blk.u_port4.bsy;
    wire [`PW-1:0] b11_src = B.u_x.u_exch.pos[1].u_blk.u_port1.addr;
    wire           b11_clm = B.u_x.u_exch.pos[1].u_blk.u_port1.clm;
    wire [`PW-1:0] c11_src = C.u_x.u_exch.pos[1].u_blk.u_port1.addr;
    wire [`PW-1:0] c20_src = C.u_x.u_exch.pos[2].u_blk.u_port0.addr;
    wire [`PW-1:0] a20_src = A.u_x.u_exch.pos[2].u_blk.u_port0.addr;

    real tk_a, tk_c, t_b14, t_c11;
    reg  b14_d = 1'b0, c11_d = 1'b0;
    always @(posedge clk_b) begin b14_d <= busy_b[T14]; if (busy_b[T14] && !b14_d) t_b14 = $realtime; end
    always @(posedge clk_c) begin c11_d <= busy_c[T11]; if (busy_c[T11] && !c11_d) t_c11 = $realtime; end

    // ---- hands: one task an exchange, each waiting on its own ticks ------------
    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask
    task dial_a(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; repeat (12) @(posedge t1k_a);
                hook_a[p] = 1'b1; repeat (8)  @(posedge t1k_a);
            end
            repeat (100) @(posedge t1k_a);
        end
    endtask
    task dial_b(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_b[p] = 1'b0; repeat (12) @(posedge t1k_b);
                hook_b[p] = 1'b1; repeat (8)  @(posedge t1k_b);
            end
            repeat (100) @(posedge t1k_b);
        end
    endtask
    task dial_c(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_c[p] = 1'b0; repeat (12) @(posedge t1k_c);
                hook_c[p] = 1'b1; repeat (8)  @(posedge t1k_c);
            end
            repeat (100) @(posedge t1k_c);
        end
    endtask
    // a key alone: one 12 ms break, the make's start recorded
    task key_a; begin hook_a[P20] = 1'b0; #12_000_000; hook_a[P20] = 1'b1; tk_a = $realtime; end endtask
    task key_c; begin hook_c[P20] = 1'b0; #12_000_000; hook_c[P20] = 1'b1; tk_c = $realtime; end endtask

    integer j; reg s0, s1;
    task hear_c(input [`PW-1:0] p);
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 8; j = j + 1) begin
                @(posedge fs_c); @(posedge clk_c);
                if (rx_c[p]) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask
    task hear_a(input [`PW-1:0] p);
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 8; j = j + 1) begin
                @(posedge fs_a); @(posedge clk_a);
                if (rx_a[p]) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask

    task show(input [8*24-1:0] tag);
        $display("  OBS %0s: A dirs %b cla %0d glare %0d reg %0d | B mon %b res %b reg %0d nofwd %0d glare %0d B11->%0o clm %0d B14->%0o bsy %0d | C dirs %b cla %0d mon %b reg %0d glare %0d C11->%0o C20->%0o",
                 tag, dirs_a, cla_a, gl_a, reg_a, mon_b, res_b, reg_b, nf_b, gl_b, b11_src, b11_clm,
                 b14_src, b14_bsy, dirs_c, cla_c, mon_c, reg_c, gl_c, c11_src, c20_src);
    endtask

    task idle_all(input [8*88-1:0] what);
        begin
            ms(400);
            ck(busy_a == 0 && busy_b == 0 && busy_c == 0 && !reg_a && !reg_b && !reg_c &&
               dirs_a == 0 && dirs_b == 0 && dirs_c == 0 && res_b == 0 &&
               mon_a == 0 && mon_b == 0 && mon_c == 0, what);
            if (!(busy_a == 0 && busy_b == 0 && busy_c == 0)) $display("  OBS busy a %h b %h c %h", busy_a, busy_b, busy_c);
        end
    endtask


    // ---- +trace: every transition that matters to sc0, to REPORT --------------
    reg tron = 1'b0;
    initial if ($test$plusargs("trace")) tron = 1'b1;
    wire [3:0] a_nst = A.u_x.u_net.nst, c_nst = C.u_x.u_net.nst;
    wire [1:0] c_oaft = C.u_x.u_net.o_after, a_oaft = A.u_x.u_net.o_after;
    wire [2:0] b_mk = B.u_x.u_mk.state, c_mk = C.u_x.u_mk.state, a_mk = A.u_x.u_mk.state;
    wire [1:0] b_cl = B.u_x.u_net.cl_st, b_want = B.u_x.u_net.m_want, b_mheld = B.u_x.u_net.m_held;
    wire [1:0] b_rsb = B.u_x.u_net.rs_busy;
    wire [3:0] b_rsa = B.u_x.u_net.rs_act;
    wire [2:0] b_nd = B.u_x.u_mk.u_reg.ndig, c_nd = C.u_x.u_mk.u_reg.ndig, a_nd = A.u_x.u_mk.u_reg.ndig;
    wire [15:0] b_dg = B.u_x.u_mk.u_reg.digits;
    wire [`PW-1:0] a11_src = A.u_x.u_exch.pos[1].u_blk.u_port1.addr;
    wire [`PW-1:0] b21_src = B.u_x.u_exch.pos[2].u_blk.u_port1.addr;
    wire [3:0] b_mst = B.u_x.u_net.m_st;
    reg [3:0] a_nst_d, c_nst_d; reg [2:0] b_mk_d, c_mk_d, a_mk_d, b_nd_d, c_nd_d, a_nd_d;
    reg [1:0] b_cl_d, b_want_d, b_mheld_d, b_rsb_d; reg [3:0] b_rsa_d, b_mst_d;
    reg [`PW-1:0] a11_d, b11_d, b14_d2, c11_d2, c20_d, b21_d, a20_d;
    reg b11c_d, ma, mb14, mc11, mb11;
    always @(posedge clk_a) if (tron) begin
        a_nst_d <= a_nst; c_nst_d <= c_nst; b_mk_d <= b_mk; c_mk_d <= c_mk; a_mk_d <= a_mk;
        b_cl_d <= b_cl; b_want_d <= b_want; b_mheld_d <= b_mheld; b_rsb_d <= b_rsb; b_rsa_d <= b_rsa;
        b_nd_d <= b_nd; c_nd_d <= c_nd; a_nd_d <= a_nd; b_mst_d <= b_mst;
        a11_d <= a11_src; b11_d <= b11_src; b14_d2 <= b14_src; c11_d2 <= c11_src; c20_d <= c20_src;
        b21_d <= b21_src; a20_d <= a20_src; b11c_d <= b11_clm;
        mb11 <= ba_i[T11] ; mb14 <= ba_i[T14]; mc11 <= ca_i[T11];
        if (a_nst != a_nst_d) $display("  T %9.3f  A nst %0d -> %0d (after %0d)", $realtime/1e6, a_nst_d, a_nst, a_oaft);
        if (c_nst != c_nst_d) $display("  T %9.3f  C nst %0d -> %0d (after %0d, claimed %0d)", $realtime/1e6, c_nst_d, c_nst, c_oaft, cla_c);
        if (a_mk != a_mk_d) $display("  T %9.3f  A mk %0d -> %0d", $realtime/1e6, a_mk_d, a_mk);
        if (b_mk != b_mk_d) $display("  T %9.3f  B mk %0d -> %0d", $realtime/1e6, b_mk_d, b_mk);
        if (c_mk != c_mk_d) $display("  T %9.3f  C mk %0d -> %0d", $realtime/1e6, c_mk_d, c_mk);
        if (b_cl != b_cl_d) $display("  T %9.3f  B cl_st %0d -> %0d", $realtime/1e6, b_cl_d, b_cl);
        if (b_want != b_want_d || b_mheld != b_mheld_d || b_mst != b_mst_d)
            $display("  T %9.3f  B mon held %b want %b st %h", $realtime/1e6, b_mheld, b_want, b_mst);
        if (b_rsb != b_rsb_d || b_rsa != b_rsa_d) $display("  T %9.3f  B rs busy %b act %h", $realtime/1e6, b_rsb, b_rsa);
        if (a_nd != a_nd_d) $display("  T %9.3f  A reg ndig %0d", $realtime/1e6, a_nd);
        if (b_nd != b_nd_d) $display("  T %9.3f  B reg ndig %0d digits %h", $realtime/1e6, b_nd, b_dg);
        if (c_nd != c_nd_d) $display("  T %9.3f  C reg ndig %0d", $realtime/1e6, c_nd);
        if (a11_src != a11_d) $display("  T %9.3f  A11 -> %0o", $realtime/1e6, a11_src);
        if (a20_src != a20_d) $display("  T %9.3f  A20 -> %0o", $realtime/1e6, a20_src);
        if (b11_src != b11_d || b11_clm != b11c_d) $display("  T %9.3f  B11 -> %0o clm %0d", $realtime/1e6, b11_src, b11_clm);
        if (b14_src != b14_d2) $display("  T %9.3f  B14 -> %0o", $realtime/1e6, b14_src);
        if (b21_src != b21_d) $display("  T %9.3f  B21 -> %0o", $realtime/1e6, b21_src);
        if (c11_src != c11_d2) $display("  T %9.3f  C11 -> %0o", $realtime/1e6, c11_src);
        if (c20_src != c20_d) $display("  T %9.3f  C20 -> %0o", $realtime/1e6, c20_src);
        if (mb11 != ba_i[T11]) $display("  T %9.3f  M at B11 %0d", $realtime/1e6, ba_i[T11]);
        if (mb14 != ba_i[T14]) $display("  T %9.3f  M at B14 %0d", $realtime/1e6, ba_i[T14]);
        if (mc11 != ca_i[T11]) $display("  T %9.3f  M at C11 %0d", $realtime/1e6, ca_i[T11]);
    end

    integer sc, try, d, g0a, g0c, pass, late, cdly, p0;
    real    calA, calC, off;
    reg     glared;

    initial begin
        if (!$value$plusargs("sc=%d", sc)) sc = 3;
        if (!$value$plusargs("cdly=%d", cdly)) cdly = 0;   // SKEPTIC: C20 dials cdly ms after A20
        if (!$value$plusargs("p0=%d", p0)) p0 = 0;         // SKEPTIC: first pass to run
        $display("\n  tb_pchain -- three exchanges; glare on a forward, and a seizure with no origin.  sc=%0d", sc);
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(20);
        ck(up_a[T11] && up_a[T13] && up_b[T14] && up_c[T11], "all links up");

        // ======================================================================
        if (sc[0]) begin
            $display("  --- sc0: a forward and an origin glare on B14-C11");
            // calibration: when does B write its forward, after A's key?
            hook_a[P20] = 1'b1; ms(10);
            t_b14 = 0.0; key_a; ms(80);
            calA = t_b14 - tk_a;
            $display("  OBS calibration: B14 written %0.3f ms after A's key", calA / 1.0e6);
            hook_a[P20] = 1'b0; ms(250);
            // ... and when does C write its seizure, after C's key?
            hook_c[P20] = 1'b1; ms(10);
            t_c11 = 0.0; key_c; ms(80);
            calC = t_c11 - tk_c;
            $display("  OBS calibration: C11 written %0.3f ms after C's key", calC / 1.0e6);
            hook_c[P20] = 1'b0; ms(250);
            ck(busy_b == 0 && busy_c == 0 && res_b == 0, "calibration: idle again");

            for (pass = p0; pass < 2; pass = pass + 1) begin
            // pass 0: the callers dial on 40 ms after C's key -- C20's first
            //   break falls inside C's (scale-8, 16 ms) guard, so C abandons:
            //   what does the glare partner's departure do to A's call?
            // pass 1: they dial on 80 ms after it, outside every guard.
            late = (pass == 0) ? 0 : 40;
            $display("  --- sc0 pass %0d: the callers dial on %0d ms after C's key", pass, 40 + late);
            glared = 1'b0;
            for (try = 0; try < 17 && !glared; try = try + 1) begin
                d = (try + 1) / 2; if (try % 2) d = -d;       // 0, -1, 1, -2, 2, ...
                off = (calA - calC) + d * 250_000.0;          // quarter-millisecond steps
                g0a = gl_a; g0c = gl_c;
                hook_a[P20] = 1'b1; hook_c[P20] = 1'b1; ms(10);
                fork
                    key_a;
                    begin #(off); key_c; end
                join
                ms(40);
                if (cla_c && dirs_c != 0) begin
                    glared = 1'b1;
                    $display("  OBS glare at try %0d: C's key %0.3f ms after A's", try, (tk_c - tk_a) / 1.0e6);
                    show("at the glare");
                    $display("  OBS glare between B's forward and C's origin on the one channel (documented residual glare)");
                    ck(gl_a == g0a[7:0], "A counts no glare: A11 was never seized from both ends");
                    // both callers dial on: A20 the number it wants, C20 22-21
                    ms(late);
                    fork
                        begin dial_a(P20, 2); dial_a(P20, 3); dial_a(P20, 2); dial_a(P20, 1); end
                        begin ms(cdly); $display("  T %9.3f  SKEPTIC: C20 starts dialling (cdly %0d ms)", $realtime/1e6, cdly); dial_c(P20, 2); dial_c(P20, 2); dial_c(P20, 2); dial_c(P20, 1); end
                    join
                    ms(20);
                    show("after dialling");
                    $display("  OBS after dialling: A20 -> %0o, A11 -> %0o busy %0d, B21 -> %0o", a20_src, a11_src, busy_a[T11], b21_src);
                    ck(busy_b[P21] === 1'b1, "A20 reached B21, as dialled");
                    ck(busy_a[P21] === 1'b0, "A21 (C20's number) is not rung: C20's call went nowhere");
                    hook_b[P21] = 1'b1; ms(20);
                    tx_a[P20] = 1'b1; ms(4);
                    $display("  OBS A20 sends 1: B21 hears %0d, C20 hears %0d", rx_b[P21], rx_c[P20]);
                    ck(rx_b[P21] === 1'b1, "B21 hears A20");
                    hear_c(P20);
                    ck(!(s1 && !s0), "C20 does NOT hear A20 (no listen-in on a stranger's call)");
                    tx_a[P20] = 1'b0; ms(4);
                    hear_c(P20);
                    $display("  OBS A20 sends 0: C20 hears %0d%0d (s1 s0)", s1, s0);
                    tx_b[P21] = 1'b1; ms(4);
                    ck(rx_a[P20] === 1'b1, "A20 hears B21");
                    tx_b[P21] = 1'b0; ms(4);
                    hook_a[P20] = 1'b0; hook_b[P21] = 1'b0; hook_c[P20] = 1'b0;
                end else begin
                    $display("  OBS try %0d (C's key %0.3f ms after A's): no glare; A dirs %b, C dirs %b, B nofwd %0d",
                             try, (tk_c - tk_a) / 1.0e6, dirs_a, dirs_c, nf_b);
                    hook_a[P20] = 1'b0; hook_c[P20] = 1'b0;
                end
                ms(250);
            end
            if (!glared) $display("  OBS no glare in 17 tries");
            idle_all("sc0: all three idle again");
            end
        end

        // ======================================================================
        if (sc[1]) begin
            $display("  --- sc1: the A conductor into B11 sticks at 1");
            stuck11 = 1'b1;
            ms(100);
            show("100 ms after");
            ms(1000);
            show("1.1 s after (8.8 s real)");
            ck(mon_b == 0 && mon_c == 0 && res_b == 0,
               "a seizure nobody dials on does not hold a monitor or a resolver for good");
            ck(busy_b[T14] === 1'b0 && busy_c[T11] === 1'b0,
               "nor the B-C channel");
            // C: its one channel is held at both ends
            hook_c[P20] = 1'b1; ms(10);
            dial_c(P20, 1); ms(20);
            hear_c(P20);
            $display("  OBS C20 keys 1: C dirs %b, hears s1 %0d s0 %0d", dirs_c, s1, s0);
            ck(dirs_c != 0, "C can still reach the network");
            hook_c[P20] = 1'b0; ms(100);
            // A: its key takes A11, free at A, BUSY at B
            hook_a[P20] = 1'b1; ms(10);
            dial_a(P20, 1);
            $display("  OBS A20 keys 1: A dirs %b, A11 busy %0d A12 busy %0d", dirs_a, busy_a[T11], busy_a[T12]);
            dial_a(P20, 2); dial_a(P20, 3);          // B's own code
            ms(300);
            hear_a(P20);
            $display("  OBS A20 dialled B: A claimed %0d, hears s1 %0d s0 %0d, B reg %0d", cla_a, s1, s0, reg_b);
            ck(cla_a, "A20 can still reach its neighbour B");
            hook_a[P20] = 1'b0; ms(100);
            // B to A: B hunts W from the top and takes B13
            hook_b[P20] = 1'b1; ms(10);
            dial_b(P20, 1); dial_b(P20, 2); dial_b(P20, 2);
            $display("  OBS B20 dialled A: B dirs %b claimed %0d, A reg %0d", dirs_b, cla_b, reg_a);
            ck(cla_b, "B20 reaches A (B's glare order takes B13, whose far end is sound)");
            hook_b[P20] = 1'b0; ms(100);
            // the conductor mended
            stuck11 = 1'b0;
            ms(200);
            show("mended, 200 ms after");
            idle_all("sc1: mended -- everything released");
            // and C is reachable again
            hook_a[P20] = 1'b1; ms(10);
            dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 4);
            ck(cla_a && reg_c, "after the mend A20 reaches C again");
            hook_a[P20] = 1'b0;
            idle_all("sc1: idle at the end");
        end

        ck(clash == 0, "no cable B had two masters driving at once");
        ck(!mo_a && !mo_b && !mo_c && !uo_a && !uo_b && !uo_c, "no queue refused a write");
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #60_000_000_000; $display("  TIMEOUT"); $finish; end

    wire _unused = &{1'b0, rc_a, rc_b, rc_c, t1k_b, t1k_c, fs_b, sd_a, sc_a, wr_a, sd_b, sc_b, wr_b,
                     sd_c, sc_c, wr_c, ms_a, ms_b, ms_c, hu_a, hu_b, hu_c, res_a, res_c,
                     gl_b, nf_a, nf_c, e_a, e_b, e_c, up_b, a20_src, 1'b0};
endmodule

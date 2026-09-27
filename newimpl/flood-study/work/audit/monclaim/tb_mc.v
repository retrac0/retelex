// tb_mc -- AUDIT scratch bench (monitors and the claim).  Not part of the tree.
//
// ONE exchange X, code 1 3 (OWN_E 1, OWN_B 3), phones 20-27, tone sources 01
// and 03, and seven baseband trunk cards whose far ends are the BENCH: the
// bench drives each card's rear A (far_m -- what the far exchange's port puts
// on the wire, i.e. M at X's port) and loops its fifth conductor so the link
// is up.  a_out is X's backward A on that trunk (E + CLAIM); c_out is what X's
// trunk port listens to, so 03's steady 0 is cannot-complete.
//   T11-T15 face W (incoming, from the bench); T16, T17 face E (forward legs,
//   far ends idle).
//
// +sc=N runs one scenario (0 = all, in order):
//   1  STALE CELL.  A 0.9 ms seizure on T11 (shorter than T_ARM), then T11
//      seized again 20 ms later (inside CLR) and the far caller dials
//      3 2 2 1 -- exchange 32's line 21, NOT this exchange.  Correct: no claim
//      here, nothing rings.  Hypothesis: the cell given to the blip is still
//      held, counts the blip's death as one pulse and the re-seizure's make as
//      the end of a digit -- e = 1, ours -- then hears 3 as b, ours, and
//      claims; the register reads 2 2 and X22 rings: a wrong number.
//   2  BURST.  T11-T15 seized in the same millisecond; every far caller dials
//      1 3 (this exchange) then 2 k.  Measures the classifier's rate (rise ->
//      BUSY per trunk), who gets a monitor (NMON = 2), who is forwarded, the
//      two claims (one register: first taken, second refused to 03), the
//      unwatched three (no claim ever: their origins would wait T_CLAIM), and
//      that everything is released when the far ends drop.
//   3  STALE CELLS STARVE.  Blips on T13 and T14, then a real seizure on T15
//      12 ms later, dialling 1 3 2 5: both cells are stale, T15 is unwatched
//      for good and never claimed although it dialled this exchange.
//   4  CONTROL.  A clean seizure on T12, 1 3 2 4: claimed, X24 rings.
//
// Timers scaled by 8 as the tree's network benches.
`timescale 1ns/1ps
`include "exch.vh"

module tb_mc;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*80-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, T13 = 6'o13, T14 = 6'o14, T15 = 6'o15,
                         T16 = 6'o16, T17 = 6'o17;
`ifdef CODE42
    localparam integer CE = 4, CB = 2;
`else
    localparam integer CE = 1, CB = 3;
`endif
`ifdef REAL
    // real timers: the board's taps, a dial at 10 pps 60/40, 800 ms between digits
    localparam [8:0]  P_TARM = 9'd16, P_TREL = 9'd256, P_HIT = 9'd8, P_ID = 9'd128, P_CLR = 9'd256;
    localparam [12:0] P_RON = 13'd2048, P_ROFF = 13'd4096;
    localparam [15:0] P_NODIG = 16'd10000, P_GUARD = 16'd128, P_TKEY = 16'd5000, P_TCLAIM = 16'd2000;
    localparam integer BRK = 60, MK = 40, PAUSE = 800;
    localparam integer GAP = 100, FIRST = 400, FAST = 115, STAG = 25, HOLDW = 200, IDLEW = 700;
`else
    localparam [8:0]  P_TARM = 9'd2, P_TREL = 9'd32, P_HIT = 9'd1, P_ID = 9'd16, P_CLR = 9'd32;
    localparam [12:0] P_RON = 13'd64, P_ROFF = 13'd128;
    localparam [15:0] P_NODIG = 16'd1250, P_GUARD = 16'd16, P_TKEY = 16'd625, P_TCLAIM = 16'd250;
    localparam integer BRK = 12, MK = 8, PAUSE = 100;
    localparam integer GAP = 20, FIRST = 60, FAST = 14, STAG = 6, HOLDW = 80, IDLEW = 200;
`endif
    localparam [7:0] WW = {2'd3, 1'b0, 3'b010, 2'b11};      // facing W
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};      // facing E
    localparam [63:0] TR = (64'd1 << T11) | (64'd1 << T12) | (64'd1 << T13) | (64'd1 << T14) |
                           (64'd1 << T15) | (64'd1 << T16) | (64'd1 << T17);
    localparam [511:0] TW = ({504'd0, WW} << (8*T11)) | ({504'd0, WW} << (8*T12)) |
                            ({504'd0, WW} << (8*T13)) | ({504'd0, WW} << (8*T14)) |
                            ({504'd0, WW} << (8*T15)) |
                            ({504'd0, WE} << (8*T16)) | ({504'd0, WE} << (8*T17));

    reg  [63:0] hook = 64'd0, tx = 64'd0, far_m = 64'd0;
    wire [63:0] rx, e, busy, c_out, a_out, k_out, up;
    wire        fs, t1k, rc, sd, sc, wr, cl, rg, mko, cla, hunt, uno;
    wire [2:0]  mks;
    wire [3:0]  dirs;
    wire [1:0]  res, mon;
    wire [7:0]  ngl, nnf;
    wire [7:0]  lz8 = 8'd0;

    site_net #(.PHONES(64'h0000_0000_00FF_0000), .TRUNKS(TR), .TWORD(TW),
               .OWN_E(CE[2:0]), .OWN_B(CB[2:0]),
               .T_ARM(P_TARM), .T_REL(P_TREL), .RING_ON(P_RON), .RING_OFF(P_ROFF),
               .HIT(P_HIT), .ID(P_ID), .CLR(P_CLR), .NODIG(P_NODIG),
               .T_GUARD0(P_GUARD), .T_KEY(P_TKEY), .T_CLAIM(P_TCLAIM)) X (
        .clk(clk), .rst_n(rst_n), .hook(hook), .tx(tx), .rx(rx), .e(e),
        .c_out(c_out), .a_out(a_out), .clk_out(k_out),
        .c_in(64'd0), .a_in(far_m & TR), .clk_in(k_out & TR), .link_up(up),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(lz8), .lt_a_in(lz8), .lt_h_in(lz8), .lt_k_in(lz8), .lt_up(),
        .frame_stb(fs), .tick_1k(t1k), .ring_cad_n(rc), .port_busy(busy),
        .b_sdata(sd), .b_sclk(sc), .b_wr(wr), .b_clash(cl),
        .reg_busy(rg), .mk_state(mks), .mk_ovf(mko), .dirs_held(dirs),
        .res_busy(res), .mon_held(mon), .claimed(cla), .hunting(hunt),
        .un_ovf(uno), .n_glare(ngl), .n_nofwd(nnf));

    // ---- time in ms, and a trace of everything this slice cares about --------
    integer now = 0;
    always @(posedge t1k) now = now + 1;

    wire [1:0]  m_held  = X.u_x.u_net.m_held;
    wire [1:0]  m_armed = X.u_x.u_net.m_armed;
    wire [1:0]  m_want  = X.u_x.u_net.m_want;
    wire [11:0] m_port  = X.u_x.u_net.m_port;
    wire [3:0]  m_st    = X.u_x.u_net.m_st;
    wire [7:0]  d_cnt   = X.u_x.u_net.d_cnt;
    wire [1:0]  cl_st   = X.u_x.u_net.cl_st;
    wire        att     = X.u_x.u_net.att;
    wire [5:0]  att_pt  = X.u_x.u_net.att_port;
    wire [2:0]  cst     = X.u_x.u_net.cst;
    wire [1:0]  fst     = X.u_x.u_net.fst;
    wire [5:0]  f_in    = X.u_x.u_net.f_in;
    wire [11:0] rs_in   = X.u_x.u_net.rs_in;
    wire [5:0]  r_port  = X.u_x.u_net.r_port;
    wire [2:0]  r_ndig  = X.u_x.u_net.r_ndig;
    wire [15:0] r_dig   = X.u_x.u_net.r_digits;

    reg [127:0] tr_d = 128'd0;
    wire [127:0] tr = {busy[15:9], a_out[15:9], m_held, m_armed, m_want, m_port, m_st,
                       cl_st, att, att_pt, fst, f_in, res, rs_in, rg, mks, r_port, r_ndig,
                       cst, dirs, e[23:16] & ~{8{rc}}};
    integer tq;
    always @(posedge clk) begin
        tr_d <= tr;
        if (rst_n && tr != tr_d) begin
            $write("  [%5d ms] busy1x=%b bkA=%b | cells held=%b armed=%b want=%b port=%o/%o st=%0d/%0d cnt=%0d/%0d",
                   now, busy[15:9], a_out[15:9], m_held, m_armed, m_want,
                   m_port[11:6], m_port[5:0], m_st[3:2], m_st[1:0], d_cnt[7:4], d_cnt[3:0]);
            $write(" | cl=%0d att=%b@%o | fwd=%0d in=%o res=%b in=%o/%o",
                   cl_st, att, att_pt, fst, f_in, res, rs_in[11:6], rs_in[5:0]);
            $display(" | reg=%b mk=%0d on=%o nd=%0d dig=%h | cls=%0d dirs=%b nofwd=%0d ring2x=%b",
                   rg, mks, r_port, r_ndig, r_dig, cst, dirs, nnf, e[23:16] & ~{8{rc}});
        end
    end

    integer clash = 0;
    always @(posedge clk) if (cl) clash = clash + 1;

    // ---- the bench's hands ---------------------------------------------------
    task ms(input integer n); begin repeat (n) @(posedge t1k); end endtask

    // the far caller, as the far port puts it on the wire: 12/8 ms, 100 ms pause
    task automatic fdial(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                far_m[p] = 1'b0; ms(BRK);
                far_m[p] = 1'b1; ms(MK);
            end
            ms(PAUSE);
        end
    endtask
    // several far callers dialling the same digit in lock step
    task automatic fdial_n(input [63:0] ps, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                far_m = far_m & ~ps; ms(BRK);
                far_m = far_m | ps;  ms(MK);
            end
            ms(PAUSE);
        end
    endtask

    // which phones ring over 300 ms: a port whose E is chopped by the cadence
    integer hi [0:63]; integer lo [0:63];
    integer rp, ri;
    reg [63:0] ringing;
    task rings;
        begin
            for (rp = 0; rp < 64; rp = rp + 1) begin hi[rp] = 0; lo[rp] = 0; end
            for (ri = 0; ri < 300; ri = ri + 1) begin
                @(posedge t1k);
                for (rp = 16; rp < 24; rp = rp + 1)
                    if (e[rp]) hi[rp] = hi[rp] + 1; else lo[rp] = lo[rp] + 1;
            end
            ringing = 64'd0;
            for (rp = 16; rp < 24; rp = rp + 1)
                if (busy[rp] && !hook[rp]) ringing[rp] = 1'b1;   // written BUSY toward a caller: connected, ringing
        end
    endtask

    // what X sends the far end on trunk p: 03 is a steady 0, 01 a steady 1
    integer j; reg s0, s1;
    task hear(input [`PW-1:0] p);
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 16; j = j + 1) begin
                @(posedge fs); @(posedge clk);
                if (c_out[p]) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask

    task idle(input [8*80-1:0] what);
        begin
            ms(IDLEW);
            ck(busy[63:0] == 64'd0 && !rg && mks == 3'd0 && dirs == 4'd0 && res == 2'd0 &&
               m_held == 2'd0 && cl_st == 2'd0 && !att && fst == 2'd0 && cst == 3'd0, what);
        end
    endtask

    // time a port first reads BUSY after a mark
    integer tb_busy [0:63];
    integer mark = 0, q;
    reg arm_bt = 1'b0;
    always @(posedge clk) if (arm_bt)
        for (q = 9; q < 16; q = q + 1)
            if (busy[q] && tb_busy[q] < 0) tb_busy[q] = now - mark;

    integer sc_sel, k, n_cl, t_b, t_att, t_reg;
    reg [63:0] ps;
    initial begin
        if (!$value$plusargs("sc=%d", sc_sel)) sc_sel = 0;
        $display("\n  tb_mc -- monitors and the claim, exchange %0d%0d, far ends driven by the bench (sc=%0d)", CE, CB, sc_sel);
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        ms(20);
        ck(up[T11] && up[T15] && up[T16] && up[T17], "every trunk's link is up");

        // ======================================================================
        if (sc_sel == 0 || sc_sel == 4) begin
            $display("\n  4. CONTROL: clean seizure on T12, far dials 1 3 2 4");
            far_m[T12] = 1'b1; ms(FIRST);
            ck(busy[T12] === 1'b1, "T12 held");
            fdial(T12, CE); fdial(T12, CB);
            ck(a_out[T12] === 1'b1, "claimed: backward A on T12");
            fdial(T12, 2); fdial(T12, 4); ms(10);
            rings;
            ck(ringing == (64'd1 << 6'o24), "X24 rings, and nothing else");
            far_m[T12] = 1'b0;
            idle("4: idle again");
        end

        // ======================================================================
        if (sc_sel == 0 || sc_sel == 1) begin
            $display("\n  1. STALE CELL: 0.9 ms blip on T11, re-seized 20 ms later, far dials 3 2 2 1");
            @(posedge t1k); far_m[T11] = 1'b1; #900_000; far_m[T11] = 1'b0;
            ms(GAP);
            ck(busy[T11] === 1'b0, "the blip's hold was written away (C_UNHOLD)");
            ck((m_held[0] && m_port[5:0] == T11) || (m_held[1] && m_port[11:6] == T11),
               "but a cell given to the blip is still held on T11");
            far_m[T11] = 1'b1;                            // a NEW seizure
            ms(8);
            ck(m_held == 2'b11 && m_port[5:0] == T11 && m_port[11:6] == T11,
               "OBSERVE: two cells now watch T11");
            ms(FIRST - 8);
            fdial(T11, 3);                                // e = 3: exchange 3x
            ck(a_out[T11] === 1'b0, "SAFETY: X (13) did not claim a call dialled to 3x");
            ck(!rg, "SAFETY: X's register was not attached to T11");
            fdial(T11, 2); fdial(T11, 2); fdial(T11, 1); ms(10);
            rings;
            ck(ringing == 64'd0, "SAFETY: no phone at X rings for a call to exchange 32");
            $display("    ringing = %h (X22 is bit %0d)", ringing, 6'o22);
            far_m[T11] = 1'b0;
            idle("1: idle again");
        end

        // ======================================================================
        if (sc_sel == 0 || sc_sel == 3) begin
            $display("\n  3. STALE CELLS STARVE: blips on T13 and T14, then T15 seized and dials 1 3 2 5");
            @(posedge t1k); far_m[T13] = 1'b1; #900_000; far_m[T13] = 1'b0;
            ms(STAG);
            @(posedge t1k); far_m[T14] = 1'b1; #900_000; far_m[T14] = 1'b0;
            ms(STAG);
            ck(m_held == 2'b11, "OBSERVE: both cells held by the blips");
            far_m[T15] = 1'b1; ms(FIRST);
            ck(busy[T15] === 1'b1, "T15 held");
            fdial(T15, CE); fdial(T15, CB);
            ck(a_out[T15] === 1'b1, "LIVENESS: X claims a call dialled to it (1 3) on T15");
            fdial(T15, 2); fdial(T15, 5); ms(10);
            rings;
            ck(ringing == (64'd1 << 6'o25), "X25 rings");
            far_m[T15] = 1'b0;
            idle("3: idle again");
        end

        // ======================================================================
        if (sc_sel == 0 || sc_sel == 2) begin
            $display("\n  2. BURST: T11-T15 seized in one millisecond; each far caller dials 1 3 2 k");
            ps = (64'd1 << T11) | (64'd1 << T12) | (64'd1 << T13) | (64'd1 << T14) | (64'd1 << T15);
            for (q = 0; q < 64; q = q + 1) tb_busy[q] = -1;
            @(posedge t1k); mark = now; arm_bt = 1'b1;
            far_m = far_m | ps;
            ms(HOLDW);
            arm_bt = 1'b0;
            for (q = 9; q < 14; q = q + 1)
                $display("    T1%0d: BUSY %0d ms after its rise", q - 8, tb_busy[q]);
            ck(busy[13:9] == 5'b11111, "all five held");
            $display("    cells: held=%b ports %o/%o; forwards not passed on (n_nofwd) = %0d",
                     m_held, m_port[11:6], m_port[5:0], nnf);
            fdial_n(ps, CE);
            fdial_n(ps, CB);
            ms(20);
            n_cl = 0;
            for (q = 9; q < 14; q = q + 1) if (a_out[q]) n_cl = n_cl + 1;
            $display("    backward A after b: %b (T15..T11)", a_out[13:9]);
            ck(n_cl == 2, "OBSERVE: exactly two claims -- one a cell; three unwatched");
            // the second digit of the number differs per trunk
            fork
                fdial(T11, 2); fdial(T12, 2); fdial(T13, 2); fdial(T14, 2); fdial(T15, 2);
            join
            fork
                fdial(T11, 1); fdial(T12, 2); fdial(T13, 3); fdial(T14, 4); fdial(T15, 5);
            join
            ms(10);
            rings;
            $display("    ringing = %h", ringing);
            ck(ringing == (64'd1 << 6'o21), "the first claim's line (X21) rings, and only it");
            hear(T12);
            ck(s0 && !s1 && a_out[T12], "the second claim was refused: T12 claimed and listening to 03");
            for (q = 11; q < 14; q = q + 1)
                $display("    T1%0d unwatched: backward A=%b, still held=%b", q - 8, a_out[q], busy[q]);
            far_m = far_m & ~ps;
            idle("2: every trunk, cell, resolver and the register released");
        end

        // ======================================================================
        if (sc_sel == 5) begin
            $display("\n  5. STALE CELL, FAST CALLER: blip on T11, re-seized 20 ms later, far dials 3 2 2 1");
            $display("     with the first break of e 14 ms after the re-seizure (inside ID, outside the guard)");
            @(posedge t1k); far_m[T11] = 1'b1; #900_000; far_m[T11] = 1'b0;
            ms(GAP);
            far_m[T11] = 1'b1;                            // a NEW seizure
            ms(FAST);
            fdial(T11, 3);                                // e = 3: exchange 3x
            fdial(T11, 2);                                // b = 2
            ck(a_out[T11] === 1'b0, "SAFETY: X did not claim a call dialled to 32");
            ck(!rg, "SAFETY: X's register was not attached to T11");
            fdial(T11, 2); fdial(T11, 1); ms(10);
            rings;
            $display("    ringing = %h", ringing);
            ck(ringing == 64'd0, "SAFETY: no phone at X rings for a call to exchange 32");
            far_m[T11] = 1'b0;
            idle("5: idle again");
        end

        ck(clash == 0, "cable B never had two masters at once");
        ck(!mko && !uno, "no queue refused a write");
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #90_000_000_000; $display("  TIMEOUT"); $finish; end

    wire _unused = &{1'b0, rx, sd, sc, wr, cla, hunt, ngl, 1'b0};
endmodule

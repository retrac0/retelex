// tb_fl_fwd -- the flood study's wrong numbers at an origin and a transit, at
// REAL timers, with the neighbours the study played on the wires.  Flood study
// REPORT.md §5.1: C03, C05, C12.
//
//      bench Y ==12,13==  A 2 2  ==11==  11  X 1 3  14 == bench Z
//               faces W          faces E  faces W   faces N
//
// A and X are top_net.  A's two west trunks and X's north trunk have the BENCH
// at their far ends: it drives the far A (what the far port puts on the wire),
// the far C, and loops the clock so the link reads up.  X is a leaf (N S E
// strapped; its N trunk is then a strapped link, whose seizures are held and
// monitored but never passed on).  X's code 1 3 is a backbone code
// (numbering.md §5): a stale cell's phantom 1 is X's e.
//
// A's release detectors are built with T_REL 200, an RC 22 % short of its
// 256 ms (fabric.md §3.5: the spread is not measured); X's are nominal, and
// the monitor cells count CLR 256 against them.  Nothing below needs A's
// detectors nominal.
//
//   1  claim     C12.  A20 dials 1 3 1: Y's code.  a) Y claims on A12 after b:
//                A connects A20 to A12.  b) 1 ms of A on A11's receive wire
//                between e and b: a glitch, not a claim.  c) A standing on
//                A11 from 300 ms after e: before b, outside the guard -- no
//                monitor can have claimed, so cannot-complete, never a connect
//   2  late      C05.  Y's flood reaches A so late that its first dial break
//                falls 14 ms into A's 18 ms hold watch (network.md §6): a
//                flood arriving ~110 ms after its origin seized, first break
//                just past the origin's guard.
//                Dialled 1 3 2: A must not count e one short (2 2 is A's)
//   3  glare     C03.  A20 keys 1; Y seizes A12 2 ms after A did, A takes it as
//                the claim and drops A11 after a few ms -- younger than T_ARM,
//                so X's hold and cell have no port edge to go by.  60 ms
//                later Y floods A13 and A forwards it east: the HUNT HOLD-OFF
//                keeps it off A11 (A has no other east trunk, so it is not
//                forwarded).  Y's caller dials 3 2 2: X must not claim
//   4  RC short  C03.  A20 keys 1 and hangs up 50 ms later: A drops A11,
//                which frees at A 200 ms after the break; X11 stays held to
//                256 ms.  Y floods A13 202 ms after the break: the hold-off
//                keeps it off A11, and X's cell lets go at ID of the break
//   5  far RC    C03.  Z seizes X14, hangs up before dialling, and seizes again
//                200 ms later (Z's port released short), then dials 3 2 2.
//                X14 is held throughout; X's cell must let go at ID of the
//                break, or it counts the gap and the make as the digit 1
//
// Real timers because each of these is a race of the unscaled sweep and cable
// (a hop is about 13 ms) against the protocol windows: at scale 8 ID is 16 ms
// and a forward re-seizes after ID, not inside it.  Dials are 10 pps 60/40;
// the pauses between digits are 400 ms, shorter than a conforming pause and
// longer than anything here measures.  About 22 s simulated.
//
// Does not cover: a bench-played far end that re-seizes a channel INSIDE ID of
// a death younger than T_ARM (the hold-off only guards a far end that is a
// unit), a monitor's early claim through a transit's resolver (R_LEG takes one
// sample), a local-trunk link, or rings.
`timescale 1ns/1ps
`include "exch.vh"

module tb_fl_fwd;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*96-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk_a = 1'b0, clk_x = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #(122.070 * 1.00005) clk_x = ~clk_x; end

    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, T13 = 6'o13, T14 = 6'o14;
    localparam [`PW-1:0] P20 = 6'o20, P22 = 6'o22;
    localparam [7:0] WN = {2'd0, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b0, 3'b010, 2'b11};
    localparam [63:0] TRA = (64'd1 << T11) | (64'd1 << T12) | (64'd1 << T13);
    localparam [63:0] TRX = (64'd1 << T11) | (64'd1 << T14);
    localparam [63:0] YB  = (64'd1 << T12) | (64'd1 << T13);        // A's trunks to the bench
    localparam [511:0] TWA = ({504'd0, WE} << (8*T11)) | ({504'd0, WW} << (8*T12)) |
                             ({504'd0, WW} << (8*T13));
    localparam [511:0] TWX = ({504'd0, WW} << (8*T11)) | ({504'd0, WN} << (8*T14));

    reg  [63:0] hook_a = 64'd0, tx_a = 64'd0, hook_x = 64'd0, tx_x = 64'd0;
    reg  [63:0] ym = 64'd0, yc = 64'd0;        // Y's far A and C on A12, A13
    reg         zm = 1'b0;                     // Z's far A on X14
    reg         inj = 1'b0;                    // A = 1 forced on A11's receive wire
    wire [63:0] rx_a, e_a, rx_x, e_x, busy_a, busy_x;
    wire [63:0] ac, aa, ak, xc, xa, xk, up_a, up_x;
    wire        t1k_a, cl_a, cl_x, reg_a, reg_x, creg_a, creg_x;
    wire        mo_a, mo_x, uo_a, uo_x, cla_a;
    wire [3:0]  dirs_a;
    wire [1:0]  res_a, res_x, mon_a, mon_x;
    wire [7:0]  gl_a, nf_a;
    wire [7:0]  lz8 = 8'd0;

    // ---- the cables: A11-X11; A12, A13 to Y; X14 to Z -----------------------
    wire [63:0] ac_in = ((xc[T11] ? 64'd1 : 64'd0) << T11) | (yc & YB);
    wire [63:0] aa_in = (((xa[T11] | inj) ? 64'd1 : 64'd0) << T11) | (ym & YB);
    wire [63:0] ak_in = ((xk[T11] ? 64'd1 : 64'd0) << T11) | (ak & YB);
    wire [63:0] xc_in = (ac[T11] ? 64'd1 : 64'd0) << T11;
    wire [63:0] xa_in = ((aa[T11] ? 64'd1 : 64'd0) << T11) | ((zm ? 64'd1 : 64'd0) << T14);
    wire [63:0] xk_in = ((ak[T11] ? 64'd1 : 64'd0) << T11) | (xk & (64'd1 << T14));

    site_net #(.PHONES(64'h0000_0000_00FF_0000), .TRUNKS(TRA), .TWORD(TWA),
               .OWN_E(3'd2), .OWN_B(3'd2), .T_REL(9'd200)) A (   // an RC 22 % short
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(ac), .a_out(aa), .clk_out(ak), .c_in(ac_in), .a_in(aa_in), .clk_in(ak_in),
        .link_up(up_a),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(lz8), .lt_a_in(lz8), .lt_h_in(lz8), .lt_k_in(lz8), .lt_up(),
        .frame_stb(), .tick_1k(t1k_a), .ring_cad_n(), .port_busy(busy_a),
        .b_sdata(), .b_sclk(), .b_wr(), .b_clash(cl_a),
        .reg_busy(reg_a), .creg_busy(creg_a), .mk_state(), .mk_ovf(mo_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(),
        .un_ovf(uo_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(.PHONES(64'h0000_0000_00FF_0000), .TRUNKS(TRX), .TWORD(TWX),
               .OWN_E(3'd1), .OWN_B(3'd3), .STRAP_N(4'b0111)) X (   // a leaf: N S E strapped
        .clk(clk_x), .rst_n(rst_n), .hook(hook_x), .tx(tx_x), .rx(rx_x), .e(e_x),
        .c_out(xc), .a_out(xa), .clk_out(xk), .c_in(xc_in), .a_in(xa_in), .clk_in(xk_in),
        .link_up(up_x),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(lz8), .lt_a_in(lz8), .lt_h_in(lz8), .lt_k_in(lz8), .lt_up(),
        .frame_stb(), .tick_1k(), .ring_cad_n(), .port_busy(busy_x),
        .b_sdata(), .b_sclk(), .b_wr(), .b_clash(cl_x),
        .reg_busy(reg_x), .creg_busy(creg_x), .mk_state(), .mk_ovf(mo_x), .dirs_held(),
        .res_busy(res_x), .mon_held(mon_x), .claimed(), .hunting(),
        .un_ovf(uo_x), .n_glare(), .n_nofwd());

    // ---- what the units decide, read by hierarchy to count it ---------------
    wire           a_done  = A.u_x.u_net.done;
    wire           a_nogo  = A.u_x.u_net.nogo;
    wire [`PW-1:0] a_trunk = A.u_x.u_net.trunk;
    wire [2:0]     a_cst   = A.u_x.u_net.cst;
    wire [`PW-1:0] a_clsp  = A.u_x.u_net.cls_port;
    wire [`PW-1:0] a_rport = A.u_x.u_mk.caller;
    wire [2:0]     x_cst   = X.u_x.u_net.cst;
    wire [`PW-1:0] x_clsp  = X.u_x.u_net.cls_port;
    wire [1:0]     x_mheld = X.u_x.u_net.m_held;
    wire [2*`PW-1:0] x_mport = X.u_x.u_net.m_port;
    localparam [2:0] C_HOLD = 3'd3, C_LOW = 3'd6;

    integer n_done = 0, n_nogo = 0, a_low13 = 0;
    reg [`PW-1:0] done_trunk = 6'o00;
    always @(posedge clk_a) begin
        if (a_done) begin n_done = n_done + 1; done_trunk = a_trunk; end
        if (a_nogo) n_nogo = n_nogo + 1;
        if (a_cst == C_LOW && a_clsp == T13) a_low13 = a_low13 + 1;
    end
    // X's claims: its backward A on X11 or X14 rises, or its claim register is taken
    integer x_claims = 0;
    reg xcl_d = 1'b0;
    always @(posedge clk_x) begin
        if ((xa[T11] || xa[T14] || creg_x) && !xcl_d) x_claims = x_claims + 1;
        xcl_d <= xa[T11] || xa[T14] || creg_x;
    end
    // a cell of X's on a port
    function x_cell_on(input [`PW-1:0] p);
        x_cell_on = (x_mheld[0] && x_mport[`PW-1:0] == p) || (x_mheld[1] && x_mport[2*`PW-1:`PW] == p);
    endfunction
    // A11 seized again while it is watched
    reg watch11 = 1'b0; integer a11_taken = 0;
    always @(posedge clk_a) if (watch11 && busy_a[T11]) a11_taken = a11_taken + 1;

    integer clash = 0;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_x) if (cl_x) clash = clash + 1;

    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask

    // a dial at 10 pps 60/40 and a 400 ms pause: A20's, or a bench far end's
    // (0 A20, T12/T13 Y on that trunk, 64 Z)
    task dial(input integer who, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                if (who == 0) hook_a[P20] = 1'b0; else if (who == 64) zm = 1'b0; else ym[who] = 1'b0;
                ms(60);
                if (who == 0) hook_a[P20] = 1'b1; else if (who == 64) zm = 1'b1; else ym[who] = 1'b1;
                ms(40);
            end
            ms(400);
        end
    endtask

    // does A20 hear what Y sends on A12
    reg s0, s1; integer j;
    task hear_y12;
        begin
            yc[T12] = 1'b1; ms(3); s1 = 1'b1;
            for (j = 0; j < 8; j = j + 1) begin @(posedge t1k_a); if (!rx_a[P20]) s1 = 1'b0; end
            yc[T12] = 1'b0; ms(3); s0 = 1'b1;
            for (j = 0; j < 8; j = j + 1) begin @(posedge t1k_a); if (rx_a[P20]) s0 = 1'b0; end
        end
    endtask

    task idle(input [8*96-1:0] what);
        begin
            ms(900);
            ck(busy_a == 64'd0 && busy_x == 64'd0 && !reg_a && !reg_x && !creg_a && !creg_x &&
               mon_a == 2'd0 && mon_x == 2'd0 && res_a == 2'd0 && res_x == 2'd0 && dirs_a == 4'd0, what);
        end
    endtask

    // A20 lifts and waits for A's register
    task lift;
        integer w;
        begin
            hook_a[P20] = 1'b1;
            w = 0; while (!(reg_a && a_rport == P20) && w < 2000) begin @(posedge t1k_a); w = w + 1; end
            ms(300);
        end
    endtask

    integer nd0, nn0, nf0, gl0, xc0, t_brk, k, n;
    initial begin
        $display("\n  tb_fl_fwd -- an origin, a transit and the neighbours on the wires, real timers");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(300);
        ck(up_a[T11] && up_a[T12] && up_a[T13] && up_x[T11] && up_x[T14], "every link is up");

        // ================= 1.  what the origin takes as the claim (C12) =========
        $display("  1a. A20 dials 1 3 1; Y claims on A12 after b");
        nd0 = n_done; nn0 = n_nogo;
        lift; dial(0, 1);
        ck(dirs_a == 4'b1100, "the key seized a trunk each way: A11 east, A12 west");
        dial(0, 3);                                         // e: Y's, not X's
        ck(mon_x == 2'd0, "X's monitor let go at e: 3 is not X's 1");
        dial(0, 1);                                         // b: Y's.  Its make ends it at ID
        ym[T12] = 1'b1;                                     // Y claims, as its monitor would
        ms(40);
        ck(n_done == nd0 + 1 && done_trunk == T12, "A connected A20 to A12, the trunk Y claimed");
        hear_y12;
        ck(s1 && s0, "and A20 hears Y on it");
        hook_a[P20] = 1'b0; ym[T12] = 1'b0;
        idle("1a: both exchanges idle again");

        $display("  1b. the same, with 1 ms of A on A11's receive wire between e and b");
        nd0 = n_done; nn0 = n_nogo;
        lift; dial(0, 1); dial(0, 3);
        ms(100);                                            // 500 ms after e: outside the guard, before b
        inj = 1'b1; #1_000_000; inj = 1'b0;
        ms(100);
        ck(dirs_a == 4'b1100 && !cla_a, "a 1 ms glitch on a held trunk is no claim: A still holds both");
        dial(0, 1);
        ym[T12] = 1'b1;
        ms(40);
        ck(n_done == nd0 + 1 && done_trunk == T12, "and when Y claims, A connects A20 to A12");
        ck(n_nogo == nn0, "and gives no cannot-complete");
        hook_a[P20] = 1'b0; ym[T12] = 1'b0;
        idle("1b: both exchanges idle again");

        $display("  1c. A standing on A11 from 300 ms after e: an early claim");
        nd0 = n_done; nn0 = n_nogo;
        lift; dial(0, 1); dial(0, 3);
        inj = 1'b1;
        ms(100);
        ck(n_nogo == nn0 + 1 && dirs_a == 4'b0000, "a claim before b, outside the guard: cannot-complete, every trunk dropped");
        dial(0, 1);
        ms(200);
        ck(n_done == nd0, "and A20 is never connected, to A11 or anywhere");
        ck(!(n_done != nd0 && done_trunk == T11), "SAFETY: A20 is not connected to A11, where nothing claimed");
        hook_a[P20] = 1'b0; inj = 1'b0;
        idle("1c: both exchanges idle again");

        // ================= 2.  a late flood: a dial break in the hold watch (C05)
        $display("  2. Y floods A13; its first break of e comes 14 ms into A's hold watch");
        k = a_low13; xc0 = x_claims;
        ym[T13] = 1'b1;
        n = 0; while (!(a_cst == C_HOLD && a_clsp == T13) && n < 204800) begin @(posedge clk_a); n = n + 1; end
        ms(14);                                             // 14 ms into A's 18 ms watch
        dial(T13, 3);                                        // e = 3
        ck(a_low13 > k, "OBSERVE: the first break reached A inside its hold watch (C_LOW)");
        dial(T13, 2);                                        // b = 2: 3 2 is nobody's
        ck(aa[T13] === 1'b0 && !creg_a, "SAFETY: A (2 2) does not claim a flood dialled 1 3 2");
        ck(x_claims == xc0, "SAFETY: nor does X, which it was forwarded to");
        ym[T13] = 1'b0;
        idle("2: both exchanges idle again");

        // ================= 3.  glare drops A11 young, then a forward (C03) =======
        $display("  3. A20 keys 1; Y seizes A12 2 ms after A; Y floods A13 60 ms later");
        gl0 = gl_a; nf0 = nf_a; xc0 = x_claims;
        lift;
        hook_a[P20] = 1'b0; ms(60); hook_a[P20] = 1'b1;     // the key
        n = 0; while (!(busy_a[T11] && busy_a[T12]) && n < 1000) begin @(posedge t1k_a); n = n + 1; end
        ms(2);
        ym[T12] = 1'b1;                                     // glare: Y took the same channel
        n = 0; while (dirs_a != 4'b1000 && n < 409600) begin @(posedge clk_a); n = n + 1; end
        n = 0; while (busy_a[T11] !== 1'b0 && n < 409600) begin @(posedge clk_a); n = n + 1; end
        ck(gl_a == gl0 + 1, "A took Y's seizure of A12 as its claim, and counted the glare");
        ms(8);
        ck(x_cell_on(T11) && busy_x[T11], "X holds the short seizure on X11 and gave it a cell");
        watch11 = 1'b1; a11_taken = 0;
        ms(52);
        ck(x_cst == C_LOW && x_clsp == T11, "OBSERVE: X is waiting ID out on X11's low M: a dial break or a death");
        ym[T13] = 1'b1;                                     // Y forwards another flood to A
        ms(90);
        ck(nf_a == nf0 + 1, "A held Y's flood on A13 and found no east trunk to pass it on");
        ck(!busy_x[T11] && !x_cell_on(T11), "X wrote the dead seizure's hold away, and its cell with it");
        ms(210);
        ck(a11_taken == 0, "HOLD-OFF: A kept its forward off A11 for 256 ms after dropping it");
        watch11 = 1'b0;
        ms(100);
        dial(T13, 3);                                        // Y's caller: 3 2 2
        ck(x_claims == xc0 && !creg_x, "SAFETY: X (1 3) does not claim a flood dialled to 3x");
        dial(T13, 2); dial(T13, 2);
        ck(!(busy_x[P22] && !hook_x[P22]), "SAFETY: X22 is not rung");
        hook_a[P20] = 1'b0; ym[T12] = 1'b0; ym[T13] = 1'b0;
        idle("3: both exchanges idle again");

        // ================= 4.  A's RC is short; X's cell and hold outlive it =====
        $display("  4. A20 keys 1 and hangs up 50 ms later; Y floods A13 202 ms after the break");
        nf0 = nf_a; xc0 = x_claims;
        lift;
        hook_a[P20] = 1'b0; ms(60); hook_a[P20] = 1'b1;
        n = 0; while (busy_a[T11] !== 1'b1 && n < 1000) begin @(posedge t1k_a); n = n + 1; end
        ms(50);
        hook_a[P20] = 1'b0; t_brk = 0;                      // A20 hangs up inside the guard
        watch11 = 1'b0;
        ms(20);
        ck(dirs_a == 4'b0000 && x_cell_on(T11), "A abandoned and dropped its trunks; X's cell still counts X11");
        while (busy_a[T11] !== 1'b0 && t_brk < 600) begin @(posedge t1k_a); t_brk = t_brk + 1; end
        $display("       A11 free at A %0d ms after the drop", t_brk + 20);
        ck(busy_x[T11] && !x_cell_on(T11),
           "X's cell let go at ID of the break, while X's port still holds X11");
        watch11 = 1'b1; a11_taken = 0;
        ym[T13] = 1'b1;
        ms(60);
        ck(nf_a == nf0 + 1 && a11_taken == 0,
           "HOLD-OFF: A's forward did not take A11, free at A but still held at X");
        watch11 = 1'b0;
        ms(300);
        dial(T13, 3);
        ck(x_claims == xc0 && !creg_x, "SAFETY: X does not claim a flood dialled to 3x");
        dial(T13, 2); dial(T13, 2);
        ck(!(busy_x[P22] && !hook_x[P22]), "SAFETY: X22 is not rung");
        ym[T13] = 1'b0;
        idle("4: both exchanges idle again");

        // ================= 5.  Z's RC is short: a re-seizure inside CLR (C03) ====
        $display("  5. Z seizes X14, hangs up, seizes again 200 ms later and dials 3 2 2");
        xc0 = x_claims;
        zm = 1'b1; ms(400);
        ck(busy_x[T14] && x_cell_on(T14), "X holds X14 and gave it a cell");
        zm = 1'b0; ms(150);
        ck(busy_x[T14] && !x_cell_on(T14), "the break is ID long: X's cell let go, X14 still held");
        ms(50);
        zm = 1'b1; ms(400);                                 // Z's next call on the same channel
        dial(64, 3);
        ck(x_claims == xc0 && !creg_x, "SAFETY: X does not claim Z's call dialled to 3x");
        dial(64, 2); dial(64, 2);
        ck(!(busy_x[P22] && !hook_x[P22]), "SAFETY: X22 is not rung");
        zm = 1'b0;
        idle("5: both exchanges idle again");

        ck(clash == 0, "no cable B had two masters driving at once");
        ck(!mo_a && !mo_x && !uo_a && !uo_x, "no queue on either exchange refused a write");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #40_000_000_000; $display("  TIMEOUT"); $fatal(1); end

    wire _unused = &{1'b0, e_a, e_x, rx_x, tx_x, a_trunk, x_clsp, res_x, 1'b0};
endmodule

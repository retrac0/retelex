// tb_c16 -- VERIFY scratch bench (cluster C16-marker-reread).  Not part of the tree.
//
// tb_net's two exchanges and link (A 2 2, B 2 3; A11-B11, A12-B12; B's phones
// 20 and 21), and tb_net scenario 2 -- A20 dials 1 2 3 2 1, B21 answers and
// hangs up FIRST, so B11 releases under A20's standing M.  Measures, at B:
//   * the window B11 shows M with BUSY clear (busy_b[11] low, B11's far A up)
//   * how often B's MARKER and B's UNIT read B11's word in that window
//   * the dial-tone delay (hook -> the marker attaching its register) of a
//     line that lifts inside the window: B20 is B11+7, B21 is B11+8
//   * the same delay with nothing going on (control)
// +case=0: control only.  +case=1: window, B20 lifts.  +case=2: window, B21 lifts.
// -DREAL: real timers and a 10 pps dial; else tb_net's scale of 8.
`timescale 1ns/1ps
`include "exch.vh"

module tb_c16;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*72-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

`ifdef REAL
    localparam [8:0]  P_TARM = 9'd16, P_TREL = 9'd256, P_HIT = 9'd8, P_ID = 9'd128, P_CLR = 9'd256;
    localparam [12:0] P_RON = 13'd2048, P_ROFF = 13'd4096;
    localparam [15:0] P_NODIG = 16'd10000, P_GUARD = 16'd128, P_TKEY = 16'd5000, P_TCLAIM = 16'd2000;
    localparam integer BRK = 60, MK = 40, PAUSE = 800, SC = 8, WAITR = 600, IDLEW = 1200, RINGW = 2500;
`else
    localparam [8:0]  P_TARM = 9'd2, P_TREL = 9'd32, P_HIT = 9'd1, P_ID = 9'd16, P_CLR = 9'd32;
    localparam [12:0] P_RON = 13'd64, P_ROFF = 13'd128;
    localparam [15:0] P_NODIG = 16'd1250, P_GUARD = 16'd16, P_TKEY = 16'd625, P_TCLAIM = 16'd250;
    localparam integer BRK = 12, MK = 8, PAUSE = 100, SC = 1, WAITR = 300, IDLEW = 400, RINGW = 400;
`endif

    reg clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_b = ~clk_b; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21, P22 = 6'o22, P24 = 6'o24;
    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, T25 = 6'o25;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};
    localparam [511:0] TW_A = ({504'd0, WE} << (8*T11)) | ({504'd0, WE} << (8*T12)) |
                              ({504'd0, WE} << (8*T25));
    localparam [511:0] TW_B = ({504'd0, WW} << (8*T11)) | ({504'd0, WW} << (8*T12));

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
               .T_ARM(P_TARM), .T_REL(P_TREL), .RING_ON(P_RON), .RING_OFF(P_ROFF),
               .HIT(P_HIT), .ID(P_ID), .CLR(P_CLR), .NODIG(P_NODIG),
               .T_GUARD0(P_GUARD), .T_KEY(P_TKEY), .T_CLAIM(P_TCLAIM)) A (
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
               .T_ARM(P_TARM), .T_REL(P_TREL), .RING_ON(P_RON), .RING_OFF(P_ROFF),
               .HIT(P_HIT), .ID(P_ID), .CLR(P_CLR), .NODIG(P_NODIG),
               .T_GUARD0(P_GUARD), .T_KEY(P_TKEY), .T_CLAIM(P_TCLAIM)) B (
        .clk(clk_b), .rst_n(rst_n), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(bc_out), .a_out(ba_out), .clk_out(bk_out),
        .c_in(bc_in), .a_in(ba_in), .clk_in(bk_in), .link_up(up_b),
        .frame_stb(fs_b), .tick_1k(t1k_b), .ring_cad_n(rc_b), .port_busy(busy_b),
        .b_sdata(sd_b), .b_sclk(sc_b), .b_wr(wr_b), .b_clash(cl_b),
        .reg_busy(reg_b), .mk_state(mks_b), .mk_ovf(mko_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(hunt_b),
        .un_ovf(uno_b), .n_glare(gl_b), .n_nofwd(nf_b));

    reg stuckA = 1'b0;   // case 4: the B->A A conductor of link 11 stuck at 1 (a fault)
    always @* begin
        ac_in = 64'd0; aa_in = 64'd0; ak_in = 64'd0;
        bc_in = 64'd0; ba_in = 64'd0; bk_in = 64'd0;
        ac_in[T11] = bc_out[T11]; aa_in[T11] = stuckA || ba_out[T11]; ak_in[T11] = bk_out[T11];
        ac_in[T12] = bc_out[T12]; aa_in[T12] = ba_out[T12]; ak_in[T12] = bk_out[T12];
        bc_in[T11] = ac_out[T11]; ba_in[T11] = aa_out[T11]; bk_in[T11] = ak_out[T11];
        bc_in[T12] = ac_out[T12]; ba_in[T12] = aa_out[T12]; bk_in[T12] = ak_out[T12];
        ac_in[T25] = ac_out[T25]; aa_in[T25] = aa_out[T25]; ak_in[T25] = ak_out[T25];
    end

    // ---- B's marker and unit, by hierarchy ------------------------------------
    wire        mk_rdreq = B.u_x.u_mk.rd_req;
    wire [5:0]  mk_rdp   = B.u_x.u_mk.rd_port;
    wire        mk_rdc   = B.u_x.u_mk.rd_caller;
    wire        mk_att   = B.u_x.u_mk.r_attach;
    wire [5:0]  mk_attp  = B.u_x.u_mk.r_port;
    wire        un_rdreq = B.u_x.u_net.rd_req;
    wire [5:0]  un_rdp   = B.u_x.u_net.rd_port;
    wire        un_hunt  = B.u_x.u_net.hunting;

    wire        amk_rdreq = A.u_x.u_mk.rd_req;
    wire [5:0]  amk_rdp   = A.u_x.u_mk.rd_port;
    wire        amk_att   = A.u_x.u_mk.r_attach;
    wire [5:0]  amk_attp  = A.u_x.u_mk.r_port;
    integer n_amk11 = 0;
    always @(posedge clk_a) if (cnt_on && amk_rdreq && amk_rdp == T11) n_amk11 = n_amk11 + 1;
    real ta_att [0:63];
    integer qa;
    initial for (qa = 0; qa < 64; qa = qa + 1) ta_att[qa] = -1.0;
    always @(posedge clk_a) if (amk_att) ta_att[amk_attp] = $realtime;

    // counters, armed by the bench
    reg     cnt_on = 1'b0;
    integer n_mk11 = 0, n_un11 = 0, n_mkread = 0, n_sread_ticks = 0, n_ticks = 0, n_mkother = 0;
    always @(posedge clk_b) if (cnt_on) begin
        n_ticks = n_ticks + 1;
        if (mks_b == 3'd4) n_sread_ticks = n_sread_ticks + 1;
        if (mk_rdreq) begin
            n_mkread = n_mkread + 1;
            if (mk_rdp == T11) n_mk11 = n_mk11 + 1; else n_mkother = n_mkother + 1;
        end
        if (un_rdreq && un_rdp == T11) n_un11 = n_un11 + 1;
    end

    // time of the marker attaching a port's register
    real t_att [0:63];
    integer q;
    initial for (q = 0; q < 64; q = q + 1) t_att[q] = -1.0;
    always @(posedge clk_b) if (mk_att) t_att[mk_attp] = $realtime;

    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask
    task msb(input integer n); begin repeat (n) @(posedge t1k_b); end endtask

    task dial_a(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; ms(BRK);
                hook_a[p] = 1'b1; ms(MK);
            end
            ms(PAUSE);
        end
    endtask

    integer hi, lo;
    task rings_b(input [`PW-1:0] p);
        integer i;
        begin hi = 0; lo = 0;
            for (i = 0; i < RINGW; i = i + 1) begin
                @(posedge t1k_b); if (e_b[p]) hi = hi + 1; else lo = lo + 1;
            end
        end
    endtask

    // dial tone delay: lift p, wait for the marker to attach it
    real t0, dly, t_rel, t_mfall, t_hang;
    task lift_b(input [`PW-1:0] p, output real d);
        integer w;
        begin
            t_att[p] = -1.0; t0 = $realtime; hook_b[p] = 1'b1;
            w = 0;
            while (t_att[p] < 0.0 && w < 2000*SC) begin @(posedge t1k_b); w = w + 1; end
            if (t_att[p] < 0.0) d = -1.0; else d = (t_att[p] - t0) / 1.0e6;
        end
    endtask

    task lift_a(input [`PW-1:0] p, output real d);
        integer w;
        begin
            ta_att[p] = -1.0; t0 = $realtime; hook_a[p] = 1'b1;
            w = 0;
            while (ta_att[p] < 0.0 && w < 1000*SC) begin @(posedge t1k_a); w = w + 1; end
            if (ta_att[p] < 0.0) d = -1.0; else d = (ta_att[p] - t0) / 1.0e6;
        end
    endtask

    task idle_all(input [8*72-1:0] what);
        begin
            ms(IDLEW);
            ck(busy_a == 64'd0 && busy_b == 64'd0 && !reg_a && !reg_b &&
               mks_a == 3'd0 && mks_b == 3'd0 && dirs_a == 4'd0 && res_b == 2'd0, what);
        end
    endtask

    integer cs, w2;
    reg [`PW-1:0] lp, cp;
    initial begin
        if (!$value$plusargs("case=%d", cs)) cs = 0;
        $display("\n  tb_c16 -- B's marker and an unheld trunk (case %0d, SC %0d)", cs, SC);
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(20);
        ck(up_a[T11] && up_a[T12] && up_b[T11] && up_b[T12], "links up");

        // ---- control: B20 and B21 lift with nothing going on ----------------
        lift_b(P20, dly); $display("    CONTROL: B20 (B11+7) dial-tone delay %0.2f ms", dly);
        hook_b[P20] = 1'b0; ms(WAITR);
        lift_b(P21, dly); $display("    CONTROL: B21 (B11+8) dial-tone delay %0.2f ms", dly);
        hook_b[P21] = 1'b0; idle_all("control: idle");

        if (cs != 0 && cs != 4) begin
            // case 1: B21 called, B20 (B11+7) lifts.  case 2: B21 called and lifts again
            // (confounded: B21's own fE holds it BUSY T_REL after its release).
            // case 3: B20 called (s = 0), B21 (B11+8) lifts.
            lp = (cs == 1 || cs == 3) ? ((cs == 1) ? P20 : P21) : P21;
            cp = (cs == 3) ? P20 : P21;
            // ---- tb_net 2: A20 dials 1 2 3 2 1, B21 answers, hangs up first ----
            hook_a[P20] = 1'b1; ms((SC == 8) ? 600 : 10);
            dial_a(P20, 1);
            ck(busy_b[T11] === 1'b1, "B holds the seizure on 11");
            dial_a(P20, 2); dial_a(P20, 3);
            ck(cla_a === 1'b1 && reg_b === 1'b1, "claimed, B's register on B11");
            dial_a(P20, 2); dial_a(P20, (cp == P20) ? 0 : 1); ms(20);
            rings_b(cp); ck(hi > 50 && lo > 50, "the called B port rings");
            hook_b[cp] = 1'b1; ms(20*SC);
            ck(busy_b[T11] === 1'b1 && ba_in[T11] === 1'b1, "call up: B11 BUSY, A20's M on it");
            // B21 hangs up FIRST
            cnt_on = 1'b1; t_hang = $realtime;
            hook_b[cp] = 1'b0;
            w2 = 0; while (busy_b[T11] !== 1'b0 && w2 < 4096*600*SC) begin @(posedge clk_b); w2 = w2 + 1; end
            t_rel = $realtime;
            $display("    B11 BUSY fell %0.2f ms after the called B%0o hung up; far M (A20 via A11) still %b",
                     (t_rel - t_hang) / 1.0e6, cp, ba_in[T11]);
            msb(2);
            fork
                begin lift_b(lp, dly); end
                begin
                    w2 = 0; while (ba_in[T11] !== 1'b0 && w2 < 4096*600*SC) begin @(posedge clk_b); w2 = w2 + 1; end
                    t_mfall = $realtime;
                end
            join
            $display("    B11 showed M, BUSY clear, for %0.2f ms", (t_mfall - t_rel) / 1.0e6);
            $display("    %s (B11+%0d) lifted 2 ms into it: dial-tone delay %0.2f ms",
                     (lp == P20) ? "B20" : "B21", lp - T11, dly);
            ms(20*SC);
            cnt_on = 1'b0;
            $display("    from B21's hang-up to 20 ms after: B marker reads of B11 = %0d, other reads = %0d; B unit reads of B11 = %0d",
                     n_mk11, n_mkother, n_un11);
            $display("    B marker in S_READ %0d of %0d ticks (%0.1f%%)", n_sread_ticks, n_ticks,
                     100.0 * n_sread_ticks / n_ticks);
            hook_a[P20] = 1'b0; hook_b[lp] = 1'b0;
            idle_all("idle again");
        end

        if (cs == 4) begin
            // ---- a FAULT: B->A A of link 11 stuck at 1; the caller hangs up first ----
            lift_a(P21, dly); $display("    CONTROL: A21 (A11+8) dial-tone delay %0.2f ms", dly);
            hook_a[P21] = 1'b0; ms(WAITR);
            hook_a[P20] = 1'b1; ms((SC == 8) ? 600 : 10);
            dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 3);
            ck(cla_a === 1'b1 && reg_b === 1'b1, "4: claimed, B's register on B11");
            dial_a(P20, 2); dial_a(P20, 1); ms(20);
            rings_b(P21); ck(hi > 50 && lo > 50, "4: B21 rings");
            hook_b[P21] = 1'b1; ms(20*SC);
            stuckA = 1'b1;                          // the fault
            hook_a[P20] = 1'b0;                     // the caller hangs up FIRST
            ms(WAITR); hook_b[P21] = 1'b0; ms(WAITR);
            ck(busy_a[T11] === 1'b0, "4: A11 released (fE), under the stuck far A");
            cnt_on = 1'b1;
            lift_a(P20, dly); $display("    A20 (A11+7) with A11 unheld under a stuck A: dial-tone delay %0.2f ms (-1 = none in %0d ms)", dly, 1000*SC);
            hook_a[P20] = 1'b0; ms(WAITR);
            lift_a(P21, dly); $display("    A21 (A11+8) with A11 unheld under a stuck A: dial-tone delay %0.2f ms", dly);
            cnt_on = 1'b0;
            $display("    A marker reads of A11 meanwhile: %0d", n_amk11);
            hook_a[P21] = 1'b0; stuckA = 1'b0;
            idle_all("4: idle again once the fault clears");
        end

        ck(!mko_a && !mko_b && !uno_a && !uno_b, "no queue refused a write");
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #60_000_000_000; $display("  TIMEOUT"); $finish; end
    wire _unused = &{1'b0, rx_a, rx_b, e_a, sd_a, sc_a, wr_a, sd_b, sc_b, wr_b, cl_a, cl_b,
                     hunt_a, hunt_b, gl_a, gl_b, nf_a, nf_b, mon_a, mon_b, dirs_b, res_a,
                     cla_b, mk_rdc, un_hunt, fs_a, fs_b, rc_a, rc_b, 1'b0};
endmodule

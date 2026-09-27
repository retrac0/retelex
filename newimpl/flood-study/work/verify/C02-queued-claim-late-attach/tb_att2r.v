// tb_att2r -- VERIFY C02: work/audit/cableb/tb_att2.v at REAL timers (T_ARM 16, HIT 8, ID 128,
// CLR 256, NODIG 10000, guard 128, T_KEY 5000, T_CLAIM 2000), 10 pps 60/40, 800 ms pauses.
// The chatter fault is unchanged (1 ms break, 2 ms make: never SETTLE=32, never CLR).
// Original header:
// tb_att2 -- AUDIT (cableb slice).  tb_attw's plant, third scenario.
// tb_attw's header follows for the plant:
//  A claim that arrives while the far mini
// marker is in S_WATCH.  mini_marker.v says of WATCH: "a claim waits that
// out -- `att` is a level the unit holds until it is answered".  This bench
// holds B's marker in WATCH (B20 has just been connected to B21 and its line
// chatters: short breaks, short makes, never `settled`, never `gone`), lets
// A20's flood be claimed by B meanwhile, then lets WATCH end, and records
// what B's marker does with the claim that waited.
//
//   +scen=1   A20 stays on: after WATCH, is the claim TAKEN (B's register on
//             B11, A20's h s = 2 2 rings B22) or REFUSED (B11 -> 03, CLM)?
//   +scen=2   A20 hangs up the moment B raises att; WATCH is held 150 ms
//             more, long past B11's own release.  What is left behind?
//   +fixatt   the knob in work/audit/cableb/mini_marker_k.v: no refusal on
//             the tick the marker's own release is still landing
//
// Topology and timers exactly tb_net's (scale 8).  A = 2 2, B = 2 3,
// A11-B11 and A12-B12 on baseband cards; A faces E, B faces W with glare.
`timescale 1ns/1ps
`include "exch.vh"

module blog #(parameter [7:0] NAME = "A") (
    input clk, input t1k, input sd, input sc, input wr, input moe, input uoe);
    reg [15:0] sh = 16'd0; reg sc_d = 1'b0, wr_d = 1'b0;
    integer msn = 0;
    always @(posedge clk) begin
        if (t1k) msn = msn + 1;
        sc_d <= sc; wr_d <= wr;
        if (sc && !sc_d) sh <= {sh[14:0], sd};
        if (wr && !wr_d)
            $display("    [%0d ms] %c cableB %s G%0d dst %o src %o bsy %0d clm %0d",
                     msn, NAME, uoe ? "UNIT  " : (moe ? "MARKER" : "??    "),
                     sh[15], sh[13:8], sh[7:2], sh[1], sh[0]);
    end
endmodule

module tb_att2r;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*80-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_b = ~clk_b; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21, P22 = 6'o22, P32 = 6'o32;
    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};
    localparam [511:0] TW_A = ({504'd0, WE} << (8*T11)) | ({504'd0, WE} << (8*T12));
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

    site_net #(.PHONES(64'h0000_0000_0003_0000), .TRUNKS((64'd1 << T11) | (64'd1 << T12)),
               .TWORD(TW_A), .OWN_E(3'd2), .OWN_B(3'd2),
               .T_ARM(9'd16), .T_REL(9'd256), .RING_ON(13'd64), .RING_OFF(13'd128),
               .HIT(9'd8), .ID(9'd128), .CLR(9'd256), .NODIG(16'd10000),
               .T_GUARD0(16'd128), .T_KEY(16'd5000), .T_CLAIM(16'd2000)) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(ac_out), .a_out(aa_out), .clk_out(ak_out),
        .c_in(ac_in), .a_in(aa_in), .clk_in(ak_in), .link_up(up_a),
        .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a), .port_busy(busy_a),
        .b_sdata(sd_a), .b_sclk(sc_a), .b_wr(wr_a), .b_clash(cl_a),
        .reg_busy(reg_a), .mk_state(mks_a), .mk_ovf(mko_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(hunt_a),
        .un_ovf(uno_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(.PHONES(64'h0000_0000_0407_0000), .TRUNKS((64'd1 << T11) | (64'd1 << T12)),
               .TWORD(TW_B), .OWN_E(3'd2), .OWN_B(3'd3),
               .T_ARM(9'd16), .T_REL(9'd256), .RING_ON(13'd64), .RING_OFF(13'd128),
               .HIT(9'd8), .ID(9'd128), .CLR(9'd256), .NODIG(16'd10000),
               .T_GUARD0(16'd128), .T_KEY(16'd5000), .T_CLAIM(16'd2000)) B (
        .clk(clk_b), .rst_n(rst_n), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(bc_out), .a_out(ba_out), .clk_out(bk_out),
        .c_in(bc_in), .a_in(ba_in), .clk_in(bk_in), .link_up(up_b),
        .frame_stb(fs_b), .tick_1k(t1k_b), .ring_cad_n(rc_b), .port_busy(busy_b),
        .b_sdata(sd_b), .b_sclk(sc_b), .b_wr(wr_b), .b_clash(cl_b),
        .reg_busy(reg_b), .mk_state(mks_b), .mk_ovf(mko_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(hunt_b),
        .un_ovf(uno_b), .n_glare(gl_b), .n_nofwd(nf_b));

    always @* begin
        ac_in = 64'd0; aa_in = 64'd0; ak_in = 64'd0;
        bc_in = 64'd0; ba_in = 64'd0; bk_in = 64'd0;
        ac_in[T11] = bc_out[T11]; aa_in[T11] = ba_out[T11]; ak_in[T11] = bk_out[T11];
        ac_in[T12] = bc_out[T12]; aa_in[T12] = ba_out[T12]; ak_in[T12] = bk_out[T12];
        bc_in[T11] = ac_out[T11]; ba_in[T11] = aa_out[T11]; bk_in[T11] = ak_out[T11];
        bc_in[T12] = ac_out[T12]; ba_in[T12] = aa_out[T12]; bk_in[T12] = ak_out[T12];
    end

    blog #(.NAME("A")) LA (.clk(clk_a), .t1k(t1k_a), .sd(sd_a), .sc(sc_a), .wr(wr_a),
                           .moe(A.u_x.m_oe), .uoe(A.u_x.u_oe));
    blog #(.NAME("B")) LB (.clk(clk_b), .t1k(t1k_b), .sd(sd_b), .sc(sc_b), .wr(wr_b),
                           .moe(B.u_x.m_oe), .uoe(B.u_x.u_oe));

    integer clash = 0;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_b) if (cl_b) clash = clash + 1;

    // ---- what B's marker does with the claim ----------------------------------
    // att_ack with a NOGO word pushed that tick is a refusal; with the
    // register attached to the trunk it is a take.
    integer n_take = 0, n_refuse = 0, now_b = 0;
    always @(posedge clk_b) if (t1k_b) now_b = now_b + 1;
    always @(posedge clk_b) begin
        if (B.u_x.u_mk.att_ack) begin
            if (B.u_x.u_mk.push_v != 2'b00) begin
                n_refuse = n_refuse + 1;
                $display("    [%0d ms] B's marker REFUSED the claim on %o (state was %0d, r_busy %0d)",
                         now_b, B.u_x.u_net.att_port, B.u_x.u_mk.state, B.u_x.u_mk.r_busy);
            end else begin
                n_take = n_take + 1;
                $display("    [%0d ms] B's marker TOOK the claim on %o", now_b, B.u_x.u_net.att_port);
            end
        end
    end
    reg att_d = 1'b0;
    always @(posedge clk_b) begin
        att_d <= B.u_x.u_net.att;
        if (B.u_x.u_net.att && !att_d)
            $display("    [%0d ms] B's unit raises att for %o; B's marker is in state %0d",
                     now_b, B.u_x.u_net.att_port, B.u_x.u_mk.state);
    end

    task automatic ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask
    task automatic ms_b(input integer n); begin repeat (n) @(posedge t1k_b); end endtask

    task automatic dial_a(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; ms(60); hook_a[p] = 1'b1; ms(40);
            end
            ms(800);
        end
    endtask
    task automatic pulses_a(input [`PW-1:0] p, input integer n);
        integer i;
        begin for (i = 0; i < n; i = i + 1) begin hook_a[p] = 1'b0; ms(60); hook_a[p] = 1'b1; ms(40); end end
    endtask
    task automatic dial_b(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_b[p] = 1'b0; ms_b(60); hook_b[p] = 1'b1; ms_b(40);
            end
            ms_b(800);
        end
    endtask
    task automatic pulses_b(input [`PW-1:0] p, input integer n);
        integer i;
        begin for (i = 0; i < n; i = i + 1) begin hook_b[p] = 1'b0; ms_b(60); hook_b[p] = 1'b1; ms_b(40); end end
    endtask

    integer j; reg s0, s1;
    task hear_a(input [`PW-1:0] p);
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 8; j = j + 1) begin
                @(posedge fs_a); @(posedge clk_a);
                if (rx_a[p]) s1 = 1'b1; else s0 = 1'b1;
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

    // B20's chattering line: 1 ms breaks, 2 ms makes.  Never `settled`
    // (SETTLE is 4 ms here), never `gone` (CLR 32), no digit (a one-sample
    // break never reaches HIT's second sample).
    reg chat = 1'b0;
    always begin
        @(posedge t1k_b);
        if (chat) begin hook_b[P20] = 1'b0; ms_b(1); hook_b[P20] = 1'b1; ms_b(1); end
    end

    integer dstop, tw, h0, t_ret;
    // the register B's marker attaches: when, to what, and what it counts
    reg att_r = 1'b0;
    always @(posedge clk_b) begin
        if (B.u_x.u_mk.r_attach)
            $display("    [%0d ms] B's register ATTACHES to %o", now_b, B.u_x.u_mk.r_port);
        if (B.u_x.u_mk.u_reg.dig_stb && B.u_x.u_mk.u_reg.busy)
            $display("    [%0d ms] B's register counts a digit of %0d pulses (caller %o)",
                     now_b, B.u_x.u_mk.u_reg.cnt, B.u_x.u_mk.u_reg.port);
    end
    initial begin
        if (!$value$plusargs("dstop=%d", dstop)) dstop = 64;
        $display("\n  tb_att2r (REAL timers) -- a second claim queued behind one that waits out S_WATCH, dstop %0d%s",
                 dstop, $test$plusargs("fixatt") ? " (+fixatt)" : "");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(30);
        ck(up_a[T11] && up_a[T12] && up_b[T11] && up_b[T12], "links up");

        hook_b[P20] = 1'b1; ms_b(80);
        dial_b(P20, 2);
        pulses_b(P20, 1);
        wait (mks_b == 3'd7);
        $display("    [%0d ms] B's marker in S_WATCH: B20 connected to B21; B20 chatters", now_b);
        chat = 1'b1;

        // ---- first call: A20 1 2 3 -- B claims B11, att waits ---------------
        hook_a[P20] = 1'b1; ms(80);
        dial_a(P20, 1); dial_a(P20, 2); pulses_a(P20, 3);
        wait (B.u_x.u_net.att === 1'b1);
        $display("    [%0d ms] claim 1 (B11) waiting on B's WATCH", now_b);
        ms(136);
        dial_a(P20, 2); dial_a(P20, 2);                 // h s: nobody at B hears them
        wait (reg_a === 1'b0);
        $display("    [%0d ms] A's register free again: A20's call is put through to B11", now_b);

        // ---- second call: A21 1 2 3 3 2 -- intended B32 ---------------------
        hook_a[P21] = 1'b1; ms(80);
        dial_a(P21, 1); dial_a(P21, 2); pulses_a(P21, 3);
        t_ret = now_b;
        fork
            begin wait (B.u_x.u_net.m_want != 2'd0); end
            begin ms(480); end
        join_any
        disable fork;
        tw = now_b;
        ck(B.u_x.u_net.m_want != 2'd0 && B.u_x.u_net.cl_st != 2'd0,
           "claim 2 (B12) is wanted and queued behind claim 1 (cl_st busy)");
        $display("    [%0d ms] claim 2 wanted, %0d ms after b's last make began", now_b, now_b - t_ret + 40);
        ms(760 - (now_b - t_ret));
        h0 = now_b;
        $display("    [%0d ms] A21 begins h = 3; B's WATCH is ended %0d ms into it", now_b, dstop);
        fork
            begin pulses_a(P21, 3); ms(800); pulses_a(P21, 2); ms(800); end
            begin ms_b(dstop); chat = 1'b0; @(posedge t1k_b); @(posedge t1k_b); hook_b[P20] = 1'b1; end
        join
        ms(80);
        rings_b(P32);
        $display("    B32 (dialled) hi %0d lo %0d", hi, lo);
        ck(hi > 50 && lo > 50, "B32, the number A21 dialled, rings");
        rings_b(P22);
        $display("    B22 (not dialled) hi %0d lo %0d", hi, lo);
        ck(!(hi > 50 && lo > 50), "B22, a number nobody dialled, does NOT ring");
        hook_a[P20] = 1'b0; hook_a[P21] = 1'b0; hook_b[P20] = 1'b0; ms(500);
        ck(clash == 0, "no clash on cable B");
        ck(!mko_a && !mko_b && !uno_a && !uno_b, "no queue overflow");
        $display("    takes %0d refusals %0d", n_take, n_refuse);
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #60_000_000_000; $display("  WATCHDOG"); $finish; end

    wire _unused = &{1'b0, rc_a, rc_b, sd_b, hunt_a, hunt_b, res_a, res_b, dirs_a,
                     dirs_b, gl_a, gl_b, nf_b, tx_a, tx_b, e_a, rx_b, cla_b, 1'b0};
endmodule

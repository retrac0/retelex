// tb_c01r -- VERIFY C01 at REAL timers (site_net defaults: T_ARM 16, T_REL 256,
// HIT 8, ID 128, CLR 256, SETTLE 32, NODIG 10000, T_GUARD0 128 ...).
// Derived from work/audit/cableb/tb_attw.v (same plant: A = 2 2, B = 2 3,
// A11-B11 and A12-B12 baseband, A faces E, B faces W with glare).
//
// Dials are conforming: 10 pps 60/40, 720 ms pause (ES 201 187).  B20 dials
// 2 1 (local, B21) and A20 dials 1 2 3, timed (+offs, ms) so that B's monitor
// claims B11 a few ms after B's connect words: inside B's WATCH.
//
//   +scen=1  nobody hangs up; A20 then dials h s = 2 2.  Intent: the claim
//            waits out WATCH and is TAKEN, B22 is connected.
//   +scen=2  CONFORMING DOUBLE ABANDON: A20 hangs up +xa ms after att rises
//            (default 2), B20 hangs up +xb ms after att (default 10), both
//            inside B's 32 ms SETTLE, so B's WATCH ends only at B20's CLR.
//            Is anything left held 3 s later?
//   +scen=3  FAULT: B20's line chatters (4 ms break / 12 ms make: never a
//            pulse, never steady) from B's WATCH until +xb ms after att
//            (default 400); A20 hangs up +xa ms after att.
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

module tb_c01r;
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

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21, P22 = 6'o22;
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

    // REAL timers: every protocol timer at site_net's default
    site_net #(.PHONES(64'h0000_0000_0003_0000), .TRUNKS((64'd1 << T11) | (64'd1 << T12)),
               .TWORD(TW_A), .OWN_E(3'd2), .OWN_B(3'd2)) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(ac_out), .a_out(aa_out), .clk_out(ak_out),
        .c_in(ac_in), .a_in(aa_in), .clk_in(ak_in), .link_up(up_a),
        .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a), .port_busy(busy_a),
        .b_sdata(sd_a), .b_sclk(sc_a), .b_wr(wr_a), .b_clash(cl_a),
        .reg_busy(reg_a), .mk_state(mks_a), .mk_ovf(mko_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(hunt_a),
        .un_ovf(uno_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(.PHONES(64'h0000_0000_0007_0000), .TRUNKS((64'd1 << T11) | (64'd1 << T12)),
               .TWORD(TW_B), .OWN_E(3'd2), .OWN_B(3'd3)) B (
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

    integer n_take = 0, n_refuse = 0, now_b = 0, t_watch = -1, t_wend = -1;
    always @(posedge clk_b) if (t1k_b) now_b = now_b + 1;
    always @(posedge clk_b) begin
        if (B.u_x.u_mk.att_ack) begin
            if (B.u_x.u_mk.push_v != 2'b00) begin
                n_refuse = n_refuse + 1;
                $display("    [%0d ms] B's marker REFUSED the claim on %o", now_b, B.u_x.u_net.att_port);
            end else begin
                n_take = n_take + 1;
                $display("    [%0d ms] B's marker TOOK the claim on %o", now_b, B.u_x.u_net.att_port);
            end
        end
    end
    reg att_d = 1'b0; reg [2:0] mk_d = 3'd0;
    reg b11_rel_seen = 1'b0;
    always @(posedge clk_b) begin
        att_d <= B.u_x.u_net.att;
        mk_d  <= mks_b;
        if (B.u_x.u_net.att && !att_d)
            $display("    [%0d ms] B's unit raises att for %o; B's marker is in state %0d",
                     now_b, B.u_x.u_net.att_port, mks_b);
        if (mks_b == 3'd7 && mk_d != 3'd7) begin
            t_watch = now_b; $display("    [%0d ms] B's marker enters S_WATCH", now_b);
        end
        if (mks_b != 3'd7 && mk_d == 3'd7) begin
            t_wend = now_b; $display("    [%0d ms] B's marker leaves S_WATCH -> %0d", now_b, mks_b);
        end
        if (B.u_x.u_exch.pos[1].u_blk.u_port1.rel)
            $display("    [%0d ms] B11 releases itself (fM/fE fall)", now_b);
    end

    task automatic ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask

    // 10 pps 60/40 pulses; the caller of these adds the pause
    task automatic pulses(input integer site, input [`PW-1:0] p, input integer n);
        integer i;
        begin for (i = 0; i < n; i = i + 1) begin
            if (site == 0) hook_a[p] = 1'b0; else hook_b[p] = 1'b0; ms(60);
            if (site == 0) hook_a[p] = 1'b1; else hook_b[p] = 1'b1; ms(40);
        end end
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

    // B20's chattering line (scen 3): 4 ms break, 12 ms make.  A break under
    // HIT (8) is never a pulse; a make under SETTLE (32) is never steady.
    reg chat = 1'b0;
    always begin
        @(posedge t1k_a);
        if (chat) begin hook_b[P20] = 1'b0; ms(4); hook_b[P20] = 1'b1; ms(12); end
    end

    integer scen, offs, lag, xa, xb, tatt, mk_at_att;
    event go_b;
    wire [`PW-1:0] b11_addr = B.u_x.u_exch.pos[1].u_blk.u_port1.addr;
    wire           b11_bsy  = B.u_x.u_exch.pos[1].u_blk.u_port1.bsy;
    wire           b11_clm  = B.u_x.u_exch.pos[1].u_blk.u_port1.clm;

    initial begin
        if (!$value$plusargs("scen=%d", scen)) scen = 2;
        if (!$value$plusargs("offs=%d", offs)) offs = 1200;
        if (!$value$plusargs("lag=%d", lag)) lag = 9;
        if (!$value$plusargs("xa=%d", xa)) xa = 2;
        if (!$value$plusargs("xb=%d", xb)) xb = (scen == 3) ? 400 : 10;
        $display("\n  tb_c01r -- REAL timers, scen %0d offs %0d lag %0d xa %0d xb %0d%s%s", scen, offs, lag, xa, xb,
                 $test$plusargs("fixatt") ? " +fixatt" : "", $test$plusargs("fixwatch") ? " +fixwatch" : "");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(30);
        ck(up_a[T11] && up_a[T12] && up_b[T11] && up_b[T12], "links up");

        // ALIGNMENT.  B20's s (one pulse) starts 720 ms after its h ends, so
        // its make begins h_end + 780, its digit lands at + 128 and the
        // connect ~3 ms later: WATCH from about h_end + 911.  A20's b (three
        // pulses) makes last at its start + 260 and B claims ~130 ms after:
        // att at b_start + 390.  So b_start = h_end + 521 + lag puts att
        // `lag` ms into B's WATCH.  A20's pause before b is then >= 720 ms
        // (offs >= 1010).
        fork
            begin   // A20: 1 2 at 10 pps, 720 ms pause, then b = 3 on B's cue
                hook_a[P20] = 1'b1; ms(300);
                pulses(0, P20, 1); ms(720);
                pulses(0, P20, 2);
                @(go_b); ms(521 + lag);
                $display("    [%0d ms] A20 starts b", now_b);
                pulses(0, P20, 3);
            end
            begin   // B20: 2 1, started offs ms later
                ms(offs);
                hook_b[P20] = 1'b1; ms(300);
                pulses(1, P20, 2); -> go_b; ms(720);
                pulses(1, P20, 1);
                if (scen == 3) begin wait (mks_b == 3'd7); chat = 1'b1;
                    $display("    [%0d ms] B20 starts to chatter", now_b); end
            end
        join
        fork
            begin wait (B.u_x.u_net.att === 1'b1); end
            begin ms(400); end
        join_any
        disable fork;
        tatt = now_b; mk_at_att = mks_b;
        ck(B.u_x.u_net.att === 1'b1, "B's monitor claimed and B's unit raised att");
        ck(mk_at_att == 3'd7, "and B's marker is in S_WATCH at that moment (the case under test)");

        if (scen == 1) begin
            ms(600);
            $display("    [%0d ms] B11 latch: addr %o bsy %0d clm %0d; B reg busy %0d caller %o",
                     now_b, b11_addr, b11_bsy, b11_clm, reg_b, B.u_x.u_mk.caller);
            ck(n_take == 1 && n_refuse == 0,
               "the claim that waited out WATCH is TAKEN (the design's stated intent)");
            // h s = 2 2 (the pause since b is already ~ 600 + 130 ms)
            pulses(0, P20, 2); ms(720);
            pulses(0, P20, 2); ms(400);
            $display("    [%0d ms] B22 busy %0d, B22 latch addr %o", now_b, busy_b[P22],
                     B.u_x.u_exch.pos[2].u_blk.u_port2.addr);
            ck(busy_b[P22] === 1'b1, "B22 connected: A20's call completed through B");
            hear_a(P20);
            $display("    A20 hears %s", (s0 && !s1) ? "steady 0 (03 cannot-complete or silence)" :
                                          (s1 && !s0) ? "steady 1" : "a mixture");
            hook_a[P20] = 1'b0; hook_b[P20] = 1'b0; ms(3000);
            ck(busy_a == 64'd0 && busy_b == 64'd0 && mon_a == 2'd0 && mon_b == 2'd0,
               "both exchanges idle 3 s after everyone hung up");
        end else begin
            fork
                begin ms(xa); hook_a[P20] = 1'b0;
                      $display("    [%0d ms] A20 hangs up (att + %0d)", now_b, xa); end
                begin ms(xb);
                      if (scen == 3) begin chat = 1'b0; ms(20); end
                      hook_b[P20] = 1'b0;
                      $display("    [%0d ms] B20 hangs up (att + %0d)", now_b, xb); end
            join
            ms(3000);
            $display("    [%0d ms] 3 s after every phone is on-hook: B11 addr %o bsy %0d clm %0d BUSY %0d",
                     now_b, b11_addr, b11_bsy, b11_clm, busy_b[T11]);
            $display("              A11 BUSY %0d, A monitors %b, B monitors %b, A n_nofwd %0d, WATCH %0d..%0d, att %0d",
                     busy_a[T11], mon_a, mon_b, nf_a, t_watch, t_wend, tatt);
            ck(busy_b[T11] === 1'b0, "B11 free again");
            ck(busy_a[T11] === 1'b0, "A11 free again");
            ck(mon_a == 2'd0 && mon_b == 2'd0, "no monitor held at either exchange");
            ck(busy_a == 64'd0 && busy_b == 64'd0 && !reg_a && !reg_b, "both exchanges idle");
        end

        ck(clash == 0, "no clash on cable B");
        ck(!mko_a && !mko_b && !uno_a && !uno_b, "no queue overflow");
        $display("    takes %0d refusals %0d", n_take, n_refuse);
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #20_000_000_000; $display("  WATCHDOG"); $finish; end

    wire _unused = &{1'b0, rc_a, rc_b, sd_b, hunt_a, hunt_b, res_a, res_b, dirs_a,
                     dirs_b, gl_a, gl_b, nf_b, tx_a, tx_b, e_a, e_b, rx_b, cla_a, cla_b, 1'b0};
endmodule

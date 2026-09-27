// tb_fcan -- AUDIT (cableb slice).  The classifier's UNHOLD and the forward
// of the same seizure, on cable B in the wrong order.
//
// net_unit.v C_UNHOLD sets f_cancel "and calls off the forward" -- but only
// F_WANT and F_HUNT look at f_cancel; F_WRITE does not.  The sweep's last
// CONFIRM visit is port 77 (the last read is port 70, whose word ends in
// port 00's bit-time, so CONFIRM counts ports 00..77).  If a seizure on 77
// dies in the millisecond before that visit, one tick carries both h_done
// and C_UNHOLD: the UNHOLD is pushed with f_cancel, F_HUNT (reading f_cancel
// a tick too early) goes to F_WRITE, and F_WRITE pushes the leg and the way
// back AFTER the unhold.  At the real T_ARM (16 ms) the port never armed on
// a ~12 ms seizure, so nothing will ever clear 77 or its leg.
//
// One exchange, V = 2 2.  T_ARM is 16 ms (the real value: the ratio that
// matters is the sweep against T_ARM, and both are then real); the other
// timers are the benches' scale 8.  Trunks, each looped to itself: 77 facing
// W (the bench ORs a blip onto its incoming A), 13 facing E.
//
//   +mode=0 (default)  the blip ends during CONFIRM, at scan == +k (16)
//   +mode=1            control: the blip ends a pass earlier, mid-sweep
//   +fixfc             the knob in net_unit_k.v: F_WRITE honours f_cancel
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

module tb_fcan;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*80-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    localparam [`PW-1:0] T77 = 6'o77, T13 = 6'o13;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};
    localparam [511:0] TW = ({504'd0, WW} << (8*T77)) | ({504'd0, WE} << (8*T13));

    reg  [63:0] hook = 64'd0, tx = 64'd0;
    wire [63:0] rx, e, busy, c_out, a_out, k_out, up;
    reg  [63:0] c_in, a_in, k_in;
    wire        fs, t1k, rc, sd, sc, wr, cl;
    wire        regb, mko, cla, hunt, uno;
    wire [2:0]  mks;
    wire [3:0]  dirs;
    wire [1:0]  res, mon;
    wire [7:0]  gl, nf;
    reg         blip = 1'b0;

    site_net #(.PHONES(64'h0000_0000_0003_0000), .TRUNKS((64'd1 << T77) | (64'd1 << T13)),
               .TWORD(TW), .OWN_E(3'd2), .OWN_B(3'd2),
               .T_ARM(9'd16), .T_REL(9'd32), .RING_ON(13'd64), .RING_OFF(13'd128),
               .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250),
               .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)) V (
        .clk(clk), .rst_n(rst_n), .hook(hook), .tx(tx), .rx(rx), .e(e),
        .c_out(c_out), .a_out(a_out), .clk_out(k_out),
        .c_in(c_in), .a_in(a_in), .clk_in(k_in), .link_up(up),
        .frame_stb(fs), .tick_1k(t1k), .ring_cad_n(rc), .port_busy(busy),
        .b_sdata(sd), .b_sclk(sc), .b_wr(wr), .b_clash(cl),
        .reg_busy(regb), .mk_state(mks), .mk_ovf(mko), .dirs_held(dirs),
        .res_busy(res), .mon_held(mon), .claimed(cla), .hunting(hunt),
        .un_ovf(uno), .n_glare(gl), .n_nofwd(nf));

    always @* begin
        c_in = 64'd0; a_in = 64'd0; k_in = 64'd0;
        c_in[T77] = c_out[T77]; a_in[T77] = a_out[T77] | blip; k_in[T77] = k_out[T77];
        c_in[T13] = c_out[T13]; a_in[T13] = a_out[T13];        k_in[T13] = k_out[T13];
    end

    blog #(.NAME("V")) LV (.clk(clk), .t1k(t1k), .sd(sd), .sc(sc), .wr(wr),
                           .moe(V.u_x.m_oe), .uoe(V.u_x.u_oe));

    integer now = 0;
    always @(posedge clk) if (t1k) now = now + 1;

    // the unit's decisions, as they happen
    always @(posedge clk) begin
        if (V.u_x.u_net.h_done)
            $display("    [%0d ms] sweep done (h_done), h_ok %b, last CONFIRM visit port %o, fst %0d",
                     now, V.u_x.u_net.h_ok, V.u_x.u_net.sp_port, V.u_x.u_net.fst);
        if (V.u_x.u_net.w_cls && V.u_x.u_net.cst == 3'd4)
            $display("    [%0d ms] UNHOLD pushed for %o; fst %0d f_in %o", now,
                     V.u_x.u_net.cls_port, V.u_x.u_net.fst, V.u_x.u_net.f_in);
        if (V.u_x.u_net.w_cls && V.u_x.u_net.cst == 3'd2)
            $display("    [%0d ms] HOLD pushed for %o", now, V.u_x.u_net.cls_port);
        if (V.u_x.u_net.w_fwd)
            $display("    [%0d ms] FORWARD pushed: f_in %o f_ok %b f_cancel %0d", now,
                     V.u_x.u_net.f_in, V.u_x.u_net.f_ok, V.u_x.u_net.f_cancel);
    end

    task automatic ms(input integer n); begin repeat (n) @(posedge t1k); end endtask

    integer mode, k, t0, t1;
    wire [`PW-1:0] p77_addr = V.u_x.u_exch.pos[7].u_blk.u_port7.addr;
    wire           p77_bsy  = V.u_x.u_exch.pos[7].u_blk.u_port7.bsy;
    wire           p77_fm   = V.u_x.u_exch.pos[7].u_blk.u_port7.fm;
    wire [`PW-1:0] p13_addr = V.u_x.u_exch.pos[1].u_blk.u_port3.addr;
    wire           p13_bsy  = V.u_x.u_exch.pos[1].u_blk.u_port3.bsy;

    initial begin
        if (!$value$plusargs("mode=%d", mode)) mode = 0;
        if (!$value$plusargs("k=%d", k)) k = 16;
        $display("\n  tb_fcan -- UNHOLD vs the forward's F_WRITE, mode %0d k %0d%s", mode, k,
                 $test$plusargs("fixfc") ? " (+fixfc)" : "");
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        ms(30);
        ck(up[T77] && up[T13], "both looped links up");

        @(posedge t1k); ms(3);
        blip = 1'b1; t0 = $time / 1000;
        $display("    [%0d ms] seizure on 77 begins", now);
        if (mode == 0) begin
            wait (V.u_x.u_net.hst == 3'd2);          // H_CONFIRM
            wait (V.scan == k[5:0]);
        end else begin
            wait (V.u_x.u_net.hst == 3'd1 && V.u_x.u_net.h_n == 7'd56);
        end
        blip = 1'b0; t1 = $time / 1000;
        $display("    [%0d ms] seizure on 77 ends: it stood %0d us, fM armed %0d",
                 now, (t1 - t0), p77_fm);
        ms(20);
        $display("    [%0d ms] 77 latch addr %o bsy %0d; 13 latch addr %o bsy %0d; res %b mon %b",
                 now, p77_addr, p77_bsy, p13_addr, p13_bsy, res, mon);
        ms(400);
        $display("    [%0d ms] 400 ms on: 77 addr %o bsy %0d BUSY %0d; 13 addr %o bsy %0d BUSY %0d; res %b mon %b",
                 now, p77_addr, p77_bsy, busy[T77], p13_addr, p13_bsy, busy[T13], res, mon);
        ck(busy[T77] === 1'b0, "77, whose seizure died, is not BUSY");
        ck(busy[T13] === 1'b0, "13, the leg forwarded from it, is not BUSY");
        ck(res == 2'd0, "no resolver held");
        ck(mon == 2'd0, "no monitor held");
        ck(!cl && !mko && !uno, "no clash, no overflow");
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #3_000_000_000; $display("  WATCHDOG"); $finish; end

    wire _unused = &{1'b0, rx, e, up, fs, rc, regb, mks, cla, hunt, dirs, gl, nf, 1'b0};
endmodule

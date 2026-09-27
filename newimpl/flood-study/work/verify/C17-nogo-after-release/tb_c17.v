// tb_c17 -- VERIFY bench for C17 (nogo after the caller port released).
// Scratch; not part of the tree.  The harness is work/audit/origin/tb_orig.v's:
// two exchanges, A (code 2 2) and B (3 2), links 11 and 12 E-W up, 13 cut.
//
//   mode bit0  T: A20 dials 1 3 3 (code 33: B hears it, nobody claims), and
//              hangs up X ms after the unit's f2 (b in).  T_CLAIM runs from f2.
//   mode bit1  N: A21 lifts, dials nothing, and hangs up X ms after the
//              register attached.  NODIG runs from the attach.  No unit
//              involved: mini_marker S_COLLECT, as on top_min.
//
// X sweeps x0, x0+step, ... (us, n values).  For each: the times, from the
// reference, of the port's REL, the register's gone, the unit's nogo / the
// register's nodig and the word caller <- 03 on cable B; then whether the
// caller port is left BUSY.  A stuck port is then lifted and hung up to show
// that this clears it.
//
// +define+REAL: real timers (T_REL 256, CLR 256, NODIG 10000, T_CLAIM 2000 ...)
// and a 10 pps dial (60/40 ms, 720 ms pauses).  +define+CLR_FIX=<n>: CLR only.
`timescale 1ns/1ps
`include "exch.vh"

module tb_c17;
    reg clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_b = ~clk_b; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21;
    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, T13 = 6'o13;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};
    localparam [7:0] WN = {2'd0, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WS = {2'd1, 1'b1, 3'b010, 2'b11};
    localparam [511:0] TW_A = ({504'd0, WE} << (8*T11)) | ({504'd0, WE} << (8*T12)) |
                              ({504'd0, WN} << (8*T13));
    localparam [511:0] TW_B = ({504'd0, WW} << (8*T11)) | ({504'd0, WW} << (8*T12)) |
                              ({504'd0, WS} << (8*T13));
    localparam [63:0] TR = (64'd1 << T11) | (64'd1 << T12) | (64'd1 << T13);

`ifdef REAL
    localparam integer BRK = 60, MK = 40, PAUSE = 720;
    localparam [8:0] P_CLR = 9'd256;
`ifdef TREL_FIX
    localparam [8:0] P_TREL = `TREL_FIX;
`else
    localparam [8:0] P_TREL = 9'd256;
`endif
`define SP .PHONES(64'h0000_0000_0007_0000), .TRUNKS(TR), \
        .T_ARM(9'd16), .T_REL(P_TREL), .RING_ON(13'd512), .RING_OFF(13'd1024), \
        .HIT(9'd8), .ID(9'd128), .CLR(P_CLR), .NODIG(16'd10000), \
        .T_GUARD0(16'd128), .T_KEY(16'd5000), .T_CLAIM(16'd2000)
`else
    localparam integer BRK = 12, MK = 8, PAUSE = 100;
`ifdef CLR_FIX
    localparam [8:0] P_CLR = `CLR_FIX;
`else
    localparam [8:0] P_CLR = 9'd32;
`endif
`ifdef TREL_FIX
    localparam [8:0] P_TREL = `TREL_FIX;
`else
    localparam [8:0] P_TREL = 9'd32;
`endif
`define SP .PHONES(64'h0000_0000_0007_0000), .TRUNKS(TR), \
        .T_ARM(9'd2), .T_REL(P_TREL), .RING_ON(13'd64), .RING_OFF(13'd128), \
        .HIT(9'd1), .ID(9'd16), .CLR(P_CLR), .NODIG(16'd1250), \
        .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)
`endif

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

    site_net #(`SP, .TWORD(TW_A), .OWN_E(3'd2), .OWN_B(3'd2), .STRAP_N(4'b0001)) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(ac_out), .a_out(aa_out), .clk_out(ak_out),
        .c_in(ac_in), .a_in(aa_in), .clk_in(ak_in), .link_up(up_a),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(8'd0), .lt_a_in(8'd0), .lt_h_in(8'd0), .lt_k_in(8'd0), .lt_up(),
        .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a), .port_busy(busy_a),
        .b_sdata(sd_a), .b_sclk(sc_a), .b_wr(wr_a), .b_clash(cl_a),
        .reg_busy(reg_a), .mk_state(mks_a), .mk_ovf(mko_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(hunt_a),
        .un_ovf(uno_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(`SP, .TWORD(TW_B), .OWN_E(3'd3), .OWN_B(3'd2), .STRAP_N(4'b0010)) B (
        .clk(clk_b), .rst_n(rst_n), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(bc_out), .a_out(ba_out), .clk_out(bk_out),
        .c_in(bc_in), .a_in(ba_in), .clk_in(bk_in), .link_up(up_b),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(8'd0), .lt_a_in(8'd0), .lt_h_in(8'd0), .lt_k_in(8'd0), .lt_up(),
        .frame_stb(fs_b), .tick_1k(t1k_b), .ring_cad_n(rc_b), .port_busy(busy_b),
        .b_sdata(sd_b), .b_sclk(sc_b), .b_wr(wr_b), .b_clash(cl_b),
        .reg_busy(reg_b), .mk_state(mks_b), .mk_ovf(mko_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(hunt_b),
        .un_ovf(uno_b), .n_glare(gl_b), .n_nofwd(nf_b));

    reg cut13 = 1'b1;
    always @* begin
        ac_in = 64'd0; aa_in = 64'd0; ak_in = 64'd0;
        bc_in = 64'd0; ba_in = 64'd0; bk_in = 64'd0;
        ac_in[T11] = bc_out[T11]; aa_in[T11] = ba_out[T11]; ak_in[T11] = bk_out[T11];
        bc_in[T11] = ac_out[T11]; ba_in[T11] = aa_out[T11]; bk_in[T11] = ak_out[T11];
        ac_in[T12] = bc_out[T12]; aa_in[T12] = ba_out[T12]; ak_in[T12] = bk_out[T12];
        bc_in[T12] = ac_out[T12]; ba_in[T12] = aa_out[T12]; bk_in[T12] = ak_out[T12];
        ac_in[T13] = !cut13 && bc_out[T13]; aa_in[T13] = !cut13 && ba_out[T13]; ak_in[T13] = !cut13 && bk_out[T13];
        bc_in[T13] = !cut13 && ac_out[T13]; ba_in[T13] = !cut13 && aa_out[T13]; bk_in[T13] = !cut13 && ak_out[T13];
    end

`define TMS ($realtime / 1.0e6)
`define P20 A.u_x.u_exch.pos[2].u_blk.u_port0
`define P21 A.u_x.u_exch.pos[2].u_blk.u_port1

    // ---- the observations ------------------------------------------------------
    reg  [`PW-1:0] wp = P20;          // the caller under test
    reg            tr = 1'b0;         // tracing: from the hang-up on
    real t_ref = 0.0, t_rel = -1.0, t_gone = -1.0, t_nogo = -1.0, t_nodig = -1.0, t_w03 = -1.0;

    reg [15:0] sh_a = 16'd0; reg sc_a_d = 1'b0, wr_a_d = 1'b0;
    reg gone_d = 1'b0, nogo_d = 1'b0, nodig_d = 1'b0;
    integer clash = 0;
    always @(posedge clk_a) begin
        sc_a_d <= sc_a; wr_a_d <= wr_a;
        if (cl_a) clash = clash + 1;
        if (sc_a && !sc_a_d) sh_a <= {sh_a[14:0], sd_a};
        if (wr_a && !wr_a_d && sh_a[15] && sh_a[13:8] == wp) begin
            if (tr) $display("  [%9.3f] +%8.3f  A wr dst %02o src %02o bsy %0d clm %0d", `TMS,
                             `TMS - t_ref, sh_a[13:8], sh_a[7:2], sh_a[1], sh_a[0]);
            if (tr && sh_a[7:2] == 6'o03) t_w03 = `TMS - t_ref;
        end
        gone_d <= A.u_x.u_mk.reg_gone; nogo_d <= A.u_x.u_net.nogo; nodig_d <= A.u_x.u_mk.reg_nodig;
        if (tr && A.u_x.u_mk.reg_gone && !gone_d) begin
            t_gone = `TMS - t_ref;
            $display("  [%9.3f] +%8.3f  A r_gone rises (mk %0d)", `TMS, t_gone, mks_a);
        end
        if (tr && A.u_x.u_net.nogo && !nogo_d) begin
            t_nogo = `TMS - t_ref;
            $display("  [%9.3f] +%8.3f  A unit nogo pulse (mk %0d, r_gone %0d)", `TMS, t_nogo, mks_a, A.u_x.u_mk.reg_gone);
        end
        if (tr && A.u_x.u_mk.reg_nodig && !nodig_d) begin
            t_nodig = `TMS - t_ref;
            $display("  [%9.3f] +%8.3f  A r_nodig rises (mk %0d, r_gone %0d)", `TMS, t_nodig, mks_a, A.u_x.u_mk.reg_gone);
        end
        if (tr && wp == P20 && `P20.rel) begin
            t_rel = `TMS - t_ref;
            $display("  [%9.3f] +%8.3f  A20 port REL", `TMS, t_rel);
        end
        if (tr && wp == P21 && `P21.rel) begin
            t_rel = `TMS - t_ref;
            $display("  [%9.3f] +%8.3f  A21 port REL", `TMS, t_rel);
        end
    end

    task automatic msa(input integer n); begin repeat (n) @(posedge t1k_a); end endtask
    task automatic dial_a(input [`PW-1:0] p, input integer d, input integer pause);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; msa(BRK);
                hook_a[p] = 1'b1; msa(MK);
            end
            msa(pause);
        end
    endtask

    integer mode, x0, step, n, i, nstuck = 0, nidle_bad = 0;
    real x;
    reg [5:0] l_addr; reg l_bsy;

    task automatic outcome(input [`PW-1:0] p);
        begin
            tr = 1'b0;
            l_addr = (p == P20) ? `P20.addr : `P21.addr;
            l_bsy  = (p == P20) ? `P20.bsy  : `P21.bsy;
            $display("  RESULT X=%9.3f ms  rel +%8.3f gone +%8.3f nogo +%8.3f nodig +%8.3f w03 +%8.3f  -> port %02o busy %0d latch %02o bsy %0d  %s",
                     x, t_rel, t_gone, t_nogo, t_nodig, t_w03, p, busy_a[p], l_addr, l_bsy,
                     busy_a[p] ? "STUCK BUSY" : "free");
            if (busy_a[p]) begin
                nstuck = nstuck + 1;
                // is it really stuck?  wait a further 2 CLR, then lift and hang up
                msa(P_CLR * 2);
                $display("    still busy %0d after 2 CLR more; lifting", busy_a[p]);
                hook_a[p] = 1'b1; msa(P_CLR);
                $display("    off-hook: busy %0d, latch %02o, register busy %0d (a stuck port is not taken as a caller)",
                         busy_a[p], (p == P20) ? `P20.addr : `P21.addr, reg_a);
                hook_a[p] = 1'b0; msa(P_CLR * 2);
                $display("    hung up: busy %0d", busy_a[p]);
            end
            msa(P_CLR * 4);
            if (!(busy_a == 64'd0 && busy_b == 64'd0 && !reg_a && !reg_b && mks_a == 3'd0 && mks_b == 3'd0 &&
                  dirs_a == 4'd0 && dirs_b == 4'd0 && mon_a == 2'd0 && mon_b == 2'd0)) begin
                nidle_bad = nidle_bad + 1;
                $display("    IDLE? busy_a %h busy_b %h reg %0d%0d mk %0d%0d dirs %h%h mon %b%b",
                         busy_a, busy_b, reg_a, reg_b, mks_a, mks_b, dirs_a, dirs_b, mon_a, mon_b);
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("mode=%d", mode)) mode = 3;
        if (!$value$plusargs("n=%d", n)) n = 10;
        if (!$value$plusargs("step=%d", step)) step = 500;
        $display("\n  tb_c17 -- mode %0d, CLR %0d, T_REL %0d, BRK/MK/PAUSE %0d/%0d/%0d", mode, P_CLR, P_TREL, BRK, MK, PAUSE);
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        msa(40);
        $display("  links: A11 %0d A12 %0d B11 %0d B12 %0d A13 %0d", up_a[T11], up_a[T12], up_b[T11], up_b[T12], up_a[T13]);

        if (mode & 1) begin
            if (!$value$plusargs("tx0=%d", x0)) x0 = 215500;
            $display("\n  T: A20 dials 1 3 3; hangs up X ms after f2 (T_CLAIM from f2)");
            for (i = 0; i < n; i = i + 1) begin
                x = (x0 + i * step) / 1000.0;
                wp = P20; t_rel = -1; t_gone = -1; t_nogo = -1; t_nodig = -1; t_w03 = -1;
                hook_a[P20] = 1'b1; msa(10 + PAUSE / 4);
                dial_a(P20, 1, PAUSE); dial_a(P20, 3, PAUSE); dial_a(P20, 3, 0);
                @(posedge A.u_x.u_net.f2);
                t_ref = `TMS;
                #((x0 + i * step) * 1000.0);
                tr = 1'b1;
                hook_a[P20] = 1'b0;
                $display("  [%9.3f] +%8.3f  A20 hangs up (X = %0.3f ms; unit nst %0d, claimed %0d)", `TMS, `TMS - t_ref, x,
                         A.u_x.u_net.nst, cla_a);
                msa(P_CLR * 3);
                outcome(P20);
            end
        end

        if (mode & 2) begin
            if (!$value$plusargs("nx0=%d", x0)) x0 = 1216000;
            $display("\n  N: A21 lifts, dials nothing; hangs up X ms after the register attached (NODIG from there)");
            for (i = 0; i < n; i = i + 1) begin
                x = (x0 + i * step) / 1000.0;
                wp = P21; t_rel = -1; t_gone = -1; t_nogo = -1; t_nodig = -1; t_w03 = -1;
                hook_a[P21] = 1'b1;
                @(posedge reg_a);
                t_ref = `TMS;
                #((x0 + i * step) * 1000.0);
                tr = 1'b1;
                hook_a[P21] = 1'b0;
                $display("  [%9.3f] +%8.3f  A21 hangs up (X = %0.3f ms; mk %0d, reg port %02o)", `TMS, `TMS - t_ref, x,
                         mks_a, A.u_x.u_mk.reg_port);
                msa(P_CLR * 3);
                outcome(P21);
            end
        end

        $display("\n  SUMMARY mode %0d CLR %0d: %0d stuck of %0d, idle-bad %0d, clash %0d, ovf %0d%0d",
                 mode, P_CLR, nstuck, ((mode & 1) ? n : 0) + ((mode & 2) ? n : 0), nidle_bad, clash, mko_a, uno_a);
        $finish;
    end

    initial begin #400_000_000_000; $display("  TIMEOUT"); $finish; end
    wire _unused = &{1'b0, rc_a, rc_b, hunt_a, hunt_b, gl_a, gl_b, nf_a, nf_b, e_a, e_b, rx_a, rx_b,
                     sd_b, sc_b, wr_b, cl_b, res_a, res_b, mko_b, uno_b, cla_b, 1'b0};
endmodule

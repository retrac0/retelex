// tb_c17f -- C17 skeptic: the FAR-END form.  Scratch; not part of the tree.
// Harness = the verifier's tb_c17.v (itself work/audit/origin/tb_orig.v's):
// A (code 2 2) and B (3 2), links 11 and 12 E-W up, 13 cut.  Scale 8, snapshot.
//
// A20 dials 1 3 2 2: B claims on B11 (A seizes A11, the lowest E trunk), B's
// register takes B11 as a caller (ctx_clm) and collects h = 2.  A20 then stops,
// and hangs up f ms after B's no-digit timer reads NODIG - T_REL - 2, so that
// B11's release falls within a tick or two of B's NODIG.  In S_COLLECT B then
// writes B11 <- 03 with BSY and CLM (mini_marker.v:404-410).  Question: does
// that word land on a released B11, and what does it leave at B and at A?
//
// Both sites are reset between points so that each point starts clean.
`timescale 1ns/1ps
`include "exch.vh"

module tb_c17f;
    reg clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_b = ~clk_b; end

    localparam [`PW-1:0] P20 = 6'o20;
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

    localparam integer BRK = 12, MK = 8, PAUSE = 100;
    localparam [8:0]  P_CLR = 9'd32, P_TREL = 9'd32;
    localparam [15:0] P_NODIG = 16'd1250;
`define SP .PHONES(64'h0000_0000_0007_0000), .TRUNKS(TR), \
        .T_ARM(9'd2), .T_REL(P_TREL), .RING_ON(13'd64), .RING_OFF(13'd128), \
        .HIT(9'd1), .ID(9'd16), .CLR(P_CLR), .NODIG(P_NODIG), \
        .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)

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
`define A20 A.u_x.u_exch.pos[2].u_blk.u_port0
`define A11 A.u_x.u_exch.pos[1].u_blk.u_port1
`define B11 B.u_x.u_exch.pos[1].u_blk.u_port1

    reg  tr = 1'b0;
    real t_ref = 0.0;

    // cable-B sniffers: every word to A20 or A11 at A, to B11 at B
    reg [15:0] sh_a = 16'd0, sh_b = 16'd0;
    reg sc_a_d = 1'b0, wr_a_d = 1'b0, sc_b_d = 1'b0, wr_b_d = 1'b0;
    reg b11m_d = 1'b0, a11m_d = 1'b0, st9_d = 1'b0, bgone_d = 1'b0, bnodig_d = 1'b0;
    reg agone_d = 1'b0, anodig_d = 1'b0;
    always @(posedge clk_a) begin
        sc_a_d <= sc_a; wr_a_d <= wr_a;
        if (sc_a && !sc_a_d) sh_a <= {sh_a[14:0], sd_a};
        if (tr && wr_a && !wr_a_d && sh_a[15] && (sh_a[13:8] == P20 || sh_a[13:8] == T11))
            $display("  [%9.3f] +%8.3f  A wr dst %02o src %02o bsy %0d clm %0d", `TMS, `TMS - t_ref,
                     sh_a[13:8], sh_a[7:2], sh_a[1], sh_a[0]);
        a11m_d <= `A11.a_tx; st9_d <= A.u_x.u_net.st[9];
        agone_d <= A.u_x.u_mk.reg_gone; anodig_d <= A.u_x.u_mk.reg_nodig;
        if (tr && (`A11.a_tx != a11m_d))
            $display("  [%9.3f] +%8.3f  A11 M -> %0d (busy %0d)", `TMS, `TMS - t_ref, `A11.a_tx, busy_a[T11]);
        if (tr && st9_d && !A.u_x.u_net.st[9])
            $display("  [%9.3f] +%8.3f  A unit st[11] cleared (saw A11 M low)", `TMS, `TMS - t_ref);
        if (tr && `A20.rel) $display("  [%9.3f] +%8.3f  A20 port REL", `TMS, `TMS - t_ref);
        if (tr && `A11.rel) $display("  [%9.3f] +%8.3f  A11 port REL", `TMS, `TMS - t_ref);
        if (tr && A.u_x.u_mk.reg_gone && !agone_d)
            $display("  [%9.3f] +%8.3f  A r_gone (mk %0d)", `TMS, `TMS - t_ref, mks_a);
        if (tr && A.u_x.u_mk.reg_nodig && !anodig_d)
            $display("  [%9.3f] +%8.3f  A r_nodig (mk %0d, r_gone %0d)", `TMS, `TMS - t_ref, mks_a, A.u_x.u_mk.reg_gone);
    end
    always @(posedge clk_b) begin
        sc_b_d <= sc_b; wr_b_d <= wr_b;
        if (sc_b && !sc_b_d) sh_b <= {sh_b[14:0], sd_b};
        if (tr && wr_b && !wr_b_d && sh_b[15] && sh_b[13:8] == T11)
            $display("  [%9.3f] +%8.3f  B wr dst %02o src %02o bsy %0d clm %0d", `TMS, `TMS - t_ref,
                     sh_b[13:8], sh_b[7:2], sh_b[1], sh_b[0]);
        b11m_d <= `B11.a_tx;
        bgone_d <= B.u_x.u_mk.reg_gone; bnodig_d <= B.u_x.u_mk.reg_nodig;
        if (tr && (`B11.a_tx != b11m_d))
            $display("  [%9.3f] +%8.3f  B11 M -> %0d", `TMS, `TMS - t_ref, `B11.a_tx);
        if (tr && `B11.rel) $display("  [%9.3f] +%8.3f  B11 port REL", `TMS, `TMS - t_ref);
        if (tr && B.u_x.u_mk.reg_gone && !bgone_d)
            $display("  [%9.3f] +%8.3f  B r_gone (mk %0d)", `TMS, `TMS - t_ref, mks_b);
        if (tr && B.u_x.u_mk.reg_nodig && !bnodig_d)
            $display("  [%9.3f] +%8.3f  B r_nodig (mk %0d, r_gone %0d)", `TMS, `TMS - t_ref, mks_b, B.u_x.u_mk.reg_gone);
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

    integer n, i, f0, step, nstuck_b = 0, nstuck_a = 0, nphantom = 0;
    real f;

    initial begin
        if (!$value$plusargs("n=%d", n)) n = 8;
        if (!$value$plusargs("f0=%d", f0)) f0 = 0;          // us
        if (!$value$plusargs("step=%d", step)) step = 500;  // us
        $display("\n  tb_c17f -- far-end form: CLR %0d, T_REL %0d, NODIG %0d", P_CLR, P_TREL, P_NODIG);
        for (i = 0; i < n; i = i + 1) begin
            f = (f0 + i * step) / 1000.0;
            tr = 1'b0; hook_a = 64'd0;
            rst_n = 1'b0; repeat (20) @(posedge clk_a); rst_n = 1'b1;
            msa(40);
            hook_a[P20] = 1'b1; msa(10 + PAUSE / 4);
            dial_a(P20, 1, PAUSE); dial_a(P20, 3, PAUSE); dial_a(P20, 2, PAUSE); dial_a(P20, 2, 0);
            $display("\n  point %0d: f = %0.3f ms.  claimed %0d, B reg busy %0d port %02o ctx_clm %0d ndig %0d, mk %0d",
                     i, f, cla_a, reg_b, B.u_x.u_mk.reg_port, B.u_x.u_mk.ctx_clm, B.u_x.u_mk.reg_ndig, mks_b);
            // B's no-digit timer at NODIG - T_REL - 2, then f ms, then hang up
            wait (B.u_x.u_mk.u_reg.nd_t == P_NODIG - {7'd0, P_TREL} - 16'd2);
            t_ref = `TMS;
            #(f * 1.0e6);
            tr = 1'b1;
            hook_a[P20] = 1'b0;
            $display("  [%9.3f] +%8.3f  A20 hangs up (B nd_t %0d; A mk %0d, A nst %0d)", `TMS, `TMS - t_ref,
                     B.u_x.u_mk.u_reg.nd_t, mks_a, A.u_x.u_net.nst);
            msa(P_CLR * 3);
            tr = 1'b0;
            msa(P_CLR * 16);            // 512 ms scaled: 4 s real
            $display("  RESULT f=%6.3f  B11 busy %0d latch %02o bsy %0d clm %0d | A11 M %0d busy %0d latch %02o, A mon %b res %b nofwd %0d st11 %0d | A20 busy %0d latch %02o | B reg %0d mk %0d, A reg %0d mk %0d  %s%s",
                     f, busy_b[T11], `B11.addr, `B11.bsy, `B11.clm,
                     `A11.a_tx, busy_a[T11], `A11.addr, mon_a, res_a, nf_a, A.u_x.u_net.st[9],
                     busy_a[P20], `A20.addr, reg_b, mks_b, reg_a, mks_a,
                     busy_b[T11] ? "B11-STUCK " : "", busy_a[P20] ? "A20-STUCK" : "");
            if (busy_b[T11]) nstuck_b = nstuck_b + 1;
            if (busy_a[P20]) nstuck_a = nstuck_a + 1;
            if (mon_a != 2'd0) nphantom = nphantom + 1;
        end
        $display("\n  SUMMARY far-end: B11 stuck %0d of %0d, A holds a phantom (monitor held) %0d, A20 stuck %0d",
                 nstuck_b, n, nphantom, nstuck_a);
        $finish;
    end

    initial begin #200_000_000_000; $display("  TIMEOUT"); $finish; end
    wire _unused = &{1'b0, rc_a, rc_b, hunt_a, hunt_b, gl_a, gl_b, nf_b, e_a, e_b, rx_a, rx_b,
                     cl_a, cl_b, res_b, mko_a, mko_b, uno_a, uno_b, cla_b, up_a, up_b, dirs_a, dirs_b,
                     mon_b, reg_a, 1'b0};
endmodule

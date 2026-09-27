// tb_c06rt -- C06 verifier bench, REAL TIMERS (site_net defaults: HIT 8, ID 128,
// CLR 256, T_ARM 16, T_REL 256, T_GUARD0 128, T_KEY 5000, T_CLAIM 2000, NODIG 10000).
// Scratch; not part of the tree.
//
//   A 2 2   A11,A12 face E  ==  B11,B12 face W   B 3 2
//
// Each trial: A20 off-hook, keys 1 (60 ms break), then holds the make for
// KM ms before e = 1 (60/40), then 720 ms, b = 3, 720 ms, h = 2, 400 ms.
// A20 means 13 (no such exchange).  If e's pulse is lost at B, B's monitors
// read 3 2 = B's own code and claim: a wrong number.  The trial reports what
// the origin did.  +km=<list first> is not parsed: the list is in the bench.
`timescale 1ns/1ps
`include "exch.vh"

module tb_c06rt;
    reg clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #122.070 clk_b = ~clk_b; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21, P22 = 6'o22;
    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};
    localparam [511:0] TW_A = ({504'd0, WE} << (8*T11)) | ({504'd0, WE} << (8*T12));
    localparam [511:0] TW_B = ({504'd0, WW} << (8*T11)) | ({504'd0, WW} << (8*T12));
    localparam [63:0] TR = (64'd1 << T11) | (64'd1 << T12);

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

`define SP .PHONES(64'h0000_0000_0007_0000), .TRUNKS(TR)

    site_net #(`SP, .TWORD(TW_A), .OWN_E(3'd2), .OWN_B(3'd2)) A (
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

    site_net #(`SP, .TWORD(TW_B), .OWN_E(3'd3), .OWN_B(3'd2)) B (
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

    always @* begin
        ac_in = 64'd0; aa_in = 64'd0; ak_in = 64'd0;
        bc_in = 64'd0; ba_in = 64'd0; bk_in = 64'd0;
        ac_in[T11] = bc_out[T11]; aa_in[T11] = ba_out[T11]; ak_in[T11] = bk_out[T11];
        bc_in[T11] = ac_out[T11]; ba_in[T11] = aa_out[T11]; bk_in[T11] = ak_out[T11];
        ac_in[T12] = bc_out[T12]; aa_in[T12] = ba_out[T12]; ak_in[T12] = bk_out[T12];
        bc_in[T12] = ac_out[T12]; ba_in[T12] = aa_out[T12]; bk_in[T12] = ak_out[T12];
    end

`define TMS ($realtime / 1.0e6)

    // ---- what the origin and B do ------------------------------------------------
    real t_go, t_push, t_brk1, t_bcls;
    reg  [3:0] nst_a_d = 0;
    reg  [1:0] mon_b_d = 0;
    reg        cl_a_d = 0, att_b_d = 0;
    reg        o_nogo, o_claim, b_att;
    integer    nbrk;
    always @(posedge clk_a) begin
        nst_a_d <= A.u_x.u_net.nst; cl_a_d <= cla_a;
        if (A.u_x.u_net.nst != nst_a_d)
            $display("  [%9.3f] A nst %0d -> %0d  (ndig %0d)", `TMS, nst_a_d, A.u_x.u_net.nst, A.u_x.u_mk.reg_ndig);
        if (A.u_x.u_net.flood_go) t_go = $realtime;
        if (A.u_x.u_net.nst == 4'd3 && A.u_x.u_net.w_orig) t_push = $realtime;
        if (A.u_x.u_net.r_brk) begin
            nbrk = nbrk + 1;
            if (nbrk == 1) t_brk1 = $realtime;
            $display("  [%9.3f] A r_brk (nst %0d, guarding %0d, tmr %0d)", `TMS, A.u_x.u_net.nst,
                     A.u_x.u_net.guarding, A.u_x.u_net.tmr);
        end
        if (A.u_x.u_net.nogo) begin o_nogo = 1'b1; $display("  [%9.3f] A nogo", `TMS); end
        if (cla_a && !cl_a_d) begin
            o_claim = 1'b1;
            $display("  [%9.3f] A CLAIMED on %02o (guarding %0d)", `TMS, A.u_x.u_net.trunk, A.u_x.u_net.guarding);
        end
    end
    always @(posedge clk_b) begin
        mon_b_d <= mon_b; att_b_d <= B.u_x.u_net.att;
        if (mon_b != mon_b_d) $display("  [%9.3f] B mon_held %b", `TMS, mon_b);
        if (B.u_x.u_net.cst == 3'd1 && t_bcls == 0.0) t_bcls = $realtime;
        if (B.u_x.u_net.att && !att_b_d) begin
            b_att = 1'b1;
            $display("  [%9.3f] B att port %02o: B CLAIMS", `TMS, B.u_x.u_net.att_port);
        end
    end

    task automatic msa(input integer n); begin repeat (n) @(posedge t1k_a); end endtask
    // a digit at 10 pps, 60/40, then `pause` ms more make
    task automatic dial_a(input [`PW-1:0] p, input integer d, input integer pause);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; msa(60);
                hook_a[p] = 1'b1; msa(40);
            end
            msa(pause);
        end
    endtask

    integer kms [0:15];
    integer nk, k, km, wrong, safe, other;
    initial begin
        // the key's make, before e's first break (ms, at tick resolution)
        kms[0] = 128; kms[1] = 129; kms[2] = 130; kms[3] = 131; kms[4] = 132;
        kms[5] = 134; kms[6] = 138; kms[7] = 720;
        nk = 8;
        wrong = 0; safe = 0; other = 0;
        $display("\n  tb_c06rt -- a break before the seizure, at real timers");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        msa(40);
        $display("  links up: A %b%b B %b%b", up_a[T11], up_a[T12], up_b[T11], up_b[T12]);
        for (k = 0; k < nk; k = k + 1) begin
            km = kms[k];
            t_go = 0.0; t_push = 0.0; t_brk1 = 0.0; t_bcls = 0.0; nbrk = 0;
            o_nogo = 1'b0; o_claim = 1'b0; b_att = 1'b0;
            $display("\n  TRIAL %0d: key make %0d ms before e=1; A20 dials 1 1 3 2 (means 13)", k, km);
            hook_a[P20] = 1'b1; msa(300);
            hook_a[P20] = 1'b0; msa(60); hook_a[P20] = 1'b1; msa(km);    // the key
            nbrk = 0;
            dial_a(P20, 1, 720);                                          // e = 1
            dial_a(P20, 3, 720);                                          // b = 3
            dial_a(P20, 2, (km > 200) ? 1500 : 400);                      // h = 2
            $display("  RESULT key-make %0d ms: flood_go->push %.3f ms; flood_go->e's r_brk %.3f ms; e's r_brk %s the push; B saw the rise %.3f ms after the push; origin %s; B claimed %0d",
                     km, (t_push - t_go) / 1.0e6, (t_brk1 - t_go) / 1.0e6,
                     (t_brk1 < t_push) ? "BEFORE" : "after", (t_bcls - t_push) / 1.0e6,
                     o_claim ? "CLAIMED (connects at s)" : (o_nogo ? "NOGO" : "still waiting"), b_att);
            if (o_claim || b_att) wrong = wrong + 1;
            else if (o_nogo) safe = safe + 1;
            else other = other + 1;
            hook_a[P20] = 1'b0; msa(1500);
            $display("  idle? busy_a %h busy_b %h reg %0d%0d nst %0d%0d mon %b%b",
                     busy_a, busy_b, reg_a, reg_b, A.u_x.u_net.nst, B.u_x.u_net.nst, mon_a, mon_b);
        end
        $display("\n  SUMMARY: %0d trials: %0d claimed by 32 (wrong number), %0d abandoned (nogo), %0d other",
                 nk, wrong, safe, other);
        $finish;
    end

    initial begin #200_000_000_000; $display("  TIMEOUT"); $finish; end
    wire _unused = &{1'b0, rc_a, rc_b, hunt_a, hunt_b, gl_a, gl_b, nf_a, nf_b, 1'b0};
endmodule

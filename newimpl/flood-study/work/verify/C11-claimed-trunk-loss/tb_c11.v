`timescale 1ns/1ps
`include "exch.vh"

module tb_c11;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*80-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    // B's crystal: +bppm ppm, started boff ns late (plesiochronous: its
    // tick and frame phases walk against A's through the run)
    integer bppm, boff; real hp_b;
    initial begin
        if (!$value$plusargs("bppm=%d", bppm)) bppm = 0;
        if (!$value$plusargs("boff=%d", boff)) boff = 0;
        hp_b = 122.070 * (1.0 + bppm * 1.0e-6);
        #(40 + boff); forever #(hp_b) clk_b = ~clk_b;
    end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21, P22 = 6'o22;
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

// the ports' release time (an RC-and-'14 on the board, a counter here); CLR stays 32
`ifndef TREL_V
`define TREL_V 9'd32
`endif
`define SP .PHONES(64'h0000_0000_0007_0000), .TRUNKS(TR), \
        .T_ARM(9'd2), .T_REL(`TREL_V), .RING_ON(13'd64), .RING_OFF(13'd128), \
        .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250), \
        .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)

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

    // ---- the cables ------------------------------------------------------------
    reg cut11 = 1'b0, cut12 = 1'b0, cut13 = 1'b1;
    always @* begin
        ac_in = 64'd0; aa_in = 64'd0; ak_in = 64'd0;
        bc_in = 64'd0; ba_in = 64'd0; bk_in = 64'd0;
        ac_in[T11] = !cut11 && bc_out[T11]; aa_in[T11] = !cut11 && ba_out[T11]; ak_in[T11] = !cut11 && bk_out[T11];
        bc_in[T11] = !cut11 && ac_out[T11]; ba_in[T11] = !cut11 && aa_out[T11]; bk_in[T11] = !cut11 && ak_out[T11];
        ac_in[T12] = !cut12 && bc_out[T12]; aa_in[T12] = !cut12 && ba_out[T12]; ak_in[T12] = !cut12 && bk_out[T12];
        bc_in[T12] = !cut12 && ac_out[T12]; ba_in[T12] = !cut12 && aa_out[T12]; bk_in[T12] = !cut12 && ak_out[T12];
        ac_in[T13] = !cut13 && bc_out[T13]; aa_in[T13] = !cut13 && ba_out[T13]; ak_in[T13] = !cut13 && bk_out[T13];
        bc_in[T13] = !cut13 && ac_out[T13]; ba_in[T13] = !cut13 && aa_out[T13]; bk_in[T13] = !cut13 && ak_out[T13];
    end

    // ---- traces ------------------------------------------------------------------
`define TMS ($realtime / 1.0e6)

    // cable B, both sites: every word
    reg [15:0] sh_a = 16'd0, sh_b = 16'd0;
    reg sc_a_d = 1'b0, wr_a_d = 1'b0, sc_b_d = 1'b0, wr_b_d = 1'b0;
    integer nref_a = 0, nref_b = 0;          // refusals: trunk <- 03 with CLAIM
    always @(posedge clk_a) begin
        sc_a_d <= sc_a; wr_a_d <= wr_a;
        if (sc_a && !sc_a_d) sh_a <= {sh_a[14:0], sd_a};
        if (wr_a && !wr_a_d) begin
            $display("  [%9.3f] A wr  g%0d dst %02o src %02o bsy %0d clm %0d", `TMS,
                     sh_a[15], sh_a[13:8], sh_a[7:2], sh_a[1], sh_a[0]);
            if (sh_a[15] && sh_a[7:2] == 6'o03 && sh_a[0] && TR[sh_a[13:8]]) nref_a = nref_a + 1;
        end
    end
    always @(posedge clk_b) begin
        sc_b_d <= sc_b; wr_b_d <= wr_b;
        if (sc_b && !sc_b_d) sh_b <= {sh_b[14:0], sd_b};
        if (wr_b && !wr_b_d) begin
            $display("  [%9.3f] B wr  g%0d dst %02o src %02o bsy %0d clm %0d", `TMS,
                     sh_b[15], sh_b[13:8], sh_b[7:2], sh_b[1], sh_b[0]);
            if (sh_b[15] && sh_b[7:2] == 6'o03 && sh_b[0] && TR[sh_b[13:8]]) nref_b = nref_b + 1;
        end
    end

    // the origin bank, the marker, the claim handshake
    reg [3:0] nst_a_d = 0, nst_b_d = 0; reg [2:0] mk_a_d = 0, mk_b_d = 0;
    reg cl_a_d = 0, cl_b_d = 0, att_a_d = 0, att_b_d = 0;
    reg [1:0] mh_a_d = 0, mh_b_d = 0; reg [2:0] cst_a_d = 0, cst_b_d = 0;
    integer att_in_watch_b = 0, att_in_watch_a = 0;
    always @(posedge clk_a) begin
        nst_a_d <= A.u_x.u_net.nst; mk_a_d <= mks_a; cl_a_d <= cla_a;
        att_a_d <= A.u_x.u_net.att; mh_a_d <= mon_a; cst_a_d <= A.u_x.u_net.cst;
        if (A.u_x.u_net.nst != nst_a_d) $display("  [%9.3f] A nst %0d -> %0d  (ndig %0d)", `TMS, nst_a_d, A.u_x.u_net.nst, A.u_x.u_mk.reg_ndig);
        if (mks_a != mk_a_d) $display("  [%9.3f] A mk  %0d -> %0d  reg_busy %0d", `TMS, mk_a_d, mks_a, reg_a);
        if (cla_a && !cl_a_d) $display("  [%9.3f] A CLAIMED on %02o  (guarding %0d, n_glare %0d)", `TMS,
                                        A.u_x.u_net.trunk, A.u_x.u_net.guarding, gl_a);
        if (A.u_x.u_net.att != att_a_d) $display("  [%9.3f] A att %0d port %02o (mk %0d reg_busy %0d)", `TMS,
                                        A.u_x.u_net.att, A.u_x.u_net.att_port, mks_a, reg_a);
        if (A.u_x.u_net.att && mks_a == 3'd7) att_in_watch_a = att_in_watch_a + 1;
        if (A.u_x.u_mk.att_ack) $display("  [%9.3f] A att_ack: %s  (mk %0d reg_busy %0d)", `TMS,
                                        A.u_x.u_mk.r_attach ? "TAKEN" : "REFUSED", mks_a, reg_a);
        if (mon_a != mh_a_d) $display("  [%9.3f] A mon_held %b", `TMS, mon_a);
        if (A.u_x.u_net.cst != cst_a_d) $display("  [%9.3f] A cls %0d -> %0d port %02o", `TMS, cst_a_d, A.u_x.u_net.cst, A.u_x.u_net.cls_port);
    end
    always @(posedge clk_b) begin
        nst_b_d <= B.u_x.u_net.nst; mk_b_d <= mks_b; cl_b_d <= cla_b;
        att_b_d <= B.u_x.u_net.att; mh_b_d <= mon_b; cst_b_d <= B.u_x.u_net.cst;
        if (B.u_x.u_net.nst != nst_b_d) $display("  [%9.3f] B nst %0d -> %0d  (ndig %0d)", `TMS, nst_b_d, B.u_x.u_net.nst, B.u_x.u_mk.reg_ndig);
        if (mks_b != mk_b_d) $display("  [%9.3f] B mk  %0d -> %0d  reg_busy %0d", `TMS, mk_b_d, mks_b, reg_b);
        if (cla_b && !cl_b_d) $display("  [%9.3f] B CLAIMED on %02o  (guarding %0d, n_glare %0d)", `TMS,
                                        B.u_x.u_net.trunk, B.u_x.u_net.guarding, gl_b);
        if (B.u_x.u_net.att != att_b_d) $display("  [%9.3f] B att %0d port %02o (mk %0d reg_busy %0d)", `TMS,
                                        B.u_x.u_net.att, B.u_x.u_net.att_port, mks_b, reg_b);
        if (B.u_x.u_net.att && mks_b == 3'd7) att_in_watch_b = att_in_watch_b + 1;
        if (B.u_x.u_mk.att_ack) $display("  [%9.3f] B att_ack: %s  (mk %0d reg_busy %0d)", `TMS,
                                        B.u_x.u_mk.r_attach ? "TAKEN" : "REFUSED", mks_b, reg_b);
        if (mon_b != mh_b_d) $display("  [%9.3f] B mon_held %b", `TMS, mon_b);
        if (B.u_x.u_net.cst != cst_b_d) $display("  [%9.3f] B cls %0d -> %0d port %02o", `TMS, cst_b_d, B.u_x.u_net.cst, B.u_x.u_net.cls_port);
    end

    integer clash = 0;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_b) if (cl_b) clash = clash + 1;

    // ---- the bench's hands ---------------------------------------------------------
    task automatic msa(input integer n); begin repeat (n) @(posedge t1k_a); end endtask
    task automatic msb(input integer n); begin repeat (n) @(posedge t1k_b); end endtask

    // a digit: n pulses of 12 ms break, 8 ms make, then `pause` ms more make
    task automatic dial_a(input [`PW-1:0] p, input integer d, input integer pause);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; msa(12);
                hook_a[p] = 1'b1; msa(8);
            end
            msa(pause);
        end
    endtask
    task automatic dial_b(input [`PW-1:0] p, input integer d, input integer pause);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_b[p] = 1'b0; msb(12);
                hook_b[p] = 1'b1; msb(8);
            end
            msb(pause);
        end
    endtask

    reg s0, s1;
    task automatic hear_a(input [`PW-1:0] p);
        integer j;
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 8; j = j + 1) begin
                @(posedge fs_a); @(posedge clk_a);
                if (rx_a[p]) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask
    task automatic hear_b(input [`PW-1:0] p);
        integer j;
        begin s0 = 1'b0; s1 = 1'b0;
            for (j = 0; j < 8; j = j + 1) begin
                @(posedge fs_b); @(posedge clk_b);
                if (rx_b[p]) s1 = 1'b1; else s0 = 1'b1;
            end
        end
    endtask
    integer hi, lo, hia, loa;
    task automatic rings_a(input [`PW-1:0] p);
        integer i;
        begin hia = 0; loa = 0;
            for (i = 0; i < 300; i = i + 1) begin @(posedge t1k_a); if (e_a[p]) hia = hia + 1; else loa = loa + 1; end
        end
    endtask
    task automatic rings_b(input [`PW-1:0] p);
        integer i;
        begin hi = 0; lo = 0;
            for (i = 0; i < 300; i = i + 1) begin @(posedge t1k_b); if (e_b[p]) hi = hi + 1; else lo = lo + 1; end
        end
    endtask
    // is A's port p hearing B's phone q?  toggle q's tx and follow it
    integer fol;
    task automatic follows_ab(input [`PW-1:0] p, input [`PW-1:0] q);
        begin fol = 0;
            tx_b[q] = 1'b1; msa(4); if (rx_a[p] === 1'b1) fol = fol + 1;
            tx_b[q] = 1'b0; msa(4); if (rx_a[p] === 1'b0) fol = fol + 1;
            tx_b[q] = 1'b1; msa(4); if (rx_a[p] === 1'b1) fol = fol + 1;
            tx_b[q] = 1'b0; msa(4); if (rx_a[p] === 1'b0) fol = fol + 1;
        end
    endtask

    integer idle_bad = 0;
    task automatic idle_all(input [8*80-1:0] what);
        begin
            msa(400);
            if (!(busy_a == 64'd0 && busy_b == 64'd0 && !reg_a && !reg_b &&
                  mks_a == 3'd0 && mks_b == 3'd0 && dirs_a == 4'd0 && dirs_b == 4'd0 &&
                  res_a == 2'd0 && res_b == 2'd0 && mon_a == 2'd0 && mon_b == 2'd0 &&
                  A.u_x.u_net.nst == 4'd0 && B.u_x.u_net.nst == 4'd0 &&
                  !A.u_x.u_net.att && !B.u_x.u_net.att)) begin
                idle_bad = idle_bad + 1;
                $display("  IDLE? busy_a %h busy_b %h reg %0d%0d mk %0d%0d dirs %h%h res %b%b mon %b%b",
                         busy_a, busy_b, reg_a, reg_b, mks_a, mks_b, dirs_a, dirs_b, res_a, res_b, mon_a, mon_b);
            end
            ck(1'b1 && busy_a == 64'd0 && busy_b == 64'd0 && !reg_a && !reg_b &&
               mks_a == 3'd0 && mks_b == 3'd0 && dirs_a == 4'd0 && mon_a == 2'd0 && mon_b == 2'd0, what);
        end
    endtask

    // ======================================================================
    // C11 verifier instrumentation
    // ======================================================================
    real t_hup, t_gone, t_low, t_drop, t_nogo20;
    reg  armed_i = 1'b0;
    reg  gone_d = 1'b0;
    integer bad_nogo = 0, fired = 0, gone_first = 0, trial_bad = 0;
    always @(posedge clk_a) begin
        gone_d <= A.u_x.u_net.r_gone;
        if (armed_i) begin
            if (A.u_x.u_net.r_gone && !gone_d && t_gone < 0) t_gone = $realtime;
            // the claimed trunk read low at A, whatever the origin is doing by then
            if (A.u_x.u_net.sp_fresh &&
                (A.u_x.u_net.sp_port == A.u_x.u_net.trunk) && !A.u_x.u_net.sp_m && t_low < 0)
                t_low = $realtime;
            if ((A.u_x.u_net.nst == 4'd7) && (nst_a_d != 4'd7) && t_drop < 0) t_drop = $realtime;
        end
        if (wr_a && !wr_a_d && armed_i && sh_a[15] && sh_a[13:8] == P20 &&
            sh_a[7:2] == 6'o03 && sh_a[1] && t_nogo20 < 0) t_nogo20 = $realtime;
    end

    integer scen, k, ntr, fol2;
    initial begin
        if (!$value$plusargs("scen=%d", scen)) scen = 3;
        if (!$value$plusargs("ntr=%d", ntr)) ntr = 12;
        $display("\n  tb_c11 -- scen %0d, B %0d ppm, B offset %0d ns, %0d trials, port T_REL %0d, CLR 32", scen, bppm, boff, ntr, `TREL_V);
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        msa(30);
        ck(up_a[T11] && up_a[T12] && up_b[T11] && up_b[T12] && !up_a[T13], "links 11, 12 up; 13 cut");

        // ============ S4 (the auditor's): the claimed trunk dies before N_DONE ============
        if (scen & 1) begin
            $display("\n  S4. A20 dials 1 3 2; link 11 cut 80 ms; A20 dials 2 1; then A22 calls B20 on A11");
            hook_a[P20] = 1'b1; msa(10);
            dial_a(P20, 1, 100); dial_a(P20, 3, 100); dial_a(P20, 2, 100);
            $display("  OBS S4: A claimed %0d on %02o", cla_a, A.u_x.u_net.trunk);
            cut11 = 1'b1; msa(80); cut11 = 1'b0; msa(80);
            $display("  OBS S4: after cut: A11 busy %0d, A nst %0d, B reg_busy %0d", busy_a[T11], A.u_x.u_net.nst, reg_b);
            dial_a(P20, 2, 100); dial_a(P20, 1, 0);
            msa(30);
            $display("  OBS S4: A nst %0d reg_a %0d busy A20 %0d", A.u_x.u_net.nst, reg_a, busy_a[P20]);
            hear_a(P20);
            $display("  OBS S4: A20 hears s0 %0d s1 %0d (NOGO tone toggles; silence is constant)", s0, s1);
            hook_a[P22] = 1'b1; msa(10);
            dial_a(P22, 1, 100); dial_a(P22, 3, 100); dial_a(P22, 2, 100);
            dial_a(P22, 2, 100); dial_a(P22, 0, 0);
            msa(30);
            rings_b(P20);
            $display("  OBS S4: B20 ring hi %0d lo %0d; A22's trunk %02o", hi, lo, A.u_x.u_net.trunk);
            hook_b[P20] = 1'b1; msa(30);
            follows_ab(P22, P20); k = fol;
            follows_ab(P20, P20); fol2 = fol;
            $display("  OBS S4: A22 follows B20 %0d/4; A20 follows B20 %0d/4", k, fol2);
            ck(k == 4, "S4: A22's call to B20 is up");
            ck(fol2 < 3, "S4 intent: A20 does NOT hear A22's call (no listen-in)");
            hook_a[P20] = 1'b0; hook_a[P22] = 1'b0; hook_b[P20] = 1'b0;
            idle_all("S4: idle again");
        end

        // ============ S7: the caller hangs up after the claim (the fix's race) ============
        // A20 dials 1 3 2, is claimed by B, hangs up 20 ms + a sub-ms phase
        // later.  The claim falls ~T_REL later at A (B11 clears itself), the
        // register's gone comes ~CLR later.  A NOGO written onto A20 after
        // A20 has released itself leaves A20 BUSY for good.
        if (scen & 2) begin
            for (k = 0; k < ntr; k = k + 1) begin
                hook_a[P20] = 1'b1; msa(10);
                dial_a(P20, 1, 100); dial_a(P20, 3, 100); dial_a(P20, 2, 0);
                wait (cla_a === 1'b1);
                msa(20);
                #(((k * 415) % 1000) * 1000);
                t_gone = -1; t_low = -1; t_drop = -1; t_nogo20 = -1;
                armed_i = 1'b1;
                t_hup = $realtime;
                hook_a[P20] = 1'b0;
                msa(150);
                armed_i = 1'b0;
                $display("  OBS S7.%0d: phase %0d us; gone +%0.3f ms, claim low +%0.3f ms (gone - low %0.3f); N_DROP %s%0.3f; NOGO->A20 %s%0.3f; A20 busy %0d",
                         k, (k * 415) % 1000,
                         (t_gone - t_hup) / 1.0e6, (t_low - t_hup) / 1.0e6, (t_gone - t_low) / 1.0e6,
                         (t_drop < 0) ? "none " : "+", (t_drop < 0) ? 0.0 : (t_drop - t_hup) / 1.0e6,
                         (t_nogo20 < 0) ? "none " : "+", (t_nogo20 < 0) ? 0.0 : (t_nogo20 - t_hup) / 1.0e6,
                         busy_a[P20]);
                if (t_drop >= 0) fired = fired + 1;
                if (t_nogo20 >= 0) bad_nogo = bad_nogo + 1;
                msa(250);
                if (busy_a[P20]) begin
                    trial_bad = trial_bad + 1;
                    $display("  OBS S7.%0d: A20 LEFT BUSY on-hook; the subscriber lifts and replaces to clear it", k);
                    hook_a[P20] = 1'b1; msa(40); hook_a[P20] = 1'b0; msa(100);
                end
                idle_all("S7: idle again");
            end
            $display("  OBS S7: %0d trials; fix fired %0d; NOGO onto A20 after hang-up %0d; A20 left busy %0d",
                     ntr, fired, bad_nogo, trial_bad);
            ck(trial_bad == 0 && bad_nogo == 0, "S7: a caller who hangs up after the claim is never left BUSY");
        end

        ck(clash == 0, "cable B never had two masters at once");
        ck(!mko_a && !mko_b && !uno_a && !uno_b, "no queue refused a write");
        $display("\n  %0d checks, %0d errors, idle-bad %0d.  %s\n", chk, errs, idle_bad,
                 (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #60_000_000_000; $display("  TIMEOUT"); $finish; end

    wire _unused = &{1'b0, rc_a, rc_b, hunt_a, hunt_b, gl_b, nf_b, 1'b0};
endmodule

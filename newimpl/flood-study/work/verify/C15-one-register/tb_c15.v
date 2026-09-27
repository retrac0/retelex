// tb_orig -- AUDIT bench (origin bank + mini marker network half).  Scratch;
// not part of the tree.  Two exchanges, three baseband links:
//
//   A 2 2   A11,A12 face E  ==  B11,B12 face W (glare)   B 3 2
//           A13 faces N     ==  B13 faces S (glare)      -- the N/S link is
//           jumpered at both ends (STRAP_N), and CUT (reads NONE) except in S5
//
// Phones 20, 21, 22 at each.  Timers scaled by 8 as tb_net's.
//
//   S1 (+scen bit0) a claim that arrives while B's marker is in S_WATCH
//   S2 (bit1) two-way: A20 dials B21 and B20 dials A21 at the same time
//   S3 (bit2) a break between the key's recognition and the seizure write
//             (a) control: normal pause   (b) the key's make only 20 ms
//   S4 (bit3) the claimed trunk dies before N_DONE (link cut 80 ms), then the
//             channel is re-used by another call
//   S5 (bit4) the N/S link up: B hears the flood twice and claims twice
//
// Observations are printed as OBS lines; ck() states the DESIGN INTENT, so a
// FAIL here is a reproduction, not a bench bug.
`timescale 1ns/1ps
`include "exch.vh"

module tb_c15;
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

`ifdef REAL
`define SP .PHONES(64'h0000_0000_0007_0000), .TRUNKS(TR), \
        .T_ARM(9'd16), .T_REL(9'd256), .RING_ON(13'd512), .RING_OFF(13'd1024), \
        .HIT(9'd8), .ID(9'd128), .CLR(9'd256), .NODIG(16'd10000), \
        .T_GUARD0(16'd128), .T_KEY(16'd5000), .T_CLAIM(16'd2000)
`define BRK 60
`define MK 40
`define PZ 760
`define SC 8
`else
`define SP .PHONES(64'h0000_0000_0007_0000), .TRUNKS(TR), \
        .T_ARM(9'd2), .T_REL(9'd32), .RING_ON(13'd64), .RING_OFF(13'd128), \
        .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250), \
        .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)
`define BRK 12
`define MK 8
`define PZ 100
`define SC 1
`endif

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

    // C15: when does each caller first hear 03 (eight frames running of 0)?
    reg fsd_a = 1'b0, fsd_b = 1'b0; integer z_a = 0, z_b = 0; reg ng_a = 1'b0, ng_b = 1'b0;
    always @(posedge clk_a) begin
        fsd_a <= fs_a;
        if (fs_a && !fsd_a) begin
            z_a = rx_a[P20] ? 0 : z_a + 1;
            if (hook_a[P20] && z_a == 8 && !ng_a) begin ng_a = 1'b1;
                $display("  [%9.3f] A20 HEARS 03 (cannot-complete)", `TMS); end
            if (!hook_a[P20]) ng_a = 1'b0;
        end
    end
    always @(posedge clk_b) begin
        fsd_b <= fs_b;
        if (fs_b && !fsd_b) begin
            z_b = rx_b[P20] ? 0 : z_b + 1;
            if (hook_b[P20] && z_b == 8 && !ng_b) begin ng_b = 1'b1;
                $display("  [%9.3f] B20 HEARS 03 (cannot-complete)", `TMS); end
            if (!hook_b[P20]) ng_b = 1'b0;
        end
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
                hook_a[p] = 1'b0; msa(`BRK);
                hook_a[p] = 1'b1; msa(`MK);
            end
            msa(pause);
        end
    endtask
    task automatic dial_b(input [`PW-1:0] p, input integer d, input integer pause);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_b[p] = 1'b0; msb(`BRK);
                hook_b[p] = 1'b1; msb(`MK);
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
            for (i = 0; i < 300*`SC; i = i + 1) begin @(posedge t1k_a); if (e_a[p]) hia = hia + 1; else loa = loa + 1; end
        end
    endtask
    task automatic rings_b(input [`PW-1:0] p);
        integer i;
        begin hi = 0; lo = 0;
            for (i = 0; i < 300*`SC; i = i + 1) begin @(posedge t1k_b); if (e_b[p]) hi = hi + 1; else lo = lo + 1; end
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
            msa(400*`SC);
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

    integer scen, k, ph, dl;
    integer taken_b, refused_b, r0a, r0b;
    reg a_hold_phantom;
    initial begin
        if (!$value$plusargs("scen=%d", scen)) scen = 31;
        $display("\n  tb_orig -- origin bank / mini marker network half, scen mask %0d", scen);
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        msa(30);
        ck(up_a[T11] && up_a[T12] && up_b[T11] && up_b[T12] && !up_a[T13], "links 11, 12 up; 13 cut");

        // ===================== S1: a claim during WATCH =========================
        // B20 dials 2 1 (a local call); A20's b completes dl us after B20's s,
        // so B's monitor claims a few ms into B's WATCH (SETTLE after the connect)
        if (scen & 1) begin
            for (k = 0; k < 3; k = k + 1) begin
                dl = 1500 + k * 1500;
                $display("\n  S1.%0d B20 dials 2 1; A20 dials 1 3 2 2 2, its b ending %0d us after B20's s", k, dl);
                att_in_watch_b = 0; r0b = nref_b;
                fork
                    begin hook_a[P20] = 1'b1; msa(10); dial_a(P20, 1, 100); dial_a(P20, 3, 100); end
                    begin hook_b[P20] = 1'b1; msb(10); dial_b(P20, 2, 100); end
                join
                msa(20);
                fork
                    begin #(dl * 1000); dial_a(P20, 2, 100); dial_a(P20, 2, 100); dial_a(P20, 2, 0); end
                    begin #20_000_000; dial_b(P20, 1, 0); end
                join
                msa(40);
                rings_b(P22);
                $display("  OBS S1.%0d: att pending in B WATCH for %0d ticks; B refusals %0d; B22 ring hi %0d lo %0d",
                         k, att_in_watch_b, nref_b - r0b, hi, lo);
                if (att_in_watch_b > 0)
                    ck(nref_b == r0b && hi > 30 && lo > 30,
                       "S1 intent: a claim pending in WATCH waits it out and is TAKEN: B22 rings");
                hook_a[P20] = 1'b0; hook_b[P20] = 1'b0;
                idle_all("S1: idle again");
            end
        end

        // ===================== S2: two-way at once ================================
        if (scen & 2) begin
            $display("\n  S2. A20 dials 1 3 2 2 1 while B20 dials 1 2 2 2 1");
            r0a = nref_a; r0b = nref_b;
            fork
                begin hook_a[P20] = 1'b1; msa(10*`SC);
                      dial_a(P20, 1, `PZ); dial_a(P20, 3, `PZ); dial_a(P20, 2, `PZ);
                      dial_a(P20, 2, `PZ); dial_a(P20, 1, 0); end
                begin msb(3*`SC); hook_b[P20] = 1'b1; msb(10*`SC);
                      dial_b(P20, 1, `PZ); dial_b(P20, 2, `PZ); dial_b(P20, 2, `PZ);
                      dial_b(P20, 2, `PZ); dial_b(P20, 1, 0); end
            join
            $display("  [%9.3f] both callers have dialled their last digit", `TMS);
            msa(30*`SC);
            fork
                begin rings_a(P21); r0a = hia; end
                begin rings_b(P21); end
            join
            $display("  OBS S2: A21 ring-hi %0d, B21 ring-hi %0d; refusals A %0d B %0d; claimed A %0d B %0d",
                     r0a, hi, nref_a, nref_b, cla_a, cla_b);
            ck(nref_a == 0 && nref_b == 0, "S2 intent: neither claim is refused (both called lines are free)");
            hook_a[P20] = 1'b0; hook_b[P20] = 1'b0;
            idle_all("S2: idle again");
        end

        // ===================== S3: a break before the seizure =====================
        if (scen & 4) begin
            $display("\n  S3a. control: A20 dials 1 1 3 2 2 with 100 ms pauses (no exchange 13)");
            hook_a[P20] = 1'b1; msa(10);
            dial_a(P20, 1, 100); dial_a(P20, 1, 100); dial_a(P20, 3, 100);
            dial_a(P20, 2, 100); dial_a(P20, 2, 0);
            msa(300);
            $display("  OBS S3a: B reg_busy %0d, A claimed %0d", reg_b, cla_a);
            ck(!cla_a, "S3a: nobody claims a call to 13");
            hook_a[P20] = 1'b0;
            idle_all("S3a: idle again");

            $display("\n  S3b. A20 keys 1 with a 20 ms make, so e's break begins before the seizure");
            hook_a[P20] = 1'b1; msa(10);
            hook_a[P20] = 1'b0; msa(12); hook_a[P20] = 1'b1; msa(20);   // the key, ID 16 ms
            dial_a(P20, 1, 100);                                         // e = 1: its break
                                                                         // straddles the seizure
            dial_a(P20, 3, 100); dial_a(P20, 2, 100); dial_a(P20, 2, 100);
            $display("  OBS S3b: after 1 1 3 2 2: A claimed %0d on %02o, B reg_busy %0d, B caller %02o",
                     cla_a, A.u_x.u_net.trunk, reg_b, B.u_x.u_mk.caller);
            ck(!cla_a, "S3b intent: a call dialled to 13 is never claimed by 32");
            dial_a(P20, 1, 0);                                           // one digit more
            msa(30);
            rings_b(P21);
            $display("  OBS S3b: B21 ring hi %0d lo %0d", hi, lo);
            ck(!(hi > 30 && lo > 30), "S3b intent: B21 (never dialled) does not ring");
            if (hi > 30) begin
                hook_b[P21] = 1'b1; msa(20);
                follows_ab(P20, P21);
                $display("  OBS S3b: A20 follows B21 %0d/4", fol);
                hook_b[P21] = 1'b0;
            end
            hook_a[P20] = 1'b0;
            idle_all("S3b: idle again");
        end

        // ===================== S4: the claimed trunk dies before N_DONE ===========
        if (scen & 8) begin
            $display("\n  S4. A20 dials 1 3 2; link 11 cut 80 ms; A20 dials 2 1; then A22 calls B20 on A11");
            hook_a[P20] = 1'b1; msa(10);
            dial_a(P20, 1, 100); dial_a(P20, 3, 100); dial_a(P20, 2, 100);
            $display("  OBS S4: A claimed %0d on %02o", cla_a, A.u_x.u_net.trunk);
            cut11 = 1'b1; msa(80); cut11 = 1'b0; msa(80);
            $display("  OBS S4: after cut: A11 busy %0d, A nst %0d, B reg_busy %0d", busy_a[T11], A.u_x.u_net.nst, reg_b);
            dial_a(P20, 2, 100); dial_a(P20, 1, 0);
            msa(30);
            $display("  OBS S4: A nst %0d reg_a %0d  (A20 now latched to A11?)", A.u_x.u_net.nst, reg_a);
            ck(A.u_x.u_net.nst == 4'd0, "S4: A's origin finished");
            // another call takes the channel
            hook_a[P22] = 1'b1; msa(10);
            dial_a(P22, 1, 100); dial_a(P22, 3, 100); dial_a(P22, 2, 100);
            dial_a(P22, 2, 100); dial_a(P22, 0, 0);
            msa(30);
            rings_b(P20);
            $display("  OBS S4: B20 ring hi %0d lo %0d; A22's trunk %02o", hi, lo, A.u_x.u_net.trunk);
            hook_b[P20] = 1'b1; msa(30);
            follows_ab(P22, P20);
            $display("  OBS S4: A22 follows B20 %0d/4", fol);
            k = fol;
            follows_ab(P20, P20);
            $display("  OBS S4: A20 (who dialled B21, whose call died) follows B20 %0d/4", fol);
            ck(k == 4, "S4: A22's call to B20 is up");
            ck(fol < 3, "S4 intent: A20 does NOT hear A22's call (no listen-in)");
            hook_a[P20] = 1'b0; hook_a[P22] = 1'b0; hook_b[P20] = 1'b0;
            idle_all("S4: idle again");
        end

        // ===================== S5: two copies, two claims =========================
        if (scen & 16) begin
            cut13 = 1'b0; msa(30);
            ck(up_a[T13] && up_b[T13], "S5: the N/S link is up");
            for (ph = 0; ph < 3; ph = ph + 1) begin
                $display("\n  S5.%0d A20 dials 1 3 2 2 1 with the N/S link up (phase +%0d us)", ph, ph * 330);
                r0a = nref_b; a_hold_phantom = 1'b0;
                hook_a[P20] = 1'b1; msa(10);
                #(ph * 330_000);
                dial_a(P20, 1, 100);
                ck(dirs_a == 4'b0101, "S5: the key seized one trunk E and one N");
                dial_a(P20, 3, 100);
                dial_a(P20, 2, 0);
                fork
                    begin : watchph
                        repeat (300) begin
                            @(posedge t1k_a);
                            if (mon_a != 2'd0) a_hold_phantom = 1'b1;
                        end
                    end
                    begin msa(100); dial_a(P20, 2, 100); dial_a(P20, 1, 0); end
                join
                msa(30);
                rings_b(P21);
                $display("  OBS S5.%0d: B21 ring hi %0d; B refusals %0d; A monitor attached after the claim %0d; A nofwd %0d",
                         ph, hi, nref_b - r0a, a_hold_phantom, nf_a);
                ck(hi > 30, "S5: B21 rings");
                ck(!a_hold_phantom, "S5 intent: the dropped copy's late claim is not taken at A as a new seizure");
                hook_a[P20] = 1'b0;
                idle_all("S5: idle again");
            end
            cut13 = 1'b1;
        end

        // ===================== S6: a late refusal on a released trunk ===========
        // As S1, but B20's line chatters after the connect (makes of 2 ms <
        // SETTLE), so B's WATCH runs ~150 ms with A's claim pending; A20 hangs
        // up at once after b.  B11 releases itself (fM falls) while the claim
        // waits; the refusal at WATCH's end is then written on a port with no
        // edge left to clear it.
        if (scen & 32) begin
            $display("\n  S6. claim pending in a long WATCH, its caller gone before the refusal");
            att_in_watch_b = 0; r0b = nref_b;
            fork
                begin hook_a[P20] = 1'b1; msa(10); dial_a(P20, 1, 100); dial_a(P20, 3, 100); end
                begin hook_b[P20] = 1'b1; msb(10); dial_b(P20, 2, 100); end
            join
            msa(20);
            fork
                begin #3_000_000; dial_a(P20, 2, 0);
                      wait (cla_a === 1'b1); msa(2); hook_a[P20] = 1'b0;   // A20 gives up at once
                end
                begin #20_000_000; dial_b(P20, 1, 0);
                      wait (mks_b == 3'd7); msb(1);
                      repeat (30) begin hook_b[P20] = 1'b0; msb(3); hook_b[P20] = 1'b1; msb(2); end
                end
            join
            msa(300);
            $display("  OBS S6: att pending in WATCH %0d ticks; B refusals %0d; busy A11 %0d B11 %0d; A mon %b; A cst %0d",
                     att_in_watch_b, nref_b - r0b, busy_a[T11], busy_b[T11], mon_a, A.u_x.u_net.cst);
            hook_b[P20] = 1'b0;
            msa(1500);
            $display("  OBS S6: 1.5 s later: busy A11 %0d B11 %0d; A mon %b; A cst %0d",
                     busy_a[T11], busy_b[T11], mon_a, A.u_x.u_net.cst);
            ck(!busy_b[T11] && !busy_a[T11] && mon_a == 2'd0,
               "S6 intent: nothing is left held once every phone is on-hook and the timers have run");
            idle_all("S6: idle again");
        end

        ck(clash == 0, "cable B never had two masters at once");
        ck(!mko_a && !mko_b && !uno_a && !uno_b, "no queue refused a write");
        $display("\n  %0d checks, %0d errors, idle-bad %0d.  %s\n", chk, errs, idle_bad,
                 (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #40_000_000_000; $display("  TIMEOUT"); $finish; end

    wire _unused = &{1'b0, rc_a, rc_b, hunt_a, hunt_b, gl_b, nf_b, 1'b0};
endmodule

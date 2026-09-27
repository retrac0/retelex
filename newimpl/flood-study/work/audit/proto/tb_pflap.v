// tb_pflap -- AUDIT (protocol slice).  A LINK OUTAGE IS A DIAL PULSE.
// Scratch; not part of the tree.  REAL TIMERS (site_net's defaults: T_ARM 16,
// T_REL 256, HIT 8, ID 128, CLR 256, NODIG 10000, guard 128, T_KEY 5000,
// T_CLAIM 2000), a dial at 10 pps 60/40 and 600 ms between digits.
//
//   A 2 1  A11,A12 face E  ==baseband==  B11,B12 face W (glare)  B 2 3
//   phones 20, 21, 22 at each.  `cut` opens all five conductors of both
//   channels at once (a cable pulled, a connector lifted), both ways.
//
// A baseband card drops A the moment its fifth conductor stops (baseband_card.v
// a_tx = a_s2 && link_up && settled), as network.md 1.1 asks ("Link down ...
// let A fall, so that a call in progress releases").  Hypothesis: an outage
// between HIT (8 ms) and CLR (256 ms) is not a release but a BREAK, and every
// pulse counter beyond the link -- the monitors before the claim, the owner's
// register after it -- counts it as a pulse.  The origin reads its caller
// directly and never sees it.
//
//   +sc bit0  CONTROL.  A20 dials 1 2 2 2 1 (exchange 22: nobody).  No claim;
//             A20 hears cannot-complete 2 s after b; nothing rings at B.
//   +sc bit1  OUTAGE IN b.  The same number; 40 ms of outage 30 ms into the
//             make after b's second pulse.  B's monitor counts b = 3: B (2 3)
//             claims a call dialled to 22, and B21 rings for A20.
//   +sc bit2  OUTAGE IN s, AFTER THE CLAIM.  A20 dials 1 2 3 2 1 (B21); 40 ms of
//             outage 30 ms into the make after s's one pulse.  B's register
//             counts s = 2: B22 rings.
//   +sc bit3  LONG OUTAGE, THEN THE LINK RETURNS MID-DIAL.  A20 dials 1 2 2 3 1
//             (exchange 22: nobody); the cable is out for 500 ms from 200 ms
//             after e's first break -- e's two pulses are through, and the
//             outage ends in the pause after e.
//             B's hold releases (a proper release); when the cable returns, A11
//             still listens to A20, B11 shows M with BUSY clear and nothing
//             says it was ever seized: a fresh seizure.  B's monitor counts
//             from there: b = 2 as e (B's), h = 3 as b (B's), and claims.
//
// Every ck() states the DESIGN INTENT (never a wrong number, never a false
// claim); a FAIL is a reproduction.  OBS lines are observations.
`timescale 1ns/1ps
`include "exch.vh"

module tb_pflap;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*80-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
             else $display("    ok    %0s", what);
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #(122.070 * 1.00002) clk_b = ~clk_b; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21, P22 = 6'o22;
    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12;
    localparam [7:0] WE = {2'd2, 1'b0, 3'b010, 2'b11};      // facing E, no glare
    localparam [7:0] WW = {2'd3, 1'b1, 3'b010, 2'b11};      // facing W, glare
    localparam [511:0] TW_A = ({504'd0, WE} << (8*T11)) | ({504'd0, WE} << (8*T12));
    localparam [511:0] TW_B = ({504'd0, WW} << (8*T11)) | ({504'd0, WW} << (8*T12));
    localparam [63:0] PH = (64'd1 << P20) | (64'd1 << P21) | (64'd1 << P22);

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

    site_net #(.PHONES(PH), .TRUNKS((64'd1 << T11) | (64'd1 << T12)),
               .TWORD(TW_A), .OWN_E(3'd2), .OWN_B(3'd1)) A (
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(ac_out), .a_out(aa_out), .clk_out(ak_out),
        .c_in(ac_in), .a_in(aa_in), .clk_in(ak_in), .link_up(up_a),
        .lt_c_in(8'd0), .lt_a_in(8'd0), .lt_h_in(8'd0), .lt_k_in(8'd0),
        .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(rc_a), .port_busy(busy_a),
        .b_sdata(sd_a), .b_sclk(sc_a), .b_wr(wr_a), .b_clash(cl_a),
        .reg_busy(reg_a), .mk_state(mks_a), .mk_ovf(mko_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(hunt_a),
        .un_ovf(uno_a), .n_glare(gl_a), .n_nofwd(nf_a));

    site_net #(.PHONES(PH), .TRUNKS((64'd1 << T11) | (64'd1 << T12)),
               .TWORD(TW_B), .OWN_E(3'd2), .OWN_B(3'd3)) B (
        .clk(clk_b), .rst_n(rst_n), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(bc_out), .a_out(ba_out), .clk_out(bk_out),
        .c_in(bc_in), .a_in(ba_in), .clk_in(bk_in), .link_up(up_b),
        .lt_c_in(8'd0), .lt_a_in(8'd0), .lt_h_in(8'd0), .lt_k_in(8'd0),
        .frame_stb(fs_b), .tick_1k(t1k_b), .ring_cad_n(rc_b), .port_busy(busy_b),
        .b_sdata(sd_b), .b_sclk(sc_b), .b_wr(wr_b), .b_clash(cl_b),
        .reg_busy(reg_b), .mk_state(mks_b), .mk_ovf(mko_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(hunt_b),
        .un_ovf(uno_b), .n_glare(gl_b), .n_nofwd(nf_b));

    // ---- the cable: A11-B11, A12-B12; `cut` opens every conductor ----------
    reg cut = 1'b0;
    always @* begin
        ac_in = 64'd0; aa_in = 64'd0; ak_in = 64'd0;
        bc_in = 64'd0; ba_in = 64'd0; bk_in = 64'd0;
        ac_in[T11] = !cut && bc_out[T11]; aa_in[T11] = !cut && ba_out[T11]; ak_in[T11] = !cut && bk_out[T11];
        ac_in[T12] = !cut && bc_out[T12]; aa_in[T12] = !cut && ba_out[T12]; ak_in[T12] = !cut && bk_out[T12];
        bc_in[T11] = !cut && ac_out[T11]; ba_in[T11] = !cut && aa_out[T11]; bk_in[T11] = !cut && ak_out[T11];
        bc_in[T12] = !cut && ac_out[T12]; ba_in[T12] = !cut && aa_out[T12]; bk_in[T12] = !cut && ak_out[T12];
    end

    integer clash = 0;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_b) if (cl_b) clash = clash + 1;

    // ---- what B's monitors decided, and when -------------------------------
    // Hierarchical taps, to REPORT only.
    wire [1:0] bm_want = B.u_x.u_net.m_want;
    wire       b_att   = B.u_x.u_net.att;
    wire [`PW-1:0] b_attp = B.u_x.u_net.att_port;
    reg        b_att_d = 1'b0;
    real       t0;
    always @(posedge clk_b) begin
        b_att_d <= b_att;
        if (b_att && !b_att_d)
            $display("  OBS %0.1f ms  B raises att: a claim on B%0o", ($realtime - t0) / 1.0e6, b_attp);
    end
    reg cla_a_d = 1'b0;
    always @(posedge clk_a) begin
        cla_a_d <= cla_a;
        if (cla_a && !cla_a_d)
            $display("  OBS %0.1f ms  A's origin has its claim", ($realtime - t0) / 1.0e6);
    end

    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask

    // 10 pps, 60 ms break / 40 ms make; then the pause, a make of `pause` ms
    integer pause = 600;
    task dial_a(input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; ms(60);
                hook_a[p] = 1'b1; ms(40);
            end
            ms(pause);
        end
    endtask
    // the same digit, with an outage of `len` ms `at` ms into the make that
    // follows its last pulse
    task dial_a_cut(input [`PW-1:0] p, input integer d, input integer at, input integer len);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook_a[p] = 1'b0; ms(60);
                hook_a[p] = 1'b1; if (i < n - 1) ms(40);
            end
            ms(at);
            $display("  OBS %0.1f ms  cable cut for %0d ms", ($realtime - t0) / 1.0e6, len);
            cut = 1'b1; ms(len); cut = 1'b0;
            ms(pause + 40 - at - len);
        end
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

    // does B's port p ring in the next n ms?
    reg rang;
    task ring_b(input [`PW-1:0] p, input integer n);
        integer i;
        begin rang = 1'b0;
            for (i = 0; i < n; i = i + 1) begin @(posedge t1k_a); if (e_b[p]) rang = 1'b1; end
        end
    endtask
    // B21 / B22 written BUSY is B's marker connecting them: nothing else
    // writes a line.  The bell's cadence is 2 s on, 4 s off, too slow to test.
    reg rang21 = 1'b0, rang22 = 1'b0, watch = 1'b0;
    always @(posedge clk_b) if (watch) begin
        if (busy_b[P21]) rang21 <= 1'b1;
        if (busy_b[P22]) rang22 <= 1'b1;
    end
    task ring_both(input integer n);
        begin rang21 = 1'b0; rang22 = 1'b0; watch = 1'b1;
            repeat (n) @(posedge t1k_a);
            watch = 1'b0;
        end
    endtask

    task idle_all(input [8*80-1:0] what);
        begin
            ms(900);
            ck(busy_a == 64'd0 && busy_b == 64'd0 && !reg_a && !reg_b &&
               mks_a == 3'd0 && mks_b == 3'd0 && dirs_a == 4'd0 && dirs_b == 4'd0 &&
               mon_a == 2'd0 && mon_b == 2'd0 && res_a == 2'd0 && res_b == 2'd0, what);
            if (!(busy_a == 64'd0 && busy_b == 64'd0))
                $display("  OBS busy_a %h busy_b %h mon_b %b reg_b %b", busy_a, busy_b, mon_b, reg_b);
        end
    endtask

    integer sc;
    initial begin
        if (!$value$plusargs("sc=%d", sc)) sc = 15;
        $display("\n  tb_pflap -- a link outage is a dial pulse.  sc=%0d, real timers", sc);
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(20);
        ck(up_a[T11] && up_a[T12] && up_b[T11] && up_b[T12], "the links are up");

        // ================= control =============================================
        if (sc[0]) begin
            $display("  --- sc0: CONTROL, A20 dials 1 2 2 2 1, no outage");
            t0 = $realtime;
            hook_a[P20] = 1'b1; ms(300);
            dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 2);
            $display("  OBS %0.1f ms  b is in", ($realtime - t0) / 1.0e6);
            watch = 1'b1;
            dial_a(P20, 2); dial_a(P20, 1);
            ms(600);
            watch = 1'b0;
            hear_a(P20);
            ck(!cla_a, "control: nobody claims a call to exchange 22");
            ck(s0 && !s1, "control: A20 hears cannot-complete after the claim wait");
            ck(!rang21 && !rang22, "control: nothing rings at B");
            hook_a[P20] = 1'b0;
            idle_all("control: both exchanges idle again");
        end

        // ================= an outage inside b ====================================
        if (sc[1]) begin
            $display("  --- sc1: A20 dials 1 2 2 2 1; 40 ms outage in b's last make");
            t0 = $realtime;
            hook_a[P20] = 1'b1; ms(300);
            dial_a(P20, 1); dial_a(P20, 2);
            dial_a_cut(P20, 2, 30, 40);
            $display("  OBS %0.1f ms  b is in (A's register: %0d digits, %h)",
                     ($realtime - t0) / 1.0e6, A.u_x.u_mk.u_reg.ndig, A.u_x.u_mk.u_reg.digits);
            dial_a(P20, 2); dial_a(P20, 1);
            ring_both(3000);
            $display("  OBS B21 rang %0d, B22 rang %0d; A claimed %0d", rang21, rang22, cla_a);
            ck(!cla_a, "outage in b: nobody claims a call dialled to exchange 22");
            ck(!rang21, "outage in b: B21 (23-21, never dialled) does not ring");
            hook_a[P20] = 1'b0;
            idle_all("outage in b: both exchanges idle again");
        end

        // ================= an outage inside s, after the claim ===================
        if (sc[2]) begin
            $display("  --- sc2: A20 dials 1 2 3 2 1; 40 ms outage in s's make");
            t0 = $realtime;
            hook_a[P20] = 1'b1; ms(300);
            dial_a(P20, 1); dial_a(P20, 2); dial_a(P20, 3);
            ck(cla_a, "B claimed the call to 23");
            dial_a(P20, 2);
            dial_a_cut(P20, 1, 30, 40);
            $display("  OBS B's register: digits %h", B.u_x.u_mk.u_reg.digits);
            ring_both(3000);
            $display("  OBS B21 rang %0d, B22 rang %0d", rang21, rang22);
            ck(rang21, "outage in s: B21, the line dialled, rings");
            ck(!rang22, "outage in s: B22 (never dialled) does not ring");
            hook_a[P20] = 1'b0;
            idle_all("outage in s: both exchanges idle again");
        end

        // ================= a long outage, and the link back mid-dial ============
        if (sc[3]) begin
            $display("  --- sc3: A20 dials 1 2 2 3 1; the cable out 500 ms around e");
            t0 = $realtime;
            hook_a[P20] = 1'b1; ms(300);
            dial_a(P20, 1);                                 // the key, and its pause
            fork
                begin dial_a(P20, 2); dial_a(P20, 2); dial_a(P20, 3); dial_a(P20, 1); end
                begin
                    repeat (200) @(posedge t1k_a);
                    $display("  OBS %0.1f ms  cable cut for 500 ms", ($realtime - t0) / 1.0e6);
                    cut = 1'b1; repeat (500) @(posedge t1k_a); cut = 1'b0;
                    $display("  OBS %0.1f ms  cable back", ($realtime - t0) / 1.0e6);
                end
            join
            ms(300);
            $display("  OBS %0.1f ms  all dialled; B mon %b reg %b; A claimed %0d",
                     ($realtime - t0) / 1.0e6, mon_b, reg_b, cla_a);
            ck(!cla_a, "link back mid-dial: nobody claims a call dialled to exchange 22");
            ck(!reg_b, "link back mid-dial: B does not give a register to a call it does not own");
            hook_a[P20] = 1'b0;
            idle_all("link back mid-dial: both exchanges idle again");
        end

        ck(clash == 0, "cable B never had two masters at once");
        ck(!mko_a && !mko_b && !uno_a && !uno_b, "no queue refused a write");
        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #120_000_000_000; $display("  TIMEOUT"); $finish; end

    wire _unused = &{1'b0, rc_a, rc_b, t1k_b, sd_a, sc_a, wr_a, sd_b, sc_b, wr_b, cla_b,
                     hunt_a, hunt_b, gl_a, gl_b, nf_a, nf_b, bm_want, e_a, rx_b, 1'b0};
endmodule

// tb_fl_chain -- the flood study's races and stuck states on a chain: a dial
// break inside a hold watch two hops down, a forward written after its
// seizure died, a resolver whose incoming link was cut, and a phantom
// seizure that nothing dials on.  Flood study REPORT.md §5: C04/C05, C08,
// C09, C10.
//
//     A 2 2  ==11,12==  11,12  B 2 3  blk 3 ======== blk 1  C 2 4
//            faces E    faces W, g    faces E        faces W, g
//       77 faces S, its far end the bench
//
// tb_chain's chain with the B-C link a local eight-channel trunk (tb_lchain's),
// so a cut of that cable mutes B's whole block.  C is a leaf (N S E strapped).
// A is strapped N and W: its trunk 77 faces S and its far end is the bench,
// which drives the far A (s77) and loops the clock, so the bench can time a
// seizure on A to the millisecond.  The A conductor from A's 11 into B's 11
// can be stuck at 1 (`stuck11`), with its clock still running: the link reads
// up.
//
//   1  break in  C04/C05.  A20 dials 1 3 4, code 3 4, nobody's.  Its first
//      the watch break of e is timed off A's own seizure (16 + k ms, past A's
//                guard), so that at C, two hops down, it falls inside C's hold
//                watch: C must wait it out (C_LOW) and count e as 3, not take
//                the make for a fresh seizure and count 2 -- C's own e.
//                Several offsets; at least one must land in C's watch
//   2  a forward C09.  A20 keys 1, and A's origin sweeps; the bench seizes A77
//      that died meanwhile, so A holds it and its forward waits for the
//                origin's sweep.  The seizure dies k ms into the hold: A
//                writes the hold away ID later -- on some k, the tick its
//                forward's sweep ends.  The forward must be called off in
//                F_WRITE, or its one leg is written after the unhold and 77
//                and the leg stay BUSY with nothing to clear them.  A's ports
//                arm at the real T_ARM, 16 ms: a seizure that dies inside it
//                leaves 77 no edge of its own (at 2 ms every seizure arms
//                before it is even held, and 77's own release cleans up)
//   3  a cut     C10.  C20 keys 1: C17 to B37, forwarded to B12, one leg.
//      incoming  The B-C cable is cut and C20 is gone with it.  MUTE_BLK keeps
//                B37 BUSY, so the resolver never sees its incoming go; its leg
//                releases itself.  The resolver must see that and let go, not
//                outlive the call.  Mended, C calls A again
//   4  stuck A   C08.  The A conductor into B11 sticks at 1: a seizure nobody
//                dials on.  B holds B11, a cell, a resolver, and B30/C10 onward.
//                After 2-3 x T_KEY the cell and the resolver let go, the
//                channel onward is freed, and B11 stays parked BUSY until the
//                conductor is mended
//
// Timers scaled by 8, as tb_chain, but for A's T_ARM; the sweeps and cable B
// are not.  That is
// what lets 2 happen at all: at real timers ID (128 ms) is ten sweeps, and an
// unhold can meet a forward's h_done only if the forward waited out ~100 ms,
// which nothing here does.  1 reproduces at this scale because the unscaled
// hops put C's watch 20-30 ms behind A's guard.  About 12 s simulated.
//
// Does not cover: A's own key after 4's fault -- A still sees A11 free and
// takes it into the parked far end (the flood study's killer trunk, not
// fixed); a two-leg forward for 2 or 3 (a two-leg forward is freed by R_GONE
// either way); real timers (tb_fl_fwd).
`timescale 1ns/1ps
`include "exch.vh"

module tb_fl_chain;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*96-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    reg clk_a = 1'b0, clk_b = 1'b0, clk_c = 1'b0, rst_n = 1'b0;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #(122.070 * 1.0001) clk_b = ~clk_b; end
    initial begin #90; forever #(122.070 * 0.9999) clk_c = ~clk_c; end

    localparam [`PW-1:0] P20 = 6'o20, P21 = 6'o21;
    localparam [`PW-1:0] T11 = 6'o11, T12 = 6'o12, T77 = 6'o77;
    localparam [`PW-1:0] B30 = 6'o30, B37 = 6'o37, C10 = 6'o10, C17 = 6'o17;
    localparam [7:0] WE0 = {2'd2, 1'b0, 3'b010, 2'b11};     // facing E
    localparam [7:0] WW1 = {2'd3, 1'b1, 3'b010, 2'b11};     // facing W, glare
    localparam [7:0] WS0 = {2'd1, 1'b0, 3'b010, 2'b11};     // facing S
    localparam [511:0] TW_A = ({504'd0, WE0} << (8*T11)) | ({504'd0, WE0} << (8*T12)) |
                              ({504'd0, WS0} << (8*T77));
    localparam [511:0] TW_B = ({504'd0, WW1} << (8*T11)) | ({504'd0, WW1} << (8*T12));
    localparam [63:0]  TR_A = (64'd1 << T11) | (64'd1 << T12) | (64'd1 << T77);
    localparam [63:0]  TR_B = (64'd1 << T11) | (64'd1 << T12);

    reg  [63:0] hook_a = 0, tx_a = 0, hook_b = 0, tx_b = 0, hook_c = 0, tx_c = 0;
    wire [63:0] rx_a, e_a, rx_b, e_b, rx_c, e_c, busy_a, busy_b, busy_c;
    wire [63:0] ac, aa, ak, bc, ba, bk, up_a, up_b;
    wire [7:0]  lc_b, la_b, lh_b, lk_b, lc_c, la_c, lh_c, lk_c, lup_b, lup_c;
    wire        fs_a, t1k_a, cl_a, cl_b, cl_c;
    wire        reg_a, reg_b, reg_c, creg_a, creg_b, creg_c, mo_a, mo_b, mo_c;
    wire        cla_a, cla_b, cla_c, uo_a, uo_b, uo_c;
    wire [3:0]  dirs_a, dirs_b, dirs_c;
    wire [1:0]  res_a, res_b, res_c, mon_a, mon_b, mon_c;
    wire [7:0]  lz8 = 8'd0;
    reg         s77 = 1'b0;          // the bench's far A on A77
    reg         stuck11 = 1'b0;      // the A conductor into B11 stuck at 1
    reg         lnk = 1'b1;          // the B-C cable

    // ---- the cables: A11-B11, A12-B12 (baseband); A77 to the bench; B blk 3 to C blk 1
    wire [63:0] ac_in = (((bc >> T11) & 64'd3) << T11);
    wire [63:0] aa_in = (((ba >> T11) & 64'd3) << T11) | ((s77 ? 64'd1 : 64'd0) << T77);
    wire [63:0] ak_in = (((bk >> T11) & 64'd3) << T11) | (ak & (64'd1 << T77));
    wire [63:0] bc_in = (((ac >> T11) & 64'd3) << T11);
    wire [63:0] ba_in = (((aa >> T11) & 64'd3) << T11) | ((stuck11 ? 64'd1 : 64'd0) << T11);
    wire [63:0] bk_in = (((ak >> T11) & 64'd3) << T11);
    wire [7:0]  lc_bi = {4'd0, lnk & lc_c[1], 3'd0}, la_bi = {4'd0, lnk & la_c[1], 3'd0};
    wire [7:0]  lh_bi = {4'd0, lnk & lh_c[1], 3'd0}, lk_bi = {4'd0, lnk & lk_c[1], 3'd0};
    wire [7:0]  lc_ci = {6'd0, lnk & lc_b[3], 1'b0}, la_ci = {6'd0, lnk & la_b[3], 1'b0};
    wire [7:0]  lh_ci = {6'd0, lnk & lh_b[3], 1'b0}, lk_ci = {6'd0, lnk & lk_b[3], 1'b0};

`define SITE_PARAMS .PHONES(64'h0000_0000_0003_0000), .OWN_E(3'd2), \
        .T_REL(9'd32), .RING_ON(13'd64), .RING_OFF(13'd128), \
        .HIT(9'd1), .ID(9'd16), .CLR(9'd32), .NODIG(16'd1250), \
        .T_GUARD0(16'd16), .T_KEY(16'd625), .T_CLAIM(16'd250)

    // A's ports arm at the real 16 ms (see 2); everything else is scale 8
    site_net #(`SITE_PARAMS, .TRUNKS(TR_A), .TWORD(TW_A), .OWN_B(3'd2), .T_ARM(9'd16),
               .STRAP_N(4'b1001)) A (                        // N and W strapped
        .clk(clk_a), .rst_n(rst_n), .hook(hook_a), .tx(tx_a), .rx(rx_a), .e(e_a),
        .c_out(ac), .a_out(aa), .clk_out(ak), .c_in(ac_in), .a_in(aa_in), .clk_in(ak_in),
        .link_up(up_a),
        .lt_c_out(), .lt_a_out(), .lt_h_out(), .lt_k_out(),
        .lt_c_in(lz8), .lt_a_in(lz8), .lt_h_in(lz8), .lt_k_in(lz8), .lt_up(),
        .frame_stb(fs_a), .tick_1k(t1k_a), .ring_cad_n(),
        .port_busy(busy_a), .b_sdata(), .b_sclk(), .b_wr(), .b_clash(cl_a),
        .reg_busy(reg_a), .creg_busy(creg_a), .mk_state(), .mk_ovf(mo_a), .dirs_held(dirs_a),
        .res_busy(res_a), .mon_held(mon_a), .claimed(cla_a), .hunting(),
        .un_ovf(uo_a), .n_glare(), .n_nofwd());

    site_net #(`SITE_PARAMS, .TRUNKS(TR_B), .TWORD(TW_B), .OWN_B(3'd3), .T_ARM(9'd2),
               .LTU(8'b0000_1000), .LTWORD({32'd0, WE0, 24'd0})) B (
        .clk(clk_b), .rst_n(rst_n), .hook(hook_b), .tx(tx_b), .rx(rx_b), .e(e_b),
        .c_out(bc), .a_out(ba), .clk_out(bk), .c_in(bc_in), .a_in(ba_in), .clk_in(bk_in),
        .link_up(up_b),
        .lt_c_out(lc_b), .lt_a_out(la_b), .lt_h_out(lh_b), .lt_k_out(lk_b),
        .lt_c_in(lc_bi), .lt_a_in(la_bi), .lt_h_in(lh_bi), .lt_k_in(lk_bi), .lt_up(lup_b),
        .frame_stb(), .tick_1k(), .ring_cad_n(),
        .port_busy(busy_b), .b_sdata(), .b_sclk(), .b_wr(), .b_clash(cl_b),
        .reg_busy(reg_b), .creg_busy(creg_b), .mk_state(), .mk_ovf(mo_b), .dirs_held(dirs_b),
        .res_busy(res_b), .mon_held(mon_b), .claimed(cla_b), .hunting(),
        .un_ovf(uo_b), .n_glare(), .n_nofwd());

    site_net #(`SITE_PARAMS, .TRUNKS(64'd0), .OWN_B(3'd4), .T_ARM(9'd2),
               .STRAP_N(4'b0111),                            // a leaf
               .LTU(8'b0000_0010), .LTWORD({48'd0, WW1, 8'd0})) C (
        .clk(clk_c), .rst_n(rst_n), .hook(hook_c), .tx(tx_c), .rx(rx_c), .e(e_c),
        .c_out(), .a_out(), .clk_out(), .c_in(64'd0), .a_in(64'd0), .clk_in(64'd0),
        .link_up(),
        .lt_c_out(lc_c), .lt_a_out(la_c), .lt_h_out(lh_c), .lt_k_out(lk_c),
        .lt_c_in(lc_ci), .lt_a_in(la_ci), .lt_h_in(lh_ci), .lt_k_in(lk_ci), .lt_up(lup_c),
        .frame_stb(), .tick_1k(), .ring_cad_n(),
        .port_busy(busy_c), .b_sdata(), .b_sclk(), .b_wr(), .b_clash(cl_c),
        .reg_busy(reg_c), .creg_busy(creg_c), .mk_state(), .mk_ovf(mo_c), .dirs_held(dirs_c),
        .res_busy(res_c), .mon_held(mon_c), .claimed(cla_c), .hunting(),
        .un_ovf(uo_c), .n_glare(), .n_nofwd());

    // ---- what the units decide, read by hierarchy to count it ---------------
    localparam [2:0] C_HOLD = 3'd3, C_UNHOLD = 3'd4, C_LOW = 3'd6;
    localparam [1:0] F_WRITE = 2'd3;
    wire [3:0]     a_nst  = A.u_x.u_net.nst;
    wire [15:0]    a_tmr  = A.u_x.u_net.tmr;
    wire [2:0]     a_hst  = A.u_x.u_net.hst;
    wire           a_hown = A.u_x.u_net.h_owner;
    wire [2:0]     a_cst  = A.u_x.u_net.cst;
    wire [`PW-1:0] a_clsp = A.u_x.u_net.cls_port;
    wire [1:0]     a_fst  = A.u_x.u_net.fst;
    wire           a_fcan = A.u_x.u_net.f_cancel;
    wire [`PW-1:0] a_fin  = A.u_x.u_net.f_in;
    wire [2:0]     c_cst  = C.u_x.u_net.cst;

    // C's classifier waited out a low M on a hold (a dial break in its watch)
    integer c_low = 0;
    reg     c_low_d = 1'b0;
    always @(posedge clk_c) begin
        if (c_cst == C_LOW && !c_low_d) c_low = c_low + 1;
        c_low_d <= (c_cst == C_LOW);
    end
    // C's claims, counted at the claim register
    integer c_claims = 0;
    reg     ccr_d = 1'b0;
    always @(posedge clk_c) begin if (creg_c && !ccr_d) c_claims = c_claims + 1; ccr_d <= creg_c; end
    // A's forwarder in F_WRITE for 77 when that seizure's unhold has gone out
    integer a_fw_cancel = 0;
    always @(posedge clk_a) if (a_fst == F_WRITE && a_fcan && a_fin == T77) a_fw_cancel = a_fw_cancel + 1;

    integer clash = 0;
    always @(posedge clk_a) if (cl_a) clash = clash + 1;
    always @(posedge clk_b) if (cl_b) clash = clash + 1;
    always @(posedge clk_c) if (cl_c) clash = clash + 1;

    task ms(input integer n); begin repeat (n) @(posedge t1k_a); end endtask

    // a dial at 50 pps 12/8 and a 100 ms pause: x 0 A, 1 B, 2 C
    task dial(input integer x, input [`PW-1:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                if (x == 0) hook_a[p] = 1'b0; else if (x == 1) hook_b[p] = 1'b0; else hook_c[p] = 1'b0;
                ms(12);
                if (x == 0) hook_a[p] = 1'b1; else if (x == 1) hook_b[p] = 1'b1; else hook_c[p] = 1'b1;
                ms(8);
            end
            ms(100);
        end
    endtask
    task pulses(input integer n);
        integer i;
        begin for (i = 0; i < n; i = i + 1) begin hook_a[P20] = 1'b0; ms(12); hook_a[P20] = 1'b1; ms(8); end end
    endtask

    function idle_now(input dummy);
        idle_now = busy_a == 64'd0 && busy_b == 64'd0 && busy_c == 64'd0 &&
                   !reg_a && !reg_b && !reg_c && !creg_a && !creg_b && !creg_c &&
                   dirs_a == 0 && dirs_b == 0 && dirs_c == 0 &&
                   res_a == 0 && res_b == 0 && res_c == 0 && mon_a == 0 && mon_b == 0 && mon_c == 0;
    endfunction
    task idle_all(input [8*96-1:0] what);
        begin ms(400); ck(idle_now(0), what); end
    endtask

    integer k, n, off, low0, cl0, fw0, bad;
    initial begin
        $display("\n  tb_fl_chain -- a break in the watch, a dead forward, a cut incoming, a stuck A");
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(30);
        ck(up_a[T11] && up_a[T77] && up_b[T11] && lup_b[3] && lup_c[1], "every link is up");

        // ================= 1.  a dial break inside C's hold watch ===============
        $display("  1. A20 dials 1 3 4, its first break 16 + k ms after A's seizure");
        low0 = c_low; bad = 0;
        for (k = 0; k <= 6; k = k + 1) begin
            off = (k == 6) ? 60 : 2 * k;                     // the last: a control, well clear
            cl0 = c_claims;
            hook_a[P20] = 1'b1; ms(10);
            hook_a[P20] = 1'b0; ms(12); hook_a[P20] = 1'b1;  // the key
            n = 0; while (a_nst != 4'd4 && n < 100) begin @(posedge t1k_a); n = n + 1; end
            while (a_nst == 4'd4 && a_tmr < 16 + off) @(posedge clk_a);   // N_NET: A has seized
            pulses(3); ms(100);                              // e = 3
            pulses(4); ms(100);                              // b = 4: code 3 4
            if (c_claims != cl0 || creg_c) bad = bad + 1;
            hook_a[P20] = 1'b0;
            ms(300);
            if (!idle_now(0)) bad = bad + 100;
        end
        ck(c_low > low0, "OBSERVE: in at least one try the first break reached C inside its hold watch");
        ck(bad < 100, "every try left all three exchanges idle");
        ck(bad == 0, "SAFETY: 1 3 4 is nobody's: C (2 4) never claims it, however late the flood");

        // ================= 2.  a forward whose seizure died in its hold ==========
        $display("  2. A20 keys 1; A77 seized during A's origin sweep and dropped k ms into its hold");
        fw0 = a_fw_cancel; bad = 0;
        // Each wait is bounded, and the first try that leaves anything held
        // ends the loop: a later try could not find 77 free to seize.
        for (k = 0; k < 5 && bad == 0; k = k + 1) begin
            hook_a[P20] = 1'b1; ms(10);
            hook_a[P20] = 1'b0; ms(12); hook_a[P20] = 1'b1;  // the key
            n = 0; while (!(a_hst == 3'd1 && !a_hown) && n < 40) begin @(posedge t1k_a); n = n + 1; end
            @(posedge clk_a) s77 = 1'b1;                     // the far end seizes A77
            n = 0; while (!(a_cst == C_HOLD && a_clsp == T77) && n < 163840) begin @(posedge clk_a); n = n + 1; end
            if (n == 163840) bad = bad + 1000;               // never held: 77 was not free
            ms(k);
            s77 = 1'b0;                                      // and is gone
            ms(60);
            if (busy_a[T77] || busy_a[T12] || res_a != 2'd0) bad = bad + 1;
            hook_a[P20] = 1'b0;
            ms(300);
            if (!idle_now(0)) bad = bad + 100;
        end
        ck(a_fw_cancel > fw0, "OBSERVE: once, the unhold went out while the forward waited to write");
        ck(bad == 0, "77, whose seizure died, and the leg forwarded from it are not left BUSY, nor a resolver held");

        // ================= 3.  the incoming link cut under a forward =============
        $display("  3. C20 keys 1 through B; the B-C cable is cut and mended");
        hook_c[P20] = 1'b1; ms(10);
        dial(2, P20, 1);
        ck(busy_b[B37] && busy_b[T12] && res_b != 2'd0,
           "B holds C's seizure on B37 and a resolver carries it on to B12");
        lnk = 1'b0; hook_c[P20] = 1'b0;                      // cut, and C20's call is gone
        ms(10);
        ck(busy_b[B37:B30] == 8'hFF, "MUTE_BLK: B's eight local-trunk ports read BUSY");
        ms(140);
        ck(!busy_b[T12], "B12, the leg, released itself when its E fell");
        ck(res_b == 2'd0, "B's resolver let go of the forward whose incoming link died");
        ms(100);
        lnk = 1'b1;                                          // mended
        ms(800);
        ck(!busy_b[B37] && !busy_c[C17] && res_b == 2'd0, "mended: the channel is free at both ends");
        hook_c[P20] = 1'b1; ms(10);
        dial(2, P20, 1); dial(2, P20, 2); dial(2, P20, 2);   // A's code
        ck(cla_c && creg_a, "and C20 reaches A through B again");
        hook_c[P20] = 1'b0;
        idle_all("3: all three idle");

        // ================= 4.  a seizure nobody dials on =========================
        $display("  4. the A conductor into B11 sticks at 1");
        stuck11 = 1'b1;
        ms(100);
        ck(busy_b[T11] && res_b != 2'd0 && mon_b != 2'd0 && busy_b[B30] && busy_c[C10] && mon_c != 2'd0,
           "OBSERVE: B holds B11, a cell and a resolver, and passed it on: B30, C10 and C's cell");
        ms(1900);                                            // over 3 x T_KEY
        ck(mon_b == 2'd0 && res_b == 2'd0,
           "a seizure nobody dials on does not hold B's monitor or resolver for good");
        ck(!busy_b[B30] && !busy_c[C10] && mon_c == 2'd0, "nor the channel onward, nor C's cell");
        ck(busy_b[T11], "B11 stays parked BUSY: the stuck line is never taken for a caller");
        ck(!reg_b && !creg_b, "and B never gave it a register");
        hook_c[P20] = 1'b1; ms(10);
        dial(2, P20, 1); dial(2, P20, 2); dial(2, P20, 3);   // B's code
        ck(cla_c && creg_b, "C can still reach the network: C20 reaches B");
        hook_c[P20] = 1'b0;
        stuck11 = 1'b0;                                      // mended
        idle_all("4: mended -- everything released");

        ck(clash == 0, "no cable B had two masters driving at once");
        ck(!mo_a && !mo_b && !mo_c && !uo_a && !uo_b && !uo_c, "no queue on any exchange refused a write");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #60_000_000_000; $display("  TIMEOUT"); $fatal(1); end

    wire _unused = &{1'b0, rx_a, e_a, rx_b, e_b, rx_c, e_c, tx_a, tx_b, tx_c, hook_b, fs_a,
                     cla_a, cla_b, dirs_c, res_c, up_b, lup_b, lup_c, B37, C17, 1'b0};
endmodule

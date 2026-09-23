// tb_mini_leaf -- leaf-uplink.md: mini LEAF dials 1, parent offers tone.
//
// Leaf A: LEAF=1, no net.  Parent B: TONE0=1, no net (trunks are callers).
// A.20 dials 1 → uplink → hears B dial tone → dials 2 1 → B.21 rings.
`timescale 1ns/1ps

module tb_mini_leaf;
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer BRK_NS = 12_000_000, MK_NS = 8_000_000;
    localparam integer PAUSE  = 60_000_000;
    localparam integer FR = 15625;

    reg clk_a = 0, clk_b = 0, rst_n = 0;
    always #122.0703 clk_a = ~clk_a;
    initial begin #40; forever #122.0703 clk_b = ~clk_b; end

    wire la_out, lb_out, lock_a, lock_b, fs_a, fs_b, rc_a, rc_b;
    wire dt_a, ng_a, dt_b, ng_b;

    reg  [63:0] hk_a = 0, hk_b = 0;
    reg  [63:0] tx_a = 0, tx_b = 0;
    wire [63:0] rx_a, rx_b;
    wire [63:0] ln_a, ln_b;

    wire [3:0] la_bus, lb_bus, lk_a2, lk_b2;
    assign la_out = la_bus[0];
    assign lb_out = lb_bus[0];
    assign lock_a = lk_a2[0];
    assign lock_b = lk_b2[0];

    // Leaf: digit 1 hunts block-1 trunks.
    mini_net_site #(.HAS_NET(1'b0), .LEAF(1'b1), .NDIR(1),
                    .OWN_E(3'd2), .OWN_B(3'd2),
                    .T_RISE(T_RISE), .T_FALL(T_FALL),
                    .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                    .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(2000))
    A (.clk(clk_a), .rst_n(rst_n),
       .hook(hk_a), .tx(tx_a), .rx(rx_a), .e(ln_a),
       .line_in({3'b0, lb_out}), .line_out(la_bus), .locked(lk_a2),
       .frame_stb(fs_a), .ring_cad_n(rc_a), .dt_bit(dt_a), .ng_bit(ng_a),
       .mon_held(), .got_claim(), .dirs_held(),
       .port_busy(), .reg_busy(), .wq_ovf(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    // Parent: class tone trunk on DIR0 trunks; no flood.
    mini_net_site #(.HAS_NET(1'b0), .LEAF(1'b0), .TONE0(1'b1), .NDIR(1),
                    .OWN_E(3'd2), .OWN_B(3'd3), .DIR0(2'd3), .G0(1'b1),
                    .T_RISE(T_RISE), .T_FALL(T_FALL),
                    .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                    .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(2000))
    B (.clk(clk_b), .rst_n(rst_n),
       .hook(hk_b), .tx(tx_b), .rx(rx_b), .e(ln_b),
       .line_in({3'b0, la_out}), .line_out(lb_bus), .locked(lk_b2),
       .frame_stb(fs_b), .ring_cad_n(rc_b), .dt_bit(dt_b), .ng_bit(ng_b),
       .mon_held(), .got_claim(), .dirs_held(),
       .port_busy(), .reg_busy(), .wq_ovf(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    reg path_en = 0;
    bitpath p_a20b21 (.src_clk(clk_a), .src_fs(fs_a), .src_bit(tx_a[6'o20]),
                      .dst_clk(clk_b), .dst_fs(fs_b), .dst_bit(rx_b[6'o21]), .enable(path_en));
    bitpath p_b21a20 (.src_clk(clk_b), .src_fs(fs_b), .src_bit(tx_b[6'o21]),
                      .dst_clk(clk_a), .dst_fs(fs_a), .dst_bit(rx_a[6'o20]), .enable(path_en));

    // Parent dial tone as heard on leaf 20 (through the uplink).
    reg tone_en = 0;
    bitpath p_dt_local (.src_clk(clk_a), .src_fs(fs_a), .src_bit(dt_a),
                        .dst_clk(clk_a), .dst_fs(fs_a), .dst_bit(rx_a[6'o20]), .enable(tone_en));
    bitpath p_dt_far (.src_clk(clk_b), .src_fs(fs_b), .src_bit(dt_b),
                      .dst_clk(clk_a), .dst_fs(fs_a), .dst_bit(rx_a[6'o20]), .enable(tone_en));
    bitpath p_ng_far (.src_clk(clk_b), .src_fs(fs_b), .src_bit(ng_b),
                      .dst_clk(clk_a), .dst_fs(fs_a), .dst_bit(rx_a[6'o20]), .enable(tone_en));

    always @(posedge clk_a) if (fs_a) begin
        if (hk_a[6'o20]) tx_a[6'o20] <= $random;
        if (hk_a[6'o21]) tx_a[6'o21] <= $random;
    end
    always @(posedge clk_b) if (fs_b) begin
        if (hk_b[6'o20]) tx_b[6'o20] <= $random;
        if (hk_b[6'o21]) tx_b[6'o21] <= $random;
    end

    integer errs = 0, chk = 0;

    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-52s FAIL", what); end
            else $display("     %-52s ok", what);
        end
    endtask

    task dial_a(input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hk_a[6'o20] = 1'b0; #(BRK_NS);
                hk_a[6'o20] = 1'b1; #(MK_NS);
            end
            #(PAUSE);
        end
    endtask

    task hears_local_dt(input string what);
        begin
            p_dt_local.clear; p_dt_far.clear; p_ng_far.clear;
            tone_en = 1; #(3_000_000); tone_en = 0;
            chk = chk + 1;
            if (p_dt_local.best_errs() == 0 && p_dt_far.best_errs() != 0)
                $display("     %-52s ok", what);
            else begin
                errs = errs + 1;
                $display("     %-52s FAIL (local dt %0d far dt %0d of %0d)",
                         what, p_dt_local.best_errs(), p_dt_far.best_errs(),
                         p_dt_local.nbits);
            end
        end
    endtask

    task hears_far_dt(input string what);
        begin
            p_dt_local.clear; p_dt_far.clear; p_ng_far.clear;
            tone_en = 1; #(3_000_000); tone_en = 0;
            chk = chk + 1;
            if (p_dt_far.best_errs() == 0 && p_ng_far.best_errs() != 0)
                $display("     %-52s ok", what);
            else begin
                errs = errs + 1;
                $display("     %-52s FAIL (far dt %0d ng %0d of %0d)",
                         what, p_dt_far.best_errs(), p_ng_far.best_errs(),
                         p_dt_far.nbits);
            end
        end
    endtask

    task ring_b21(input integer n, input string what);
        integer i, hi, lo;
        begin
            hi = 0; lo = 0;
            for (i = 0; i < n; i = i + 1) begin
                #(FR);
                if (ln_b[6'o21] && !rc_b) hi = hi + 1;
                if (!ln_b[6'o21] && rc_b) lo = lo + 1;
            end
            chk = chk + 1;
            if (hi > n/4 && lo > n/4) $display("     %-52s ok", what);
            else begin errs = errs + 1;
                $display("     %-52s FAIL (%0d/%0d)", what, hi, lo); end
        end
    endtask

    initial begin
        $display("MINI-LEAF (RTL) -- leaf-uplink.md: dial 1 -> parent dial tone.\n");
        #4000 rst_n = 1;
        wait (lock_a && lock_b);
        $display("  0. Link up; leaf LEAF, parent offers-tone.\n");

        $display("  1. Leaf 20 lifts -- local dial tone, then dials 1 (uplink).");
        hk_a[6'o20] = 1;
        #(40_000_000);
        hears_local_dt("20 hears leaf dial tone");
        dial_a(1);
        #(80_000_000);
        hears_far_dt("20 hears parent dial tone through the trunk");

        $display("\n  2. From parent tone, 20 dials 2 1 -- B's 21 rings.");
        dial_a(2); dial_a(1);
        #(80_000_000);
        ring_b21(2 * (RING_ON + RING_OFF), "B's 21 rings");
        hk_b[6'o21] = 1;
        #(20_000_000);
        want(ln_b[6'o21], "answered at B");
        path_en = 1; #(6_000_000); path_en = 0;
        p_a20b21.report("speech leaf 20 -> parent 21");
        p_b21a20.report("speech parent 21 -> leaf 20");
        chk = chk + 2;
        if (p_a20b21.best_err != 0 || p_b21a20.best_err != 0) errs = errs + 1;
        hk_b[6'o21] = 0; hk_a[6'o20] = 0; #(80_000_000);
        want(!ln_a[6'o20] && !ln_b[6'o21], "both released");

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #4_000_000_000; $display("  TIMEOUT"); $finish; end
endmodule

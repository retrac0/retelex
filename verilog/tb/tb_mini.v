// tb_mini -- mini-marker.md: two-digit local calls, no card word, no 1-prefix.
`timescale 1ns/1ps

module tb_mini;
    localparam integer HIT = 1, ID = 16, CLR = 32, NODIG = 500;
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer BRK_NS = 12_000_000, MK_NS = 8_000_000;
    localparam integer PAUSE  = 60_000_000;
    localparam [5:0] DIALTONE = 6'o01, NOGO = 6'o03;
    localparam [5:0] P20 = 6'o20, P21 = 6'o21, P22 = 6'o22, P25 = 6'o25;

    reg clk = 0, rst_n = 0;
    always #122.0703 clk = ~clk;

    reg  [63:0] hook = 0, tx = 0;
    wire [63:0] rx, e, port_busy;
    wire        reg_busy, wq_ovf;
    wire        wr_stb, wr_bsy, wr_clm;
    wire [5:0]  wr_dst, wr_src;
    wire        frame_stb, fill, ring_cad_n, dt_bit, ng_bit;

    mini_site #(.T_RISE(T_RISE), .T_FALL(T_FALL),
                .RING_ON(RING_ON), .RING_OFF(RING_OFF),
                .HIT(HIT), .ID(ID), .CLR(CLR), .NODIG(NODIG))
    S (.clk(clk), .rst_n(rst_n),
       .hook(hook), .tx(tx), .rx(rx), .e(e),
       .frame_stb(frame_stb), .tick_1k(), .fill(fill), .ring_cad_n(ring_cad_n),
       .dt_bit(dt_bit), .ng_bit(ng_bit),
       .port_busy(port_busy), .reg_busy(reg_busy), .wq_ovf(wq_ovf),
       .wr_stb(wr_stb), .wr_dst(wr_dst), .wr_src(wr_src),
       .wr_bsy(wr_bsy), .wr_clm(wr_clm));

    reg [5:0] last_dt = 6'h3f, last_ng = 6'h3f, last_off = 6'h3f;
    always @(posedge clk) begin
        if (wr_stb && wr_bsy && wr_src == DIALTONE) last_dt <= wr_dst;
        if (wr_stb && wr_bsy && wr_src == NOGO)     last_ng <= wr_dst;
        if (wr_stb && wr_bsy && wr_src == 6'o00)    last_off <= wr_dst;
    end

    integer errs = 0, chk = 0;
    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-56s FAIL", what); end
            else $display("     %-56s ok", what);
            $fflush();
        end
    endtask

    task dial(input [5:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook[p] = 1'b0; #BRK_NS;
                hook[p] = 1'b1; #MK_NS;
            end
            #PAUSE;
        end
    endtask

    task await_dt(input [5:0] who);
        integer t;
        begin
            last_dt = 6'h3f; t = 0;
            while (last_dt !== who && t < 200) begin #1_000_000; t = t + 1; end
        end
    endtask

    task await_ng(input [5:0] who);
        integer t;
        begin
            t = 0;
            while (last_ng !== who && t < 800) begin #1_000_000; t = t + 1; end
        end
    endtask

    task hang_all;
        begin
            hook = 0; tx = 0; #400_000_000;
        end
    endtask

    integer t;
    reg seen_ring;

    initial begin
        $display("MINI (RTL) -- mini-marker.md: two lines, one register, no word.\n");
        #4000 rst_n = 1;
        #50_000_000;

        // ---- 20 dials 21: ring, answer, speech, hang up both ----
        $display("  20 calls 21");
        hook[P20] = 1'b1;
        await_dt(P20);
        want(last_dt === P20 && reg_busy, "20 got dial tone");
        dial(P20, 2); dial(P20, 1);
        #100_000_000;
        want(port_busy[P20] && port_busy[P21] && !reg_busy,
             "20 dials 21: both busy, register free");
        want(!wq_ovf, "write queue did not overrun");

        seen_ring = 0;
        for (t = 0; t < 80 && !seen_ring; t = t + 1) begin
            if (e[P21] === 1'b1) seen_ring = 1;
            #1_000_000;
        end
        want(seen_ring, "21 rings");

        hook[P21] = 1'b1;
        #20_000_000;
        tx[P20] = 1'b1; tx[P21] = 1'b0;
        #5_000_000;
        want(rx[P21] === 1'b1 && rx[P20] === 1'b0, "answered: speech 20 -> 21");
        tx[P20] = 1'b0; tx[P21] = 1'b1;
        #5_000_000;
        want(rx[P20] === 1'b1 && rx[P21] === 1'b0, "answered: speech 21 -> 20");
        hang_all;
        want(port_busy == 64'd0 && !reg_busy, "both hang up: nothing held");

        // ---- 21 dials 20, caller hangs up first ----
        $display("  21 calls 20, caller first");
        hook[P21] = 1'b1;
        await_dt(P21);
        want(last_dt === P21, "21 got dial tone");
        dial(P21, 2); dial(P21, 0);
        #100_000_000;
        want(port_busy[P20] && port_busy[P21], "21 dials 20 connects");
        hook[P20] = 1'b1;
        #20_000_000;
        last_dt = 6'h3f;
        hook[P21] = 1'b0;                    // caller hangs up first
        #400_000_000;
        want(!port_busy[P21], "caller released");
        // 20 still off-hook with an idle latch: a new call request
        t = 0;
        while (last_dt !== P20 && t < 200) begin #1_000_000; t = t + 1; end
        want(last_dt === P20 && reg_busy, "20 left off-hook gets dial tone");
        hang_all;
        want(port_busy == 64'd0 && !reg_busy, "then 20 hangs up: idle");

        // ---- busy ----
        $display("  busy");
        hook[P20] = 1'b1;
        await_dt(P20);
        dial(P20, 2); dial(P20, 1);
        #100_000_000;
        want(port_busy[P21], "setup: 21 busy");
        hook[P22] = 1'b1;
        await_dt(P22);
        last_ng = 6'h3f;
        dial(P22, 2); dial(P22, 1);
        await_ng(P22);
        want(last_ng === P22, "22 dials busy 21 -> cannot-complete");
        hang_all;

        // ---- self ----
        $display("  self");
        hook[P20] = 1'b1;
        await_dt(P20);
        last_ng = 6'h3f;
        dial(P20, 2); dial(P20, 0);
        await_ng(P20);
        want(last_ng === P20, "20 dials itself -> cannot-complete");
        hang_all;

        // ---- empty number: no port circuit at 25, treated as free ----
        $display("  empty");
        hook[P20] = 1'b1;
        await_dt(P20);
        dial(P20, 2); dial(P20, 5);
        #100_000_000;
        want(port_busy[P20] && !port_busy[P25] && !reg_busy,
             "20 dials 25: caller patched, empty latch ignored");
        hang_all;

        // ---- first keys 0, 8, 9 ----
        $display("  first keys");
        hook[P20] = 1'b1;
        await_dt(P20);
        last_ng = 6'h3f;
        dial(P20, 0);
        await_ng(P20);
        want(last_ng === P20, "0 -> cannot-complete");
        hang_all;

        hook[P20] = 1'b1;
        await_dt(P20);
        last_ng = 6'h3f;
        dial(P20, 8);
        await_ng(P20);
        want(last_ng === P20, "8 -> cannot-complete");
        hang_all;

        hook[P20] = 1'b1;
        await_dt(P20);
        last_ng = 6'h3f;
        dial(P20, 9);
        await_ng(P20);
        want(last_ng === P20, "9 -> cannot-complete");
        hang_all;

        // ---- 1 is a highway, not a prefix ----
        $display("  highway 1");
        hook[P20] = 1'b1;
        await_dt(P20);
        last_off = 6'h3f; last_ng = 6'h3f;
        dial(P20, 1);
        #50_000_000;
        want(last_off === P20 && last_ng !== P20 && reg_busy,
             "1 dropped dial tone, still collecting (not a prefix)");
        hang_all;

        // ---- abandon mid-dial ----
        $display("  abandon");
        hook[P20] = 1'b1;
        await_dt(P20);
        dial(P20, 2);                        // highway in, waiting for s
        hook[P20] = 1'b0;
        #400_000_000;
        want(!reg_busy && !port_busy[P20], "hang up mid-dial: register and port free");

        // ---- no-digit timeout ----
        $display("  nodig");
        hook[P20] = 1'b1;
        await_dt(P20);
        last_ng = 6'h3f;
        await_ng(P20);
        want(last_ng === P20 && !reg_busy, "nothing dialled -> cannot-complete, register free");
        want(port_busy[P20], "port stays busy until hung up");
        hang_all;
        want(port_busy == 64'd0 && !reg_busy && !wq_ovf, "final idle");

        $display("");
        if (errs) begin
            $display("MINI: %0d of %0d failed", errs, chk);
            $fatal(1);
        end
        $display("MINI: %0d checks ok", chk);
        $finish;
    end
endmodule

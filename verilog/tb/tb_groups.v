// tb_groups -- groups.md §2: a port answers to a number.
//
//   1. Hunt group: 21 answers to 20.  23 dials 20 while 20 is busy → 21.
//   2. Digit 0 → pilot 04.
//   3. Cover: 04 busy; 21 answers to 04; dial 0 → 21.
//   4. Dual membership: 22 answers to 20 and 25; dial 25 → 22.
//   5. Field B K: 21 answers to 04 with K; busy 04 → 21; unequipped 04 skips K.
`timescale 1ns/1ps

module tb_groups;
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 64, T_FALL = 2048;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer BRK_NS = 12_000_000, MK_NS = 8_000_000;
    localparam integer PAUSE  = 60_000_000;
    localparam [5:0] DIALTONE = 6'o01;

    // answers to port N: {FF, hs, 2'b01}
    localparam [15:0] ANS20 = {8'hFF, 6'o20, 2'b01};
    localparam [15:0] ANS04 = {8'hFF, 6'o04, 2'b01};
    // Dual: primary answers-to 20, tag 01 payload 25
    localparam [15:0] DUAL20_25 = {6'o25, 2'b01, 6'o20, 2'b01};
    // Field B K-only (busy owner): LUK = 001, MBZ 000
    localparam [15:0] ANS04_K = {6'b001000, 2'b10, 6'o04, 2'b01};
    // Field B U-only (unequipped owner)
    localparam [15:0] ANS04_U = {6'b010000, 2'b10, 6'o04, 2'b01};

    reg clk = 0, rst_n = 0;
    always #122.0703 clk = ~clk;

    reg  [63:0] hook = 0, tx = 0;
    wire [63:0] rx, e, port_busy;
    wire [1:0]  regs_busy;
    wire        wr_stb, wr_bsy, wr_clm;
    wire [5:0]  wr_dst, wr_src;

    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(2'd2),
               .LINE_PORTS(64'h0000_0000_000F_0010),
               .LINE_WORD_04(16'hFFFF),
               .LINE_WORD_20(16'hFFFF),
               .LINE_WORD_21(ANS20),
               .LINE_WORD_22(DUAL20_25),
               .LINE_WORD_23(16'hFFFF),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250),
               .NREG(2), .NMON(1), .NRES(1))
    A (.clk(clk), .rst_n(rst_n),
       .hook(hook), .tx(tx), .rx(rx), .e(e),
       .line_in(1'b0), .line_out(), .locked(),
       .frame_stb(), .ring_cad_n(), .dt_bit(), .ng_bit(),
       .mon_held(), .mon_busy(), .mon_full(), .got_claim(), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(port_busy), .regs_busy(regs_busy),
       .wq_ovf(), .n_defer(), .ev_cnt(),
       .wr_stb(wr_stb), .wr_dst(wr_dst), .wr_src(wr_src),
       .wr_bsy(wr_bsy), .wr_clm(wr_clm));

    reg  [63:0] hook2 = 0, tx2 = 0;
    wire [63:0] pb2;
    wire        wr2_stb, wr2_bsy, wr2_clm;
    wire [5:0]  wr2_src, wr2_dst;
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(2'd2),
               .LINE_PORTS(64'h0000_0000_0003_0010),
               .LINE_WORD_04(16'hFFFF),
               .LINE_WORD_20(16'hFFFF),
               .LINE_WORD_21(ANS04),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250),
               .NREG(2), .NMON(1), .NRES(1))
    B (.clk(clk), .rst_n(rst_n),
       .hook(hook2), .tx(tx2), .rx(), .e(),
       .line_in(1'b0), .line_out(), .locked(),
       .frame_stb(), .ring_cad_n(), .dt_bit(), .ng_bit(),
       .mon_held(), .mon_busy(), .mon_full(), .got_claim(), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(pb2), .regs_busy(),
       .wq_ovf(), .n_defer(), .ev_cnt(),
       .wr_stb(wr2_stb), .wr_dst(wr2_dst), .wr_src(wr2_src),
       .wr_bsy(wr2_bsy), .wr_clm(wr2_clm));

    // Site C: field B K on 21; 04 is a real line.  Site D: field B U on 21; 04 empty.
    reg  [63:0] hook3 = 0, tx3 = 0;
    wire [63:0] pb3;
    wire        wr3_stb, wr3_bsy, wr3_clm;
    wire [5:0]  wr3_src, wr3_dst;
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(2'd2),
               .LINE_PORTS(64'h0000_0000_0003_0010),
               .LINE_WORD_04(16'hFFFF),
               .LINE_WORD_20(16'hFFFF),
               .LINE_WORD_21(ANS04_K),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250),
               .NREG(2), .NMON(1), .NRES(1))
    C (.clk(clk), .rst_n(rst_n),
       .hook(hook3), .tx(tx3), .rx(), .e(),
       .line_in(1'b0), .line_out(), .locked(),
       .frame_stb(), .ring_cad_n(), .dt_bit(), .ng_bit(),
       .mon_held(), .mon_busy(), .mon_full(), .got_claim(), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(pb3), .regs_busy(),
       .wq_ovf(), .n_defer(), .ev_cnt(),
       .wr_stb(wr3_stb), .wr_dst(wr3_dst), .wr_src(wr3_src),
       .wr_bsy(wr3_bsy), .wr_clm(wr3_clm));

    reg  [63:0] hook4 = 0, tx4 = 0;
    wire [63:0] pb4;
    wire        wr4_stb, wr4_bsy, wr4_clm;
    wire [5:0]  wr4_src, wr4_dst;
    // 04 unequipped (not in LINE_PORTS); 21 has U flag
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(2'd2),
               .LINE_PORTS(64'h0000_0000_0003_0000),
               .LINE_WORD_20(16'hFFFF),
               .LINE_WORD_21(ANS04_U),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250),
               .NREG(2), .NMON(1), .NRES(1))
    D (.clk(clk), .rst_n(rst_n),
       .hook(hook4), .tx(tx4), .rx(), .e(),
       .line_in(1'b0), .line_out(), .locked(),
       .frame_stb(), .ring_cad_n(), .dt_bit(), .ng_bit(),
       .mon_held(), .mon_busy(), .mon_full(), .got_claim(), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(pb4), .regs_busy(),
       .wq_ovf(), .n_defer(), .ev_cnt(),
       .wr_stb(wr4_stb), .wr_dst(wr4_dst), .wr_src(wr4_src),
       .wr_bsy(wr4_bsy), .wr_clm(wr4_clm));

    reg [5:0] last_dt = 6'h3f, last_dt2 = 6'h3f, last_dt3 = 6'h3f, last_dt4 = 6'h3f;
    always @(posedge clk) begin
        if (wr_stb && wr_bsy && !wr_clm && wr_src == DIALTONE)
            last_dt <= wr_dst;
        if (wr2_stb && wr2_bsy && !wr2_clm && wr2_src == DIALTONE)
            last_dt2 <= wr2_dst;
        if (wr3_stb && wr3_bsy && !wr3_clm && wr3_src == DIALTONE)
            last_dt3 <= wr3_dst;
        if (wr4_stb && wr4_bsy && !wr4_clm && wr4_src == DIALTONE)
            last_dt4 <= wr4_dst;
    end

    integer errs = 0, chk = 0;
    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-56s FAIL", what); end
            else $display("     %-56s ok", what);
        end
    endtask

    task dial_from(input [5:0] p, input integer d);
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
    task dial2_from(input [5:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook2[p] = 1'b0; #BRK_NS;
                hook2[p] = 1'b1; #MK_NS;
            end
            #PAUSE;
        end
    endtask
    task dial3_from(input [5:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook3[p] = 1'b0; #BRK_NS;
                hook3[p] = 1'b1; #MK_NS;
            end
            #PAUSE;
        end
    endtask
    task dial4_from(input [5:0] p, input integer d);
        integer n, i;
        begin
            n = (d == 0) ? 10 : d;
            for (i = 0; i < n; i = i + 1) begin
                hook4[p] = 1'b0; #BRK_NS;
                hook4[p] = 1'b1; #MK_NS;
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
    task await_dt2(input [5:0] who);
        integer t;
        begin
            last_dt2 = 6'h3f; t = 0;
            while (last_dt2 !== who && t < 200) begin #1_000_000; t = t + 1; end
        end
    endtask
    task await_dt3(input [5:0] who);
        integer t;
        begin
            last_dt3 = 6'h3f; t = 0;
            while (last_dt3 !== who && t < 200) begin #1_000_000; t = t + 1; end
        end
    endtask
    task await_dt4(input [5:0] who);
        integer t;
        begin
            last_dt4 = 6'h3f; t = 0;
            while (last_dt4 !== who && t < 200) begin #1_000_000; t = t + 1; end
        end
    endtask

    initial begin
        $display("GROUPS (RTL) -- answers-to hunt (groups.md §2).\n");
        #4000 rst_n = 1;
        #50_000_000;

        // ---- 0. sanity: 23 dials 20 ------------------------------------
        $display("  sanity");
        hook[6'o23] = 1'b1;
        await_dt(6'o23);
        want(last_dt === 6'o23, "sanity: 23 got dial tone");
        dial_from(6'o23, 2); dial_from(6'o23, 0);
        #100_000_000;
        want(port_busy[6'o20] && port_busy[6'o23], "sanity: 23 dials 20 connects");
        hook = 0; #200_000_000;

        // ---- 1. hunt group ----------------------------------------------
        $display("  hunt group");
        hook[6'o20] = 1'b1;
        await_dt(6'o20);
        dial_from(6'o20, 2); dial_from(6'o20, 7);   // 27 unequipped → nogo
        #50_000_000;
        want(port_busy[6'o20], "setup: 20 busy");
        hook[6'o23] = 1'b1;
        await_dt(6'o23);
        dial_from(6'o23, 2); dial_from(6'o23, 0);   // dial 20
        #150_000_000;
        want(port_busy[6'o21], "dial 20 busy → answered by 21");
        hook = 0; #200_000_000;

        // ---- 2. digit 0 → 04 --------------------------------------------
        $display("  digit 0");
        hook[6'o23] = 1'b1;
        await_dt(6'o23);
        dial_from(6'o23, 0);
        #150_000_000;
        want(port_busy[6'o04], "0 connects to pilot 04");
        hook = 0; #200_000_000;

        // ---- 3. cover ---------------------------------------------------
        $display("  cover");
        hook2[6'o04] = 1'b1;
        await_dt2(6'o04);
        want(last_dt2 === 6'o04, "cover: 04 got dial tone");
        dial2_from(6'o04, 2); dial2_from(6'o04, 7);   // 27 unequipped → nogo
        #50_000_000;
        want(pb2[6'o04], "cover setup: 04 busy");
        hook2[6'o20] = 1'b1;
        await_dt2(6'o20);
        want(last_dt2 === 6'o20, "cover: 20 got dial tone");
        dial2_from(6'o20, 0);
        #200_000_000;
        want(pb2[6'o21], "0 with 04 busy → cover at 21");
        hook2 = 0; #50_000_000;

        // ---- 4. dual membership: 22 answers to 20 and 25 -----------------
        $display("  dual membership");
        hook[6'o23] = 1'b1;
        await_dt(6'o23);
        dial_from(6'o23, 2); dial_from(6'o23, 5);   // dial 25 (empty) → 22
        #150_000_000;
        want(port_busy[6'o22], "dial 25 → dual member 22");
        hook = 0; #200_000_000;

        // ---- 5. field B K: busy 04 → 21; field B U: empty 04 → 21 --------
        $display("  field B K / U");
        hook3[6'o04] = 1'b1;
        await_dt3(6'o04);
        dial3_from(6'o04, 2); dial3_from(6'o04, 7);
        #50_000_000;
        want(pb3[6'o04], "K setup: 04 busy");
        hook3[6'o20] = 1'b1;
        await_dt3(6'o20);
        dial3_from(6'o20, 0);
        #200_000_000;
        want(pb3[6'o21], "0 with 04 busy → field-B K member 21");
        hook3 = 0; #50_000_000;

        hook4[6'o20] = 1'b1;
        await_dt4(6'o20);
        dial4_from(6'o20, 0);                   // 04 unequipped → U member
        #200_000_000;
        want(pb4[6'o21], "0 with 04 unequipped → field-B U member 21");
        hook4 = 0; #50_000_000;

        $display("");
        if (errs) begin
            $display("GROUPS: %0d of %0d failed", errs, chk);
            $fatal(1);
        end
        $display("GROUPS: %0d checks ok", chk);
        $finish;
    end
endmodule

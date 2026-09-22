// tb_word -- extensions.md §2 card-identity options against the settled
// form-bit word.  The adjacent `o` run is retired (groups.md §2): a spare
// option bit does not walk.  Busy-out and a failed probe are cannot-complete
// after one answers-to hunt.  Digit 0 calls pilot 04, not class operator.
`timescale 1ns/1ps

module tb_word;
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 16, T_FALL = 64;
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer NS = 1_000_000;

    // class: {FF secondary, ppp, ccc, 2'b11}.  Bit 5 P, bit 6 b, bit 7 MBZ 0.
    localparam [15:0] W_O   = {8'hFF, 8'b0000_0111};   // plain line class (no options)
    localparam [15:0] W_B   = {8'hFF, 8'b0100_0111};   // busy-out
    localparam [15:0] W_Z   = {8'hFF, 8'b0011_1111};   // restricted, z (bit 5); bit7 MBZ
    localparam [15:0] W_OP  = {8'hFF, 8'b0000_1011};   // class operator — not the target of digit 0

    reg clk = 0, rst_n = 0;
    always #122.0703 clk = ~clk;

    reg  [63:0] hook = 0, tx = 0;
    wire [63:0] rx, e, port_busy;
    wire [1:0]  regs_busy;
    wire        wr_stb, wr_bsy, wr_clm;
    wire [5:0]  wr_dst, wr_src;

    // 20=o, 21=o, 22=plain (end of hunt), 23=caller
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(2'd2),
               .LINE_PORTS(64'h0000_0000_000F_0000),
               .LINE_WORD_20(W_O), .LINE_WORD_21(W_O),
               .LINE_WORD_22(16'hFFFF), .LINE_WORD_23(16'hFFFF),
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

    // Busy-out + restricted + operator on a second site
    reg  [63:0] hook2 = 0, tx2 = 0;
    wire [63:0] pb2, e2;
    wire        wr2_stb, wr2_bsy, wr2_clm;
    wire [5:0]  wr2_dst, wr2_src;
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(2'd2),
               .LINE_PORTS(64'h0000_0000_000F_0000),
               .LINE_WORD_20(W_B), .LINE_WORD_21(W_Z),
               .LINE_WORD_22(W_OP), .LINE_WORD_23(16'hFFFF),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250),
               .NREG(2), .NMON(1), .NRES(1))
    B (.clk(clk), .rst_n(rst_n),
       .hook(hook2), .tx(tx2), .rx(), .e(e2),
       .line_in(1'b0), .line_out(), .locked(),
       .frame_stb(), .ring_cad_n(), .dt_bit(), .ng_bit(),
       .mon_held(), .mon_busy(), .mon_full(), .got_claim(), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(pb2), .regs_busy(),
       .wq_ovf(), .n_defer(), .ev_cnt(),
       .wr_stb(wr2_stb), .wr_dst(wr2_dst), .wr_src(wr2_src),
       .wr_bsy(wr2_bsy), .wr_clm(wr2_clm));

    // Tied nail: 20 names 21 only (one-sided two-write).  21 is a plain line.
    reg  [63:0] hookn = 0, txn = 0;
    wire [63:0] pbn, en;
    localparam [15:0] NAIL20 = {8'hFF, 6'o21, 2'b00};
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(2'd2),
               .LINE_PORTS(64'h0000_0000_0003_0000),
               .LINE_WORD_20(NAIL20), .LINE_WORD_21(16'hFFFF),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250),
               .NREG(1), .NMON(1), .NRES(1))
    N (.clk(clk), .rst_n(rst_n),
       .hook(hookn), .tx(txn), .rx(), .e(en),
       .line_in(1'b0), .line_out(), .locked(),
       .frame_stb(), .ring_cad_n(), .dt_bit(), .ng_bit(),
       .mon_held(), .mon_busy(), .mon_full(), .got_claim(), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(pbn), .regs_busy(),
       .wq_ovf(), .n_defer(), .ev_cnt(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    // Call nail: 20 names 21.  Nothing held until lift.
    reg  [63:0] hookl = 0, txl = 0;
    wire [63:0] pbl, el;
    localparam [15:0] CALL20 = {8'hFF, 6'o21, 2'b10};
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(2'd2),
               .LINE_PORTS(64'h0000_0000_0003_0000),
               .LINE_WORD_20(CALL20), .LINE_WORD_21(16'hFFFF),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250),
               .NREG(1), .NMON(1), .NRES(1))
    L (.clk(clk), .rst_n(rst_n),
       .hook(hookl), .tx(txl), .rx(), .e(el),
       .line_in(1'b0), .line_out(), .locked(),
       .frame_stb(), .ring_cad_n(), .dt_bit(), .ng_bit(),
       .mon_held(), .mon_busy(), .mon_full(), .got_claim(), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(pbl), .regs_busy(),
       .wq_ovf(), .n_defer(), .ev_cnt(),
       .wr_stb(), .wr_dst(), .wr_src(), .wr_bsy(), .wr_clm());

    localparam [5:0] BUSYTONE = 6'o02, NOGO = 6'o03;
    reg [5:0] last_src = 6'h3f, last_dst = 6'h3f;
    always @(posedge clk) if (wr_stb && wr_bsy) begin
        last_src <= wr_src; last_dst <= wr_dst;
    end
    reg [5:0] b_src = 6'h3f, b_dst = 6'h3f;
    always @(posedge clk) if (wr2_stb && wr2_bsy) begin
        b_src <= wr2_src; b_dst <= wr2_dst;
    end

    integer errs = 0, chk = 0;
    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-56s FAIL", what); end
            else $display("     %-56s ok", what);
        end
    endtask
    task wait_ms(input integer n); begin #(n * NS); end endtask

    task dial(input [5:0] p, input integer pulses);
        integer i, n;
        begin
            // HIT=1, ID=16, CLR=32.  Same shape as tb_net: 12 ms break, 8 ms make.
            n = (pulses == 0) ? 10 : pulses;
            for (i = 0; i < n; i = i + 1) begin
                hook[p] = 1'b0; wait_ms(12);
                hook[p] = 1'b1; wait_ms(8);
            end
            wait_ms(40);
        end
    endtask
    task dial2(input [5:0] p, input integer pulses);
        integer i, n;
        begin
            n = (pulses == 0) ? 10 : pulses;
            for (i = 0; i < n; i = i + 1) begin
                hook2[p] = 1'b0; wait_ms(12);
                hook2[p] = 1'b1; wait_ms(8);
            end
            wait_ms(40);
        end
    endtask

    initial begin
        $display("WORD (RTL) -- retired o-bit, busy-out, restricted, tied nail, call nail.\n");
        #4000 rst_n = 1;
        wait_ms(80);

        // ---- retired o-bit: 20 busy, no answers-to member → nogo, not 22 --
        $display("  no o-run");
        hook[6'o20] = 1'b1; wait_ms(40);
        want(port_busy[6'o20], "setup: 20 off-hook busy");

        last_src = 6'h3f;
        hook[6'o23] = 1'b1; wait_ms(40);
        dial(6'o23, 2); dial(6'o23, 0);           // dial 20
        wait_ms(80);
        want(last_src == NOGO, "dial 20 busy, no cover → cannot-complete");
        want(!port_busy[6'o22], "o-bit did not walk on to 22");
        hook = 0; wait_ms(120);

        // ---- busy-out: dial 20 (b set) from 23 → cannot-complete ---------
        $display("  busy-out");
        b_src = 6'h3f;
        hook2[6'o23] = 1'b1; wait_ms(40);
        dial2(6'o23, 2); dial2(6'o23, 0);         // dial 20
        wait_ms(80);
        want(b_src == NOGO, "busy-out: b-marked idle line → cannot-complete");
        hook2 = 0; wait_ms(100);
        hook2[6'o20] = 1'b1; wait_ms(40);
        want(pb2[6'o20] === 1'b1, "busy-out: marked line still gets a register");
        hook2 = 0; wait_ms(80);

        // ---- restricted z: 21 dials 2 → nogo; 0 is pilot 04, not class 22
        $display("  restricted 0-only");
        b_src = 6'h3f;
        hook2[6'o21] = 1'b1; wait_ms(40);
        dial2(6'o21, 2);
        wait_ms(80);
        want(b_src == NOGO, "restricted z: first digit 2 -> cannot-complete");
        hook2[6'o21] = 1'b0; wait_ms(80);
        b_src = 6'h3f;
        hook2[6'o21] = 1'b1; wait_ms(40);
        dial2(6'o21, 0);                          // digit 0 → pilot 04 (unfitted)
        wait_ms(80);
        want(b_src == NOGO, "restricted z: digit 0 with no 04 → cannot-complete");
        want(!pb2[6'o22], "digit 0 did not hunt class operator at 22");
        hook2 = 0; wait_ms(100);

        // ---- tied nail ---------------------------------------------------
        $display("  tied nail");
        wait_ms(40);
        want(pbn[6'o20] && pbn[6'o21], "tied nail: scanner wrote both latches");
        hookn[6'o20] = 1'b1;
        begin : nail_e
            integer t;
            reg saw;
            saw = 0;
            for (t = 0; t < 30; t = t + 1) begin
                wait_ms(1);
                if (en[6'o21] === 1'b1) saw = 1;
            end
            want(saw, "tied nail: lift rings the partner (E at 21)");
        end
        hookn = 0; wait_ms(120);
        want(pbn[6'o20] && pbn[6'o21], "tied nail: re-nailed after release");

        // ---- call nail: 20 names 21; nothing held idle; lift connects -----
        $display("  call nail");
        wait_ms(40);
        want(!pbl[6'o20] && !pbl[6'o21], "call nail: idle holds nothing");
        hookl[6'o20] = 1'b1;
        begin : lift_e
            integer t;
            reg saw;
            saw = 0;
            for (t = 0; t < 80; t = t + 1) begin
                wait_ms(1);
                if (el[6'o21] === 1'b1) saw = 1;
            end
            want(saw, "call nail: lift rings dest (E at 21)");
        end
        want(pbl[6'o20] && pbl[6'o21], "call nail: both latches up after lift");
        hookl = 0; wait_ms(120);
        want(!pbl[6'o20] && !pbl[6'o21], "call nail: release leaves both free");

        $display("");
        if (errs) begin
            $display("WORD: %0d of %0d failed", errs, chk);
            $fatal(1);
        end
        $display("WORD: %0d checks ok", chk);
        $finish;
    end
endmodule

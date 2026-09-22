// tb_priority -- extensions.md 2.4.1: under register overload, PWAIT prefers
// a priority line for the next free register.
//
//   One register.  Three lines on block 2: 20 and 21 plain, 22 priority
//   (class 001, option bit P).
//
//   1  20 lifts alone              -> gets the register (dial tone)
//   2  21 lifts while 20 holds     -> waits; still no second register
//   3  22 lifts (priority)         -> still waits while 20 holds
//   4  20 hangs up                 -> 22 takes the register, not 21
//   5  22 hangs up; 21 still up    -> after a clear scan, 21 gets it
`timescale 1ns/1ps

module tb_priority;
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam integer T_RISE = 16, T_FALL = 64;   // fast release for the bench
    localparam integer RING_ON = 200, RING_OFF = 400;
    localparam integer NS = 1_000_000;
    // class 001, P=1, b=0, spare=0  -- extensions.md 2.2 / 2.4.1
    localparam [15:0] WORD_PRI = {8'hFF, 8'b0010_0111};

    reg clk = 0, rst_n = 0;
    always #122.0703 clk = ~clk;

    reg  [63:0] hook = 0, tx = 0;
    wire [63:0] rx, e, port_busy;
    wire [0:0]  regs_busy;
    wire        frame_stb, dt_bit, ng_bit;
    wire        wr_stb, wr_bsy, wr_clm;
    wire [5:0]  wr_dst, wr_src;

    // ports 20, 21, 22 fitted; 22 carries the priority word
    net_site #(.OWN_E(3'd2), .OWN_B(3'd2), .DIR0(2'd2),
               .LINE_PORTS(64'h0000_0000_0007_0000),
               .LINE_WORD_20(16'hFFFF), .LINE_WORD_21(16'hFFFF),
               .LINE_WORD_22(WORD_PRI),
               .T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF),
               .HIT(HIT), .ID(ID), .CLR(CLR), .T_GUARD(16), .T_CLAIM(250),
               .NREG(1), .NMON(1), .NRES(1))
    A (.clk(clk), .rst_n(rst_n),
       .hook(hook), .tx(tx), .rx(rx), .e(e),
       .line_in(1'b0), .line_out(), .locked(),
       .frame_stb(frame_stb), .ring_cad_n(), .dt_bit(dt_bit), .ng_bit(ng_bit),
       .mon_held(), .mon_busy(), .mon_full(), .got_claim(), .dirs_held(),
       .fan_legs(), .res_used(), .port_busy(port_busy), .regs_busy(regs_busy),
       .wq_ovf(), .n_defer(), .ev_cnt(),
       .wr_stb(wr_stb), .wr_dst(wr_dst), .wr_src(wr_src),
       .wr_bsy(wr_bsy), .wr_clm(wr_clm));

    // who last got dial tone (SRC = dial-tone port, PDT = 6'o01)
    localparam [5:0] DIALTONE = 6'o01;
    reg [5:0] last_dt = 6'h3f;
    always @(posedge clk)
        if (wr_stb && wr_bsy && !wr_clm && wr_src == DIALTONE)
            last_dt <= wr_dst;

    integer errs = 0, chk = 0;
    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-56s FAIL", what); end
            else $display("     %-56s ok", what);
        end
    endtask

    task wait_ms(input integer n);
        begin #(n * NS); end
    endtask

    // wait until regs_busy matches, or timeout
    task await_reg(input want_busy, input integer lim_ms);
        integer t;
        begin
            t = 0;
            while (regs_busy[0] !== want_busy && t < lim_ms) begin
                wait_ms(1); t = t + 1;
            end
        end
    endtask

    // dial tone is queued then shifted: wait for the write after attach
    task await_dt(input [5:0] who, input integer lim_ms);
        integer t;
        begin
            t = 0;
            while (last_dt !== who && t < lim_ms) begin
                wait_ms(1); t = t + 1;
            end
        end
    endtask

    initial begin
        $display("PRIORITY (RTL) -- PWAIT prefers a priority line under overload.\n");
        #4000 rst_n = 1;
        wait_ms(50);

        // 1. plain 20 takes the only register
        last_dt = 6'h3f;
        hook[6'o20] = 1'b1;
        await_reg(1'b1, 100);
        await_dt(6'o20, 50);
        want(regs_busy[0] === 1'b1, "1. 20 lifted: register busy");
        want(last_dt === 6'o20,     "1. dial tone written to 20");

        // 2. plain 21 waits behind it
        last_dt = 6'h3f;
        hook[6'o21] = 1'b1;
        wait_ms(40);                    // several full scans
        want(regs_busy[0] === 1'b1, "2. still one register held");
        want(last_dt === 6'h3f,     "2. 21 has not taken dial tone");

        // 3. priority 22 also waits while the pool is full
        hook[6'o22] = 1'b1;
        wait_ms(40);
        want(last_dt === 6'h3f,     "3. 22 waits while 20 holds the register");

        // 4. 20 hangs up -- priority 22 must win over 21
        last_dt = 6'h3f;
        hook[6'o20] = 1'b0;
        await_reg(1'b0, 200);           // register CLR
        want(regs_busy[0] === 1'b0, "4. register freed after 20 hung up");
        await_reg(1'b1, 100);
        await_dt(6'o22, 50);
        want(regs_busy[0] === 1'b1, "4. a register is taken again");
        want(last_dt === 6'o22,     "4. priority 22 got dial tone, not 21");
        if (last_dt !== 6'o22)
            $display("     (got dial tone on %o, expected 22)", last_dt);

        // 5. 22 done; 21 still up -- after a clear scan, 21 gets it
        last_dt = 6'h3f;
        hook[6'o22] = 1'b0;
        await_reg(1'b0, 200);
        want(regs_busy[0] === 1'b0, "5. register freed after 22 hung up");
        await_reg(1'b1, 100);
        await_dt(6'o21, 50);
        want(regs_busy[0] === 1'b1, "5. register handed out again");
        want(last_dt === 6'o21,     "5. non-priority 21 gets dial tone once PWAIT clear");
        if (last_dt !== 6'o21)
            $display("     (got dial tone on %o, expected 21)", last_dt);

        hook = 0;
        wait_ms(50);
        $display("\n  %0d checks, %0d failed", chk, errs);
        if (errs) $fatal(1);
        $display("PASS");
        $finish;
    end
endmodule

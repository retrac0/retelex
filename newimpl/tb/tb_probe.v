// tb_probe -- the scanner-addressed listener, and the clear that fabric-rev2
// found the hard way.
//
// One probe serves the marker, every register, every monitor and any
// observer.  Tie its address to SCAN and it follows the scanner; tie it to a
// held number and it watches that one port, once every 1 ms.  M comes off /HA
// and BUSY off /HB in the SAME bit-time, so a sample is never half a port.
`timescale 1ns/1ps
`include "exch.vh"

module tb_probe;
    integer chk = 0, errs = 0, shown = 0;
    task ck(input cond, input [8*60-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask
    task oops(input [8*60-1:0] what);
        begin errs = errs + 1;
             if (shown < 8) begin shown = shown + 1;
                 $display("    FAIL  %0s  at %0t", what, $time); end
        end
    endtask

    reg clk = 1'b0, rst_n = 1'b0;
    always #122.070 clk = ~clk;

    reg [63:0] a_tx = 64'h0F1E_2D3C_4B5A_6978;
    wire [63:0] port_busy;
    wire ha_n, hb_n, hw_n, cap_stb, frame_stb, pass_stb;
    wire [2:0] slot, slotq;
    wire [`SCANW-1:0] scan;
    wire s_sdata, s_sclk, s_wr, s_busy;

    reg req = 1'b0; reg [`PW-1:0] dst = 6'd0, src = 6'd0; reg bsy = 1'b0;
    ctl_write u_ser (
        .clk(clk), .rst_n(rst_n), .req(req), .strobe(1'b1), .g(1'b1),
        .dst(dst), .src(src), .bsy(bsy), .clm(1'b0),
        .busy(s_busy), .sdata(s_sdata), .sclk(s_sclk), .wr(s_wr));

    exch #(.PORT_FITTED({64{1'b1}}), .BLOCK_FITTED(8'hFF)) u_x (
        .clk(clk), .rst_n(rst_n),
        .c_tx(64'd0), .a_tx(a_tx), .ans_n({64{1'b1}}), .word_n({64{1'b1}}),
        .c_rx(), .a_rx(), .mute_blk(8'd0), .rbt_in(1'b0),
        .sdata(s_sdata), .sclk(s_sclk), .wr(s_wr), .hw_n(hw_n),
        .hc(), .ha_n(ha_n), .hb_n(hb_n), .tick(), .slot(slot), .slotq(slotq),
        .hclk(), .line_hb(), .cap_stb(cap_stb), .tx_clk(),
        .frame_stb(frame_stb), .clk_8k(), .rx_oct(), .oct_stb(),
        .scan(scan), .pass_stb(pass_stb),
        .fill(), .ring_cad_n(), .tick_1k(), .port_busy(port_busy));

    // ---- one probe following the scan, one watching a held port -----------
    wire       f_m, f_busy, f_fresh; wire [`PW-1:0] f_port;
    probe u_follow (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .cap_stb(cap_stb),
        .frame_stb(frame_stb), .scan(scan), .ha_n(ha_n), .hb_n(hb_n),
        .port(scan),
        .m(f_m), .busy(f_busy), .port_q(f_port), .fresh(f_fresh));

    reg [`PW-1:0] watch = 6'o05;
    wire       h_m, h_busy, h_fresh; wire [`PW-1:0] h_port;
    probe u_held (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .cap_stb(cap_stb),
        .frame_stb(frame_stb), .scan(scan), .ha_n(ha_n), .hb_n(hb_n),
        .port(watch),
        .m(h_m), .busy(h_busy), .port_q(h_port), .fresh(h_fresh));

    reg armed = 1'b0;
    reg [63:0] covered = 64'd0;
    integer n_follow = 0, n_held = 0;

    always @(posedge clk) if (armed) begin
        if (f_fresh) begin
            n_follow = n_follow + 1;
            covered[f_port] = 1'b1;
            if (f_m !== a_tx[f_port])       oops("the following probe has the wrong M");
            if (f_busy !== port_busy[f_port]) oops("the following probe has the wrong BUSY");
        end
        // THE CLEAR.  With the accumulator left uncleared, a probe on a held
        // port would publish on EVERY turn, carrying that port's stale hook
        // under whatever port number happened to be going by.  Then port_q
        // would take all 64 values instead of one.
        if (h_fresh) begin
            n_held = n_held + 1;
            if (h_port !== watch) oops("the held probe published someone else's turn");
            if (h_m !== a_tx[watch]) oops("the held probe has the wrong M");
        end
    end

    integer i;
    initial begin
        $display("\n  tb_probe -- one listener, and the per-port clear");
        repeat (20) @(posedge clk);
        rst_n = 1'b1; repeat (8) @(posedge clk);
        // a spread of BUSY so the check is not satisfied by everything at zero
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk); dst = i[`PW-1:0]*6'd7; src = 6'o05; bsy = 1'b1;
            req = 1'b1; @(posedge clk); req = 1'b0; @(posedge clk);
            while (s_busy) @(posedge clk);
        end

        @(posedge pass_stb); @(posedge clk);
        armed = 1'b1;

        // ---- one pass ------------------------------------------------------
        @(posedge pass_stb); @(posedge clk);
        ck(n_follow == 64, "a probe on SCAN reads all 64 ports in one 1 ms pass");
        ck(covered == {64{1'b1}}, "and every one of them exactly once");
        ck(n_held == 1, "a probe on a held port publishes ONCE a pass, not 64 times");
        $display("     following probe: %0d ports a pass.  held probe: %0d",
                 n_follow, n_held);

        // ---- four more passes ------------------------------------------------
        n_follow = 0; n_held = 0; covered = 64'd0;
        repeat (4) @(posedge pass_stb);
        @(posedge clk);
        ck(n_follow == 4*64, "and it keeps up, pass after pass");
        ck(n_held   == 4,    "the held probe refreshes at 1 kHz");

        // ---- move the held probe onto a port with the other hook -----------
        // Port 05 and port 07 differ in the pattern; if the accumulator were
        // not cleared per port, the probe would carry 05's hook onto 07.
        armed = 1'b0;
        ck(a_tx[6'o05] !== a_tx[6'o07], "the two watched ports differ, so this proves something");
        @(posedge clk); watch = 6'o07;
        n_held = 0; armed = 1'b1;
        repeat (3) @(posedge pass_stb);
        @(posedge clk);
        ck(n_held == 3 || n_held == 2, "the moved probe settles within a pass");
        ck(h_port === 6'o07, "and it is reporting port 07");
        ck(h_m === a_tx[6'o07], "with port 07's hook, not port 05's");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #200_000_000; $display("  TIMEOUT"); $fatal(1); end
endmodule

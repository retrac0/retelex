// tb_two -- two exchanges, each on its own crystal, in one simulation.
//
// Nothing in the RTL is global, so an exchange is a thing you instantiate.  The
// two crystals here are 100 ppm apart, which is what mf8-backplane.md 2 assumes
// of any two ends of a link: each exchange keeps its own T domain, and a link
// between them would be plesiochronous.  Both sites run mvp-ex.md 6.3's manual
// board at once and neither disturbs the other.
`timescale 1ns/1ps

module tb_two;
    localparam integer T_RISE = 16, T_FALL = 256, RING_ON = 200, RING_OFF = 400;

    reg clk_a = 0, clk_b = 0, rst_n = 0;
    // 4.096 MHz, and 4.096 MHz + 100 ppm
    always #122.0703 clk_a = ~clk_a;
    always #122.0581 clk_b = ~clk_b;

    reg        rqa = 0, rqb = 0;
    reg  [5:0] dsta = 0, srca = 0, dstb = 0, srcb = 0;
    wire       bsya, bsyb, sda, scka, wr_a, sdb, sckb, wr_b;
    ctl_write ca (.clk(clk_a), .rst_n(rst_n), .req(rqa), .strobe(1'b1), .g(1'b1),
                  .dst(dsta), .src(srca), .bsy(1'b1), .clm(1'b0),
                  .busy(bsya), .sdata(sda), .sclk(scka), .wr(wr_a));
    ctl_write cb (.clk(clk_b), .rst_n(rst_n), .req(rqb), .strobe(1'b1), .g(1'b1),
                  .dst(dstb), .src(srcb), .bsy(1'b1), .clm(1'b0),
                  .busy(bsyb), .sdata(sdb), .sclk(sckb), .wr(wr_b));
    reg        h20a = 0, h21a = 0, h20b = 0, h21b = 0;
    reg  [2:0] mode_a = 0, mode_b = 0;
    wire [31:0] errs_a, errs_b, chk_a, chk_b;
    wire       fs_a, fs_b, rc_a, rc_b;

    mvp_site #(.T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF))
        site_a (.clk(clk_a), .rst_n(rst_n), .sdata(sda), .sclk(scka), .wr(wr_a), .hook20(h20a), .hook21(h21a), .mode(mode_a),
                .errs(errs_a), .chk(chk_a), .frame_stb(fs_a), .ring_cad_n(rc_a));

    mvp_site #(.T_RISE(T_RISE), .T_FALL(T_FALL), .RING_ON(RING_ON), .RING_OFF(RING_OFF))
        site_b (.clk(clk_b), .rst_n(rst_n), .sdata(sdb), .sclk(sckb), .wr(wr_b), .hook20(h20b), .hook21(h21b), .mode(mode_b),
                .errs(errs_b), .chk(chk_b), .frame_stb(fs_b), .ring_cad_n(rc_b));

    // Both consoles write the same hotline, each on its own exchange's cable B.
    task hotline;
        begin
            @(posedge clk_a); #1;
            dsta = 6'o20; srca = 6'o21; rqa = 1;
            dstb = 6'o20; srcb = 6'o21; rqb = 1;
            @(posedge clk_a); #1; rqa = 0; rqb = 0;
            wait (bsya); wait (!bsya); wait (!bsyb);
            @(posedge clk_a); #1;
            dsta = 6'o21; srca = 6'o20; rqa = 1;
            dstb = 6'o21; srcb = 6'o20; rqb = 1;
            @(posedge clk_a); #1; rqa = 0; rqb = 0;
            wait (bsya); wait (!bsya); wait (!bsyb);
        end
    endtask

    task both(input [2:0] mm, input integer us, input string what);
        reg [31:0] e0, e1;
        begin
            e0 = errs_a; e1 = errs_b;
            mode_a = mm; mode_b = mm;
            #(us * 1000);
            mode_a = 0; mode_b = 0;
            $display("     %-52s  A %s   B %s", what,
                     (errs_a == e0) ? "ok  " : "FAIL", (errs_b == e1) ? "ok" : "FAIL");
        end
    endtask

    initial begin
        $display("TWO EXCHANGES (RTL) -- independent crystals 100 ppm apart, one simulation.\n");
        #2000 rst_n = 1;
        #2000;
        hotline;
        #2000;

        h20a = 1; h20b = 1;                      // 20 lifts on both exchanges
        #(1000 * 1000);
        both(1, 25000, "20 lifts: 21 rings, 20 hears RBT");

        h21a = 1; h21b = 1;                      // 21 answers on both
        #(1000 * 1000);
        both(2, 5000, "21 answers: speech both ways");

        h21a = 0; h21b = 0;                      // and hangs up
        #(6000 * 1000);
        both(3, 3000, "21 hangs up: both latches idle");

        $display("\n     A: %0d checks, %0d errors     B: %0d checks, %0d errors",
                 chk_a, errs_a, chk_b, errs_b);
        $display("\n  %s", (errs_a == 0 && errs_b == 0) ? "PASS" : "FAIL");
        $finish;
    end
endmodule

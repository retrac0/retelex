// bitpath -- watches one CVSD bit stream from the card that sends it to the
// card that hears it, across two exchanges and a trunk, and finds the delay
// rather than assuming it.  The two ends have their own frame edges, so the
// source is recorded on its clock and compared on the destination's.
`timescale 1ns/1ps

module bitpath #(parameter integer MAXD = 60) (
    input  src_clk, input src_fs, input src_bit,
    input  dst_clk, input dst_fs, input dst_bit,
    input  enable
);
    reg        hist [0:255];
    reg [7:0]  wp = 0;
    integer    errs [0:MAXD];
    integer    nbits = 0;
    integer    best_d = 0, best_err = 0;
    integer    i;

    initial for (i = 0; i <= MAXD; i = i + 1) errs[i] = 0;

    always @(posedge src_clk) if (src_fs) begin
        hist[wp] = src_bit;
        wp = wp + 8'd1;
    end

    always @(posedge dst_clk) if (dst_fs && enable) begin
        for (i = 1; i <= MAXD; i = i + 1)
            if (dst_bit !== hist[(wp - i[7:0]) & 8'hFF]) errs[i] = errs[i] + 1;
        nbits = nbits + 1;
    end

    task report(input string what);
        integer j;
        begin
            best_err = nbits + 1; best_d = 0;
            for (j = 1; j <= MAXD; j = j + 1)
                if (errs[j] < best_err) begin best_err = errs[j]; best_d = j; end
            $display("     %-36s %5d bits, delay %2d frames, %0d wrong   %s",
                     what, nbits, best_d, best_err, (best_err == 0) ? "ok" : "FAIL");
        end
    endtask

    function integer best_errs;
        integer j;
        begin
            best_errs = nbits + 1;
            for (j = 1; j <= MAXD; j = j + 1)
                if (errs[j] < best_errs) best_errs = errs[j];
        end
    endfunction

    task clear;
        integer j;
        begin
            for (j = 0; j <= MAXD; j = j + 1) errs[j] = 0;
            nbits = 0;
        end
    endtask
endmodule

// hc165 -- 74HC165 8-bit parallel-load shift register (serial out).
// ctl_write is the cable-B serialiser: two of these daisy-chained.  The
// synth flow keeps ctl_write hierarchical and pack.py bills each instance
// as 2 x HC165; this module is the named part for that BOM line.
`timescale 1ns/1ps
(* keep_hierarchy *)
module hc165 (
    input            clk,     // CP1 / CP2 (shift)
    input            pl_n,    // /PL: low = parallel load
    input            ce_n,    // /CE: low = shift enabled
    input      [7:0] d,       // parallel inputs
    input            ds,      // serial in (daisy-chain)
    output           qh       // serial out
);
    reg [7:0] q;
    assign qh = q[7];
    always @(posedge clk or negedge pl_n)
        if (!pl_n)      q <= d;
        else if (!ce_n) q <= {q[6:0], ds};
endmodule

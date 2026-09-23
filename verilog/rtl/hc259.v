// hc259 -- a 74HC259 addressable latch: the inverse of mux8's '151, and the
// whole of a lamp field.  observers.md 1, "a lamp field is a demultiplexer
// with LEDs on it".
//
// The fabric has already done the hard half.  fabric.md 1.1 puts all 64
// ports on eight wires, each port once a frame, and A PORT'S ADDRESS IS WHERE
// IT APPEARS -- which wire, and when.  Address this part with the same count
// the commutator used and hand it the wire, and its eight outputs are the
// eight ports, held.  So an 8 x 8 grid is NOT a scanned matrix: nothing on the
// panel is multiplexed, every lamp is a latch output holding DC, and there is
// no row driver, no refresh and no duty cycle to trade against brightness.
//
// THE PART IS LEVEL SENSITIVE, not edged.  /LE low and the ADDRESSED output
// follows D; the other seven hold.  /LE high and all eight hold.  /CLR is
// asynchronous.  That transparency is not a detail to be tidied away in the
// model -- it is exactly why the busy field needs an INH (observers.md 3),
// and a model that latched on an edge would hide the fault the inhibit exists
// to prevent.
`timescale 1ns/1ps

(* keep_hierarchy *)          // one 74HC259 — do not flatten for synth-hc BOM
module hc259 (
    input            clk,       // the model's one domain; the part has no clock
    input            clr_n,     // /CLR, asynchronous, clears all eight
    input            le_n,      // /LE: low = the addressed output follows D
    input      [2:0] a,
    input            d,
    output reg [7:0] q
);
    always @(posedge clk or negedge clr_n)
        if (!clr_n)     q    <= 8'd0;
        else if (!le_n) q[a] <= d;
endmodule

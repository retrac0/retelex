// line_delay -- a carrier that is not a pair.
//
// `MS` milliseconds of constant one-way delay on the line, which is what
// distance, a mux, a vocoder or a jitter buffer put between the two ends of a
// trunk (`network.md` §1.1). It is a testbench part and nothing in the
// exchange knows it is there: a trunk card sends its differential Manchester
// into it and the far card's classifier takes it out, later.
//
// It is here to settle one question. The origin's 128 ms guard
// (`monitor.md` §3, rule 2) is sized on how long the flood takes to
// spread, and a link tens of milliseconds long makes the flood take tens of
// milliseconds longer a hop. **It costs the guard nothing**, because the
// seizure that opens the flood and the caller's pulses that follow it are the
// same wire and arrive equally late — and `make chain-delay` is that, in the
// gates, at 100 ms a hop against a 128 ms guard.
//
// A circular buffer and one pointer: a byte of storage a master tick, which at
// 4.096 MHz is 4 096 a millisecond and nothing at all beside the exchange.
`timescale 1ns/1ps

module line_delay #(
    parameter integer MS = 0            // one way, milliseconds
)(
    input  clk,                         // the SENDING exchange's master clock
    input  d,
    output q
);
    localparam integer N = MS * 4096;   // master ticks in a millisecond

    generate if (N == 0) begin : straight
        assign q = d;
    end else begin : buffered
        reg        mem [0:N-1];
        integer    i;
        reg [31:0] p = 32'd0;
        reg        out = 1'b0;
        initial for (i = 0; i < N; i = i + 1) mem[i] = 1'b0;
        always @(posedge clk) begin
            out    <= mem[p];           // read the oldest, then overwrite it
            mem[p] <= d;
            p      <= (p == N - 1) ? 32'd0 : p + 32'd1;
        end
        assign q = out;
    end endgenerate
endmodule

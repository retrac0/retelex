// phone -- a behavioural telephone on the simplified subscriber interface.
// It lifts, dials loop-disconnect pulses, talks and hangs up, and it can say
// whether it is being rung.
`timescale 1ns/1ps

module phone #(
    parameter integer PPS       = 10,     // pulses a second
    parameter integer BREAK_PCT = 60,     // break/make ratio
    parameter integer FRAME_NS  = 15625   // one 64 kHz frame
)(
    input      frame_stb,
    output reg m  = 1'b0,                 // off-hook
    output reg tx = 1'b0,                 // CVSD toward the exchange
    input      rx,
    input      e
);
    // Speech: a fresh bit every frame, so a listener can be checked against it.
    always @(posedge frame_stb) if (m) tx <= $random;

    task lift;   begin m = 1'b1; end endtask
    task hangup; begin m = 1'b0; tx = 1'b0; end endtask

    // One loop-disconnect digit: n breaks, 10 for 0.  register.md 2.
    task dial_digit(input integer d);
        integer n, i, brk_ns, mk_ns;
        begin
            n      = (d == 0) ? 10 : d;
            brk_ns = (1000000000 / PPS) * BREAK_PCT / 100;
            mk_ns  = (1000000000 / PPS) - brk_ns;
            for (i = 0; i < n; i = i + 1) begin
                m = 1'b0; #(brk_ns);
                m = 1'b1; #(mk_ns);
            end
        end
    endtask
endmodule

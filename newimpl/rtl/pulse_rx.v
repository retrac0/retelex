// pulse_rx -- three decisions from one timer.  register.md 2.
//
// A pulse register makes three decisions and they all come off a 1 kHz tick:
//
//   is this break a pulse?          break >=   8 ms   HIT   a '4040's Q4
//   does this make end the digit?   make  >= 128 ms   ID    ...        Q8
//   is this break a hang-up?        break >= 256 ms   CLR   ...        Q9
//
// Each sits well inside its gap.  ID at 128 ms is twice the longest in-digit
// make and under a fifth of the shortest pause a phone may send; CLR at
// 256 ms is 2.5 times the longest dial break; HIT at 8 ms, with the line
// card's 6.1 ms and one tick, means a break must last about 15 ms to count,
// which is half the shortest break at 20 pps.
//
// WHAT THE FOLD COSTS HERE.  M arrives through the probe at 1 kHz instead of
// continuously, so every edge this measures is quantised to 1 ms.  The
// tightest ratio in the design is HIT: the shortest break ever counted in
// register.md 3.1 was 18 ms at 20 pps, which is eighteen samples against an
// eight-sample window.  Everything else has tens of milliseconds in hand.
//
// The second conductor bought this.  With A and BUSY interleaved on one wire a
// pass was 2 ms and that same 18 ms break was nine samples against four --
// still sound, but the narrowest margin in the design, and the one that decided
// how far a dial pulse could be relayed.  /HB doubles it.
`timescale 1ns/1ps
`include "exch.vh"

module pulse_rx #(
    parameter [8:0] HIT = 9'd8,
    parameter [8:0] ID  = 9'd128,
    parameter [8:0] CLR = 9'd256
)(
    input            clk,
    input            rst_n,
    input            tick_1k,
    input            arm,        // this register is attached to a caller
    input            m,          // the caller's hook, off the probe

    output reg [3:0] cnt,        // the pulse count, saturating at 15
    output reg       dig_stb,    // one tick: the make ended a digit; cnt is it
    output reg       clear,      // one tick: 256 ms of break -- the caller went away
    output           counting,   // a digit is part-collected
    output reg       brk_stb     // one tick: a break was just counted
);
    reg [8:0] t;      // milliseconds in the state m has been in
    reg       m_d;
    reg       hit;    // this break has already been counted
    reg       done;   // the last thing that happened was a completed digit

    // register.md 2: the '163 is cleared by STB, so "count != 0" means A DIGIT IS
    // PART-COLLECTED and goes false between digits.  `cnt` cannot be cleared at
    // dig_stb here -- pulse_reg samples it in the strobe cycle and would store 0
    // for every digit -- so `done` supplies the same falling edge one gate later.
    assign counting = (cnt != 4'd0) && !done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 4'd0; dig_stb <= 1'b0; clear <= 1'b0; brk_stb <= 1'b0;
            t <= 9'd0; m_d <= 1'b0; hit <= 1'b0; done <= 1'b0;
        end else begin
            dig_stb <= 1'b0; clear <= 1'b0; brk_stb <= 1'b0;

            if (!arm) begin
                // A STORE MUST BE EMPTY WHEN IDLE.  rtl.md: a cycle after the
                // register was handed to a new caller the marker read the
                // store and found the PREVIOUS caller's number still in it.
                cnt <= 4'd0; t <= 9'd0; hit <= 1'b0; done <= 1'b0; m_d <= m;
            end else if (tick_1k) begin
                if (m != m_d) begin
                    m_d <= m; t <= 9'd0; hit <= 1'b0;
                end else begin
                    if (t != 9'd511) t <= t + 9'd1;
                    if (!m) begin
                        // a break.  Count it once, at HIT.
                        if (!hit && (t == HIT - 9'd1)) begin
                            hit     <= 1'b1;
                            brk_stb <= 1'b1;
                            done    <= 1'b0;
                            cnt     <= done ? 4'd1
                                            : ((cnt == 4'd15) ? 4'd15 : cnt + 4'd1);
                        end
                        // and at CLR it stops being a dial pulse and becomes
                        // a hang-up.
                        if (t == CLR - 9'd1) clear <= 1'b1;
                    end else begin
                        // a make.  At ID the digit is complete.
                        if (!done && (cnt != 4'd0) && (t == ID - 9'd1)) begin
                            dig_stb <= 1'b1;
                            done    <= 1'b1;
                        end
                    end
                end
            end
        end
    end
endmodule

// pulse_reg -- the register of register.md 4.  It takes no port and has no
// class: the marker's scanner is its finder, and it reads its caller's hook off
// the M highway through its own probe -- two '151s and a flip-flop, the same
// structure a port uses to listen (marker.md 4).
//
// It never sends anything.  The design has no sender: on a network call the
// caller's own pulses go down the flood live, and this register only LISTENS,
// at the origin to know what the caller is doing, and at the owning exchange --
// where a claimed trunk is simply a line -- to read h s.
//
// THE STORE IS FOUR DIGITS, five bits each (register.md 4, pulse-gen.md 4),
// and the marker reads it as LEVELS.
// A digit handed over as a strobe is an event on a wire, and an event is a race
// the moment there is more than one register; a count and a store the marker
// reads in its own time is not.  `restart` begins the store again, and it is
// how the two special prefixes cost nothing:
//
//   the key 1      "the digit the flood consumes" (network.md 2).  The
//                  marker acts on it and restarts, so e b h s land in slots
//                  0-3 -- exactly four, which is why the store is four deep
//   our own e b    restart again, and h s land in slots 0-1: from there the
//                  call is indistinguishable from a local one, because it is
`timescale 1ns/1ps

module pulse_reg #(
    parameter integer HIT = 8, ID = 128, CLR = 256,
    parameter integer NODIG = 12000                 // no digit in 12 s: give up
)(
    input             clk,
    input             rst_n,
    input      [2:0]  slotq,
    input      [2:0]  tick,
    input             tick_1k,
    input      [7:0]  ha,            // the M highway

    input             attach,        // the marker hands it a port number
    input      [5:0]  attach_port,
    input      [5:0]  attach_src,     // held party; 00 = none (register.md 6.1)
    input             release_it,
    input             restart,       // begin the store again
    output reg        busy,
    output reg [5:0]  port,
    output reg [5:0]  src,            // held party while busy; 00 if none

    output reg [2:0]  ndig,          // digits in the store since the last restart
    output reg [19:0] digits,        // the store: slot 0 in [4:0], as pulse counts (5 bits, D=16)
    output reg        gone,          // CLR, or no digit at all
    // WHICH of the two.  The marker treats them alike -- the register is free
    // and the call is over either way -- and only counters.md 9's event word
    // wants to tell them apart, so this is one conductor on the ribbon that
    // already carries the digits.
    output reg        nodig,
    output            brk            // a break just counted (network.md 3's guard)
);
    // the probe: a listener's two selects and a flip-flop, at mid-cell
    reg  m_cap;
    wire w = (tick == 3'd4) && (slotq == port[2:0]);
    always @(posedge clk or negedge rst_n)
        if (!rst_n)   m_cap <= 1'b0;
        else if (w)   m_cap <= ha[port[5:3]];

    wire [4:0] p_cnt;
    wire       p_stb, p_clr, p_counting;
    pulse_rx #(.HIT(HIT), .ID(ID), .CLR(CLR)) u_rx (
        .clk(clk), .rst_n(rst_n), .tick_1k(tick_1k), .arm(busy), .m(m_cap),
        .cnt(p_cnt), .dig_stb(p_stb), .clear(p_clr), .counting(p_counting),
        .brk_stb(brk));

    reg [15:0] idle_ms;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0; port <= 0; src <= 0; ndig <= 0; digits <= 0; gone <= 0; idle_ms <= 0;
            nodig <= 0;
        end else begin
            gone <= 1'b0; nodig <= 1'b0;
            if (attach && !busy) begin
                busy <= 1'b1; port <= attach_port; src <= attach_src; idle_ms <= 0;
                ndig <= 3'd0; digits <= 20'd0;
            end else if (release_it) begin
                busy <= 1'b0; src <= 6'd0; ndig <= 3'd0; digits <= 20'd0;   // an idle store is empty
            end else if (busy) begin
                // A digit completing in the very cycle of a restart belongs to
                // the NEW store, slot 0 -- it must not be lost, and must not be
                // read as the old store's next digit.
                if (restart) begin
                    if (p_stb) begin digits <= {15'd0, p_cnt}; ndig <= 3'd1; end
                    else       begin digits <= 20'd0;          ndig <= 3'd0; end
                    idle_ms <= 0;
                end else if (p_stb) begin
                    if (ndig < 3'd4) begin
                        digits[ndig*5 +: 5] <= p_cnt;
                        ndig <= ndig + 1'b1;
                    end
                    idle_ms <= 0;
                end
                if (p_clr) begin gone <= 1'b1; busy <= 1'b0; src <= 6'd0; ndig <= 3'd0; digits <= 20'd0; end
                if (tick_1k && !p_counting) begin
                    if (idle_ms == NODIG[15:0]) begin
                        gone <= 1'b1; nodig <= 1'b1;
                        busy <= 1'b0; src <= 6'd0; ndig <= 3'd0; digits <= 20'd0;
                    end
                    else idle_ms <= idle_ms + 1'b1;
                end
            end
        end
    end
endmodule

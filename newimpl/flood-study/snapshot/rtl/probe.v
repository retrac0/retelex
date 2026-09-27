// probe -- the scanner-addressed listener.  One 74HC688, a quarter of a '08
// and half a '74.
//
// This is the only thing in the exchange that reads the supervision planes
// besides a port, and the marker, every register, every monitor and any
// observer use the same one.  Tie `port` to SCAN and it follows the scanner,
// holding whatever port just went by; tie it to a held number and it watches
// that one port.  In the old tree this was two '151s, a '74 and two '164s on
// the highways and the probe bus, and it needed /BLK steered at it.  It needs
// nothing steered at it now.
//
// ONE TURN, BOTH FACTS.  /HA carries M and /HB carries BUSY, and port p owns
// bit-time p on both, so a turn is ONE frame and the pair is captured at one
// instant.  There is no phase bit, no half-sample to carry across a frame
// edge, and no way for a reader to see a port's M paired with its neighbour's
// BUSY.  A pass is 64 bit-times, 1 ms, so a port refreshes at 1 kHz.
//
// THE PER-PORT CLEAR IS NOT OPTIONAL.  The old marker accumulated M with no
// clear, which was harmless only because a visit was eight frames and the last
// sample won.  With ONE sample a port, an uncleared accumulator hands the
// reader the PREVIOUS port's hook: a phone nobody lifted is given dial tone
// and a phone that did lift is never seen.  (fabric-rev2.md 6.1, retired.)
// `got` is that clear: a turn publishes only if this probe actually sampled
// it, so a probe re-pointed mid-turn publishes nothing rather than a mixture.
//
// m and busy are LEVELS, held until that port comes round again 1 ms later.
// rtl.md 1: an event on a wire is a race; a level valid when read is not.
`timescale 1ns/1ps
`include "exch.vh"

module probe (
    input                  clk,
    input                  rst_n,

    input      [2:0]       slotq,      // the strobe decoder's address
    input                  cap_stb,    // mid-cell
    input                  frame_stb,  // the frame edge: a bit-time begins

    input      [`SCANW-1:0] scan,      // the port whose turn it is
    input                  ha_n,       // /HA as received.  IDLE HIGH.  M
    input                  hb_n,       // /HB as received.  IDLE HIGH.  BUSY

    input      [`PW-1:0]   port,       // the port to watch

    output reg             m,          // its hook, held
    output reg             busy,       // its BUSY, held
    output reg [`PW-1:0]   port_q,     // which port the held pair belongs to
    output reg             fresh       // one tick: the pair has just been renewed
);
    // The capture instant: strobe line 4's falling edge, which is the middle
    // of cell 4 -- 8.79 us into the 15.63 us bit-time, 6.84 us of hold after.
    // The line is already SLOTQ-addressed and so already free of fabric.md
    // 3.2's hazard; reusing it costs nothing.  Both wires are sampled here, so
    // they share one settling budget and may have identical pull-ups.
    wire a_stb = cap_stb && (slotq == `CELL_A);

    reg [`PW-1:0] acc_port;  // the port whose turn is in progress
    reg           want;      // latched at the turn's start: is it ours?
    reg           m_acc, b_acc, got;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m <= 1'b0; busy <= 1'b0; port_q <= {`PW{1'b0}}; fresh <= 1'b0;
            acc_port <= {`PW{1'b0}}; want <= 1'b0;
            m_acc <= 1'b0; b_acc <= 1'b0; got <= 1'b0;
        end else begin
            fresh <= 1'b0;

            // ha_n and hb_n are low true: an open drain pulls down for a one.
            if (a_stb && want) begin
                m_acc <= ~ha_n;
                b_acc <= ~hb_n;
                got   <= 1'b1;
            end

            // A turn is one frame, so it ends -- and the next begins -- at
            // every frame edge.
            if (frame_stb) begin
                // publish the turn that just ended, if we sampled it.
                if (got) begin
                    m      <= m_acc;
                    busy   <= b_acc;
                    port_q <= acc_port;
                    fresh  <= 1'b1;
                end
                // and start the next one.  These win: same signals, later
                // assignment, and every right-hand side above read the old
                // values.
                acc_port <= scan;
                want     <= (port == scan);
                got      <= 1'b0;
            end
        end
    end
endmodule

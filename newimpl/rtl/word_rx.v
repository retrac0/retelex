// word_rx -- the card word reader: a select on /WS in the port's own
// bit-time, and /HW into eight bits.  NETWORK.
//
// Whatever reads a card's option word -- the mini marker before it takes a
// caller, the network unit before it holds or hunts a trunk -- asks this
// board for a port, and this board does the rest.  It waits for that port's
// TURN on the scan, pulls /WS for that one bit-time, and takes the eight
// frames of /HW that follow.  About six packages: a '174 holding the port, a
// '688 comparing it with SCAN, two '161s -- the window and the count -- a
// '259 for the octet, and a 2N7002 onto /WS.
//
// THE SCAN IS THE POINTER.  Every block samples /WS at the capture instant,
// with /HA and /HB; the one whose number is SCAN[5:3] latches SCAN[2:0] and
// puts that slot's card on /HW until the next select (block.v).  Naming a
// port costs one bit-time.  It used to cost a pointing word: sixteen SCLKs on
// cable B with WR suppressed, 125 us, as long as the octet it pointed at, and
// the bus held across the read so that no other word could move the pointer.
// Now cable B carries writes and nothing else.  The price is that a read
// starts only at its port's turn -- up to a pass, 1 ms, to wait.  (Joel,
// 2026-09-25: "the scanner hits the address, the marker triggers the clock
// out and this proceeds while the scanner just moves on".)
//
// NOBODY OWNS /WS, AND NOTHING CAN COLLIDE ON IT.  A select names whichever
// port's turn it is, so two readers pulling it in one bit-time name the SAME
// port, and both take its word.  The one rule is not to select while
// somebody's word is on /HW: every reader watches /WS and, after any select,
// counts off that read's eight frames before it may pull it again.  No rank,
// no request line, no wait.
//
// THE CARD SETS THE BIT ORDER, NOT THIS READER.  A card's '165 is loaded in
// frame 7 of every octet and shifted at each frame edge after it
// (baseband_card.v; card-word.md §3), so frame 7 carries bit 0, frame 0 bit 1,
// and frame f bit f+1 mod 8.  The octet position is SCAN[2:0], so the eight
// frames after a select hold all eight bits, starting wherever the port's
// slot puts them, and the '259's outputs are wired rotated by one so each
// lands in its own place.
//
// A ONE IS A PULLED-DOWN FRAME.  card-word.md §2: "A 1 is the pin pulled low".
// /HW idles high, so a port with no card, a card held off by its power-up RC,
// and a trunk whose link is down all read ALL ZEROS -- which the word table
// calls "none / OOS".  An absent card fails SAFE.  The trap is only for a
// reader that takes the wire's level as the bit, which reads the same absence
// as all ones, a plain line.
//
// ONLY THE PRIMARY OCTET.  A sixteen-bit word at 64 kHz needs its card to load
// every sixteen frames, and the socket carries no strobe that marks sixteen
// (TX_OCT marks eight).  Everything a trunk says -- class, glare, direction --
// is in the primary.  The secondary is the class marker's problem, recorded
// as open in card-word.md §8 and newimpl/README.md 6.
//
//   fabric.md §4; card-word.md §2, §3; bus.md §2.1; newimpl/README.md 1
`timescale 1ns/1ps
`include "exch.vh"

module word_rx (
    input                   clk,
    input                   rst_n,

    // ---- the bus: timing, scan and the planes ------------------------------
    input      [2:0]        slotq,
    input                   cap_stb,
    input                   frame_stb,
    input      [`SCANW-1:0] scan,
    input                   hw_n,        // /HW.  IDLE HIGH.  Low is a one
    input                   ws_n,        // /WS as received: anybody's select, ours included
    output reg              ws_pd,       // this board pulling /WS down: a select, one bit-time

    // ---- this card's side ------------------------------------------------------
    input                   rd_req,      // one tick: read rd_port's primary octet
    input      [`PW-1:0]    rd_port,
    output                  busy,        // a read is waiting for its turn, or collecting
    output reg              done,        // one tick: `word` is the port's octet
    output reg [7:0]        word
);
    // The capture instant is the planes' own: strobe line 4's falling edge,
    // mid-cell 4, 8.79 us into the frame.  /WS and /HW are sampled with /HA
    // and /HB and share their settling budget (exch.vh).
    wire a_stb = cap_stb && (slotq == `CELL_A);

    // 74HC259 -- eight addressable latches, addressed by SCAN[2:0].  Its
    // output Qk is WIRED as bit (k+1) mod 8: layout, not an adder.
    wire [2:0] place = scan[2:0] + 3'd1;

    reg           want;     // a read is waiting for its port's turn
    reg [`PW-1:0] at;       // ... and for which port: a '174
    reg [3:0]     win;      // frames of SOMEBODY's read still on /HW: a '161
    reg [3:0]     n;        // frames of OUR read still to take: a second '161

    assign busy = want || (n != 4'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            want <= 1'b0; at <= {`PW{1'b0}}; win <= 4'd0; n <= 4'd0;
            ws_pd <= 1'b0; done <= 1'b0; word <= 8'd0;
        end else begin
            done <= 1'b0;

            // THE SELECT.  Decided at the frame edge, when SCAN has just
            // stepped to the port whose bit-time this is, and held for the
            // whole bit-time: a '688 on SCAN against the wanted port, and
            // nobody's word on /HW.  Released at the next edge, so /WS is
            // back up long before the next frame's capture.
            if (frame_stb) ws_pd <= want && (scan == at) && (win == 4'd0);

            if (a_stb) begin
                if (!ws_n) begin
                    // Somebody selected -- this board, if it pulled; another
                    // reader, if not.  Either way a word is on /HW for the
                    // next eight frames, and nobody may select until it ends.
                    win <= 4'd8;
                    if (ws_pd) begin
                        // A new read clears the latch first: a bit this read
                        // never took must not be left over from the last port.
                        want <= 1'b0; n <= 4'd8; word <= 8'd0;
                    end
                end else begin
                    if (win != 4'd0) win <= win - 4'd1;
                    if (n != 4'd0) begin
                        word[place] <= ~hw_n;
                        if (n == 4'd1) done <= 1'b1;
                        n <= n - 4'd1;
                    end
                end
            end

            // A request always lands.  These win: same signals, later
            // assignment.  An owner asks only while this board is idle, so a
            // request never meets its own select; if one ever did, it would
            // be the next read, waiting out this one's window.
            if (rd_req) begin want <= 1'b1; at <= rd_port; end
        end
    end
endmodule

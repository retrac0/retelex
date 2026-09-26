// word_dec -- what a card's primary octet says about its port.  MAXIMAL.
//
// The octet as word_rx hands it over: bit n is bit-time n, the pin low for a
// one (card-word.md §2).  Two type bits, then either a class -- a family of
// two bits and a member of one, and three options -- or a 6-bit port.  This is
// the whole of the class marker's "diode matrix" on the word side: every test
// it makes of a port is one of these outputs, and none of them is a memory.
//
//   bit-time   0 1   2 3   4   5 6 7
//   class      1 1   a a   m   p p p      family, member, options
//   port form  t t   s s s     h h h      00 tied nail, 01 answers-to, 10 call nail
//                                         (wire order: bit-time 0 first)
//
// THE TWO CONSTANTS DECIDE FIRST.  All zeros is no card -- an empty socket, a
// card in its power-up RC, a trunk whose link is down -- and reads NONE, never
// a tied nail to 00.  All ones is a plain line, a grounded pin and no part
// fitted; decoded by its bits it would be class restricted with bit 7 set,
// which is out of service, so the constant is taken before the class is.
//
// ONLY THE PRIMARY.  A card reloads its word every eight frames and the
// socket marks nothing at sixteen, so a reader on /HW gets bits 0-7 (README
// 6).  Covers, dual numbers and the L/U/K conditions live in the secondary
// and are not here; the two reserved tag-00 forms cannot be failed closed,
// and read as the local form their primary spells.
//
// On a board: half a '139 on the type bits, a '138 on the class code, and a
// few gates for the must-be-zero bits and the options.  Combinational: the
// marker latches what it needs beside the word.
//
//   card-word.md §2, §4-§6; marker.md §4
`timescale 1ns/1ps
`include "exch.vh"

module word_dec (
    input      [7:0]     w,          // the primary octet, bit n = bit-time n
    output               none,       // 00: no card, held off, or link down
    output               oos,        // a card that says nothing usable: reserved
                                     // class, unequipped code, or an MBZ bit set
    output               plain,      // FF: a plain line, no options
    output               line,       // class line (member 0), or the plain constant
    output               rest,       // class restricted
    output               src,        // class source: listened to, never written
    output               out,        // class outside line
    output               trunk,      // a flood seat: class trunk, member 0
    output               tone,       // a tone trunk: offers tone on seize
    output               tnail,      // tied nail to `hs`
    output               ans,        // answers to the number `hs`
    output               cnail,      // call nail: on lift, as if `hs` were dialled
    output     [`PW-1:0] hs,         // the port form's six bits, h s as a number
    output               pri,        // line option P (frame 5)
    output               bout,       // busy-out / busy-inbound (frame 6)
    output               data,       // line option D (frame 7): a data line
    output               zonly,      // restricted option z: only 0 completes
    output               voice,      // a voice line: may call and be called
    output               caller      // its M, BUSY clear, is a call request
);
    wire       k_none  = (w == 8'h00);
    wire       k_plain = (w == 8'hFF);
    wire [1:0] typ     = w[1:0];
    wire [2:0] cls     = w[4:2];         // {m, a a}: 0 unequipped .. 7 restricted
    wire       form    = !k_plain && (typ == 2'b11);

    // the class codes, each one output of the '138
    wire c_uneq = form && (cls == 3'd0);
    wire c_src  = form && (cls == 3'd1);
    wire c_trk  = form && (cls == 3'd2);
    wire c_line = form && (cls == 3'd3);
    wire c_rsvd = form && (cls == 3'd4);
    wire c_out  = form && (cls == 3'd5);
    wire c_tone = form && (cls == 3'd6);
    wire c_rest = form && (cls == 3'd7);

    // MUST-BE-ZERO IS ENFORCED, NOT IGNORED: a one where a zero belongs is out
    // of service (card-word.md §2).  Source, outside line and tone trunk
    // take no options; restricted's frame 7 is what keeps a class word off the
    // plain-line constant; the reserved code and the unequipped one are never
    // sent by a card that works.
    wire mbz = (c_src || c_out || c_tone) ? (w[7:5] != 3'b000) :
               c_rest                     ? w[7] : 1'b0;
    assign oos   = c_rsvd || c_uneq || mbz;

    assign none  = k_none;
    assign plain = k_plain;
    assign line  = k_plain || c_line;
    assign rest  = c_rest && !mbz;
    assign src   = c_src  && !mbz;
    assign out   = c_out  && !mbz;
    assign trunk = c_trk;                // g d d are all three options: no MBZ
    assign tone  = c_tone && !mbz;

    // THE TYPE IS PRINTED IN WIRE ORDER, AS EVERY FIELD IS: answers-to's "01"
    // is bit-time 0 low and bit-time 1 high, so w[1:0] reads 2'b10 -- the way
    // a trunk's family "01" is w[3:2] = 2'b10 and WORD[4:2] = 2 (card-word.md
    // §2, "the type bits are wire order too").  The old marker.v compared the
    // other way.
    assign tnail = !k_none && (typ == 2'b00);
    assign ans   = (typ == 2'b10);
    assign cnail = (typ == 2'b01);
    assign hs    = w[7:2];

    // The options.  The plain constant has none: its all-ones are the pin,
    // not three set bits.
    assign pri   = c_line && w[5];
    assign bout  = (c_line || rest) && w[6];
    assign data  = c_line && w[7];
    assign zonly = rest && w[5];

    // A voice line: what a dialled number may be connected to and what may
    // lift for a register.  An answers-to or a call-nail port is a line that
    // says one thing more.  A data line is in neither list (card-word.md
    // §4: "D is enforced by omission").
    assign voice  = (line && !data) || rest || ans || cnail;
    // A tone trunk is a caller at a leaf's central (leaf-uplink.md), not a
    // line: it is never dialled.
    assign caller = (line && !data) || rest || ans || tone;
endmodule

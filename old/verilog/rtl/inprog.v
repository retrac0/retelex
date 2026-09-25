// inprog -- the calls-in-progress display.  inprogress.md.
//
// A card that only listens.  It counts the ports that read BUSY on the probe
// in one complete pass of the marker's scanner and shows the total on two
// seven-segment digits in OCTAL, which is the exchange's own radix
// (protocol.md 5: "Octal as dialled").  Port 00 is "idle: never fitted", so
// the largest number the exchange can produce is 63 busy ports -- 77 octal --
// and two octal digits hold the whole range with nothing wasted.
//
// EIGHT CONDUCTORS.  CLK_8K off cable A (pin 21); PB0, /CON, SCAN[2:0],
// ADVANCE and START off cable B (mainboard.md 2.3.3).  No /BLK, no shunt
// column, no SDATA, no SCLK, no word, no connection to the marker.
//
// WHY THE SCANNER'S PORT AND NOT SLOT.  The probe is not slot-commutated.
// fabric.md 1.1 says in bold that the BUSY and word muxes are addressed by
// the scanner -- "not by SLOT" -- and block.v:108 is
//
//     wire [2:0] pb_sel = con_n ? scan_port : cw[10:8];
//
// so PB0 carries ONE port, held steady for the whole 125 us visit.  A card
// that clocked PB0 against SLOTQ would write one port's bit into all eight
// outputs of a row.
//
// THE THREE SIGNALS ARE ONE ADDRESS, AND THEY CHECK EACH OTHER.
//
//   SCAN[2:0]  which port PB0 belongs to.  Stateless: three wires, no counter,
//              nothing to align, and it follows an out-of-turn probe steer
//              (marker.md 4) for free, which no local counter can.
//   ADVANCE    the scanner's count enable gated by the clock (marker.v:485's
//              `if (pv) scan <= scan + 1'b1`).  A visit with no ADVANCE is a
//              REPEATED visit, so counting on ADVANCE de-duplicates exactly --
//              and it needs no comparison at all, where SCAN alone wanted a
//              '175 and an '86 to spot the repeat.
//   START      high through port 00's visit.  The pass boundary, so the card
//              does not count wraps to find it.
//
// ANY ONE OF THEM IS REDUNDANT AGAINST THE OTHER TWO, so the card carries a
// six-bit counter clocked by ADVANCE and cleared by START whose ONLY job is to
// disagree:
//
//     SCAN != (ADVANCE last tick ? prev+1 : prev)
//                                       the step rule.  NOTE the direction:
//                                       ADVANCE says THIS visit's port is the
//                                       last one for that port, so the port
//                                       changes on the tick AFTER it.  At a
//                                       block boundary the real marker gives
//                                       (7,adv) (0,no-adv) (0,adv) -- SCAN
//                                       changes ON a non-advancing visit, and
//                                       a checker that read it backwards would
//                                       fire at every block end
//     START     != (lcnt == 0)          not exactly 64 ADVANCEs in the pass --
//                                       a jump of 8, 16 ... preserves the low
//                                       three bits, so only the count sees it
//     unarmed for two passes            ADVANCE or START dead from reset: no
//                                       rule above can fire, because none of
//                                       them runs until a START has armed the
//                                       card.  Without this the display sits
//                                       at a plausible 00 for ever
//
// A THIRD RULE WAS TRIED AND TAKEN OUT: lcnt[2:0] != SCAN[2:0], an absolute
// check against the START anchor beside the step rule's relative one.  It
// caught nothing.  Deleting it left every check in tb_inprog green, and no
// cable fault could be constructed that the step rule did not catch first --
// it re-anchors to prev on every tick, so a jump fires it within one visit,
// and a jump of eight preserves the low three bits and is the count rule's
// business.  What it did guard was the step rule's OWN state, the '175; that
// is a card fault, not a cable fault, and it is not testable from outside.
// It is written up in inprogress.md 9 rather than shipped untested.
//
// ERR latches on any of them and holds until the reset key.  It is a check on
// the CABLE, not on the card's own reckoning -- the data path never uses lcnt.
// That is the difference between this and deriving the address locally: there
// the detector mostly catches your own inhibit being wrong, here it catches
// the wire.
//
// THE DE-DUP MATTERS BECAUSE THE MARKER DIRTIES ITS OWN PROBE constantly --
// marker.v:500 at every block end, :525 after every write, :546 after a yield
// -- and marker.v:485 says what that costs: "A re-point cannot finish before
// the visit it governs, so a disturbed visit is REPEATED, not lost."  A naive
// counter taking every visit reads high by the eight forced re-steers a pass
// plus one per write.  tb_inprog measures both side by side.
//
// /CON.  While the console holds the bus, block.v selects cw[10:8] and
// SCAN[2:0] no longer describes what is on PB0, so the card stops counting,
// holds the last complete pass, and lights FROZEN until it has re-aligned on
// a START and finished a whole pass.  It never shows a half-counted number,
// and it does not report ERR for a disagreement it was told to expect.
//
// IN 74HC.  Two '161 accumulate, two '161 are the check counter, a '175 holds
// the previous SCAN, an '86 and gates make the step rule, a NOR reads lcnt==0,
// and two '4511 are the latch, the decode and the segment drivers in one -- an
// octal digit is a BCD digit with the fourth bit grounded.  About nine
// packages and two displays (inprogress.md 7).
`timescale 1ns/1ps

module inprog (
    input            clk,
    input            rst_n,

    // cable A
    input            oct_stb,      // CLK_8K: one tick a port visit (125 us)
    // cable B
    input      [2:0] scan_port,    // the port the probe is showing
    input            scan_adv,     // the scanner stepped: this visit was not repeated
    input            scan_start,   // high through port 00's visit: a pass begins
    input            pb0,          // BUSY of the port SCAN names
    input            con_n,        // high while the marker owns the bus

    input            clr,          // the reset key: blank, re-align, clear ERR

    output     [2:0] dig_hi,       // the two octal digits ...
    output     [2:0] dig_lo,
    output     [6:0] seg_hi,       // ... through two '4511, {g,f,e,d,c,b,a}
    output     [6:0] seg_lo,
    output           ovf,          // 64 busy: will not fit two octal digits
    output           frozen,       // the display is older than the last pass
    output           err,          // the three cable signals disagree
    output           pass_stb,     // one tick as a pass latches (bench only)
    output     [6:0] count         // the latched total (bench only)
);
    // ---- the data path: ADVANCE counts, START latches --------------------
    reg  [6:0] acc;                // 2 x '161: busy ports so far this pass
    reg  [6:0] shown;              // the '4511 pair's own latches
    reg        armed;              // a START has been seen since resync
    reg        stale;              // /CON touched the pass in the display
    reg        latch;

    // ---- the check path: it never feeds the data path --------------------
    reg  [5:0] lcnt;               // 2 x '161, clocked by ADVANCE, cleared by START
    reg  [2:0] prev;               // '175: SCAN at the previous visit
    reg        prev_adv;           // ... and whether that visit advanced
    reg        unarm_wrap;         // one pass has gone by without arming
    reg        fault;

    always @(posedge clk) begin
        if (!rst_n || clr) begin
            acc   <= 7'd0;
            shown <= 7'd0;
            armed <= 1'b0;
            // FROZEN, not dark: nothing has been counted yet, and a blank 00
            // with every lamp out is the one reading this card must never
            // give.  It stays lit until a whole pass has latched.
            stale <= 1'b1;
            latch <= 1'b0;
            lcnt  <= 6'd0;
            prev  <= 3'd0;
            prev_adv <= 1'b0;
            unarm_wrap <= 1'b0;
            fault <= 1'b0;
        end else begin
            latch <= 1'b0;

            if (!con_n) begin
                // The console owns the probe.  Stop, do not trust the partial
                // pass, and do not call the disagreement an error.  The
                // watchdog starts again from here, so a tenure never counts
                // towards it.
                armed      <= 1'b0;
                stale      <= 1'b1;
                lcnt       <= 6'd0;
                unarm_wrap <= 1'b0;
            end else begin
                // ---- the checks ------------------------------------------
                if (oct_stb) begin
                    if (armed) begin
                        // the step rule, forwards: the port changes on the
                        // tick after the ADVANCE that released it
                        if (scan_port != (prev_adv ? prev + 3'd1 : prev))
                            fault <= 1'b1;
                        if (scan_adv && (scan_start != (lcnt == 6'd0)))
                            fault <= 1'b1;
                    end
                    prev     <= scan_port;
                    prev_adv <= scan_adv;
                end

                // ---- the counters ----------------------------------------
                if (!armed) begin
                    // THE WATCHDOG.  Unarmed, count VISITS and not advances:
                    // if ADVANCE is the dead conductor there are none to
                    // count, and if START is the dead one no pass ever opens.
                    // Either way the card would otherwise sit blank and silent
                    // for ever, which is the failure of section 7.  Two passes
                    // without a START is a conductor, not a wait: the next
                    // START is never more than 64 visits away.
                    if (oct_stb) begin
                        lcnt <= lcnt + 1'b1;
                        if (lcnt == 6'd63) begin
                            if (unarm_wrap) fault <= 1'b1;
                            unarm_wrap <= 1'b1;
                        end
                    end
                    if (scan_adv && scan_start) begin          // align here
                        armed      <= 1'b1;
                        lcnt       <= 6'd1;
                        acc        <= {6'd0, pb0};
                        unarm_wrap <= 1'b0;
                    end
                end else if (scan_adv) begin
                    lcnt <= scan_start ? 6'd1 : lcnt + 1'b1;
                    if (scan_start) begin
                        shown <= acc;                          // 64 samples
                        latch <= 1'b1;
                        stale <= 1'b0;
                        acc   <= {6'd0, pb0};                  // port 00 opens
                    end else
                        acc <= acc + {6'd0, pb0};
                end
            end
        end
    end

    assign count    = shown;
    assign ovf      = shown[6];
    assign dig_hi   = shown[5:3];
    assign dig_lo   = shown[2:0];
    assign frozen   = stale;
    assign err      = fault;
    assign pass_stb = latch;

    // ---- two 74HC4511: an octal digit is a BCD digit, D grounded ---------
    function [6:0] seg7(input [2:0] d);
        case (d)                       //  g f e d c b a
        3'o0: seg7 = 7'b011_1111;
        3'o1: seg7 = 7'b000_0110;
        3'o2: seg7 = 7'b101_1011;
        3'o3: seg7 = 7'b100_1111;
        3'o4: seg7 = 7'b110_0110;
        3'o5: seg7 = 7'b110_1101;
        3'o6: seg7 = 7'b111_1101;
        3'o7: seg7 = 7'b000_0111;
        endcase
    endfunction

    assign seg_hi = seg7(dig_hi);
    assign seg_lo = seg7(dig_lo);
endmodule

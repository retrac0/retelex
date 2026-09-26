// exch.vh -- the exchange's geometry, and the one width knob.
//
// There is no module here and no configuration here.  Everything below is a
// fact about the board: eight highways, eight slots, sixty-four ports, and
// where in a cell the two strobes fall.
//
// The one thing that could ever change is `PW.  At nine bits the supervision
// pass is 512 bit-times -- 8 ms, so a port's hook refreshes at 125 Hz, which
// is two samples in a dial break.  To keep a kilohertz at 512 ports you would
// have to put A back on the 512 kHz cell grid, which is to undo the fold.
// THE FOLD AND THE SIX-BIT ADDRESS ARE ONE DECISION.
//
//   fabric.md §2.1, why-bits.md, numbering.md §1

`ifndef EXCH_VH
`define EXCH_VH

// ---- the fabric ---------------------------------------------------------
`define NB 8              // blocks == highways.  Block h drives HC[h]
`define NS 8              // slots a block: the eight cells of a 64 kHz frame
`define NP 64             // ports.  A port's address IS its dialled number h s

// ---- PORT ADDRESS WIDTH -------------------------------------------------
// WIDENS WITH `PW.  Five sites, each marked with this same phrase:
//   port.v      the '273 listen latch            8 bits -> two packages
//   port.v      the source compare               one '688 -> '688 + half an '85
//   probe.v     the same compare                 likewise
//   block.v     the write decoder and block '138 two '138 -> a '154
//   ctl_write.v the control word                 16 bits, two '164 -> three
`define PW    6           // [5:3] highway h, [2:0] slot s
`define SCANW 6           // == `PW.  The scanner's address IS a port number:
                          // one slot a port, A on /HA and BUSY on /HB at once.
`define CWW   16          // 2*`PW + 4: G, spare, DST, SRC, BSY, CLM

// ---- the supervision plane ----------------------------------------------
// TWO open-collector conductors, /HA and /HB, both idle HIGH, both addressed
// by SCAN: in slot p, port p pulls /HA for its M and /HB for its BUSY.  A
// pass is `NP bit-times -- 64 frames, 1 ms -- so a port refreshes at 1 kHz.
//
// A pass is therefore EXACTLY the TICK period: 64 frames x 64 master ticks is
// 4096, so the pass boundary and TICK are one edge and SCAN[5:0] are the six
// divider stages that sit between TX_CLK and TICK.  Nothing is added to the
// chain to make the scanner; it is the chain.
//
// The card option word is NOT here.  It is a third conductor, /HW, which all
// 64 cards share and a READER addresses: it pulls a fourth, /WS, in the
// bit-time of the port it wants, and that card alone drives its word onto
// /HW at 64 kHz, one bit a frame, until the next select.  The scan only NAMES
// the card; nothing continuous depends on /HW, so the scanner never waits for
// it -- which is the whole reason the word is not on the scan.
//   bus.md §1, §2.1, card-word.md §2

// ---- where things happen inside a cell ----------------------------------
// The master clock is the 4.096 MHz crystal and a cell is eight of its ticks.
`define TICK_SLOTQ 3'd2   // the '175 takes SLOT here: a quarter cell late
`define TICK_MID   3'd4   // mid-cell.  Every capture clock W

// ---- the A/BUSY capture cell --------------------------------------------
// Strobe line 4 does double duty: the C capture for a port listening to slot
// 4, and EVERY A, BUSY and word capture in the exchange.  Its falling edge is
// the middle of cell 4 -- 8.79 us into the 15.63 us bit-time, with 6.84 us of
// hold after it.  The line is already SLOTQ-addressed and so already free of
// fabric.md §2.2's hazard.  /HA, /HB and /HW are all sampled here, so one
// settling budget covers all three and the pull-ups may be identical.
`define CELL_A 3'd4

`endif

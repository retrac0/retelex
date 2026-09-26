// 74hc.v -- the 74HC parts as the netlist check sees them.  NOT THE HAND RTL.
//
// newimpl/rtl is the reference, and its STYLE forbids a chip library: a
// module there is a board.  This file is the other side of the comparison.
// A schematic in pcb/ is exported as a KiCad netlist, turned into structural
// Verilog -- one instance per package, wired pin by pin -- and that netlist
// runs on the same benches as the RTL.  Every package it instantiates is one
// module here.  Nothing in newimpl includes this file.
//
// ---- NAMES ---------------------------------------------------------------
//
// A module is named by its part: hc151 is a 74HC151.  A port is the datasheet
// pin name (Nexperia's 74HC sheets), made into an identifier by two rules and
// one exception, and nothing else:
//
//   an overbar becomes a trailing _n           /E      -> E_n
//   a leading section number moves to the end  1A     -> A1      1OE -> OE1_n
//     of the name, after an underscore if the  1A0    -> A0_1    (the '244)
//     name already ends in a digit             1I0    -> I0_1    (the '157)
//   '=' is spelt _EQ_                          /P=Q    -> P_EQ_Q_n  (the '688)
//   an open drain's port is pd, for the one open drain there is: a FET's D.
//
// tb/check_pins.py applies these rules to every row and fails on a port they
// do not produce.  KiCad's own pin NAMES are no help: the gates' pins have
// none, 74LS148 pin 10 is "IO" with a letter O, and the symbols mix LS and HC
// naming ('151 Z for Y, '688 R for Q, '175 Mr for MR).  PIN NUMBERS are what
// the netlist carries, and they are what the tables below key on.
//
// ---- THE PIN TABLES ------------------------------------------------------
//
// Every part carries one, in lines that begin '//|'.  tb/mkpinmap.py reads
// them and writes pinmap.json; tb/check_pins.py checks each table against
// the module's own port list, against the KiCad stock symbol it names (pin
// numbers, electrical types, and the names where the symbol has them), and
// pinmap.json against the tables.  The columns:
//
//   pin   the DIP pin number, as in the KiCad symbol
//   port  the Verilog port, or '-' for a pin that is not a port
//   ds    the datasheet name, '/' for an overbar
//   type  in     an input
//         out    a totem-pole output
//         tri    a tri-state output: TWO ports, the value <port> and the
//                enable <port>_oe.  The value is driven whether or not the
//                output is enabled
//         od     an open drain: one port, 1 = pulling the net low
//         power  a supply pin, and the rail it must be on
//         nc     not connected inside
//
// THERE IS NO 'z' ANYWHERE IN THIS FILE.  A net with more than one driver --
// a tri-state bus, a wired-OR, a resistor to a signal net -- is resolved by
// the generator, outside the models, exactly as block.v's ha_pd/ha_n pair
// does it: ~|pd, or |oe ? value : pull.  newimpl/STYLE.md 6: "two drivers on
// one conductor read as 1'bx"; that is the generator's clash monitor too.
//
// Power pins are not ports.  The generator checks them against the rails the
// table names, and a package whose VCC is not on +5V is a netlist error, not
// a simulation.
//
// ---- DELAYS --------------------------------------------------------------
//
// MEASURED (pcb/out/synth_dly): Verilator 5.050 --timing ignores the delay on
// a continuous assignment -- 'assign #2 y = ~a' updates at once, at top level
// and in a submodule -- and honours a procedural one.  So every output here
// goes through hc_dly1, a procedural INERTIAL delay: an output takes a new
// value TPD after its input function last changed, and only if the function
// has held that value for the whole TPD.  That is what 'assign #d' means in
// Icarus, and it swallows the zero-width delta glitches that a zero-delay
// model makes when two inputs change in one time step (tool.md 3: 1238 false
// clashes under Icarus).  A glitch wider than TPD passes, at its own width.
// Define HC_TRANSPORT to make every delay a transport delay instead, which
// passes every glitch however narrow -- for hunting hazards, not for benches.
//
// Each output has ONE delay, the part's slowest typical input-to-output path.
// The figures are typicals at VCC = 5 V, CL = 15 pF, 25 C, as Nexperia prints
// them, rounded to the nanosecond; they are from memory, not re-read, and the
// worst case (4.5 V, 50 pF, 85 C) is about two and a half times as long.
//
//   part    TPD   path                   part    TPD   path
//   '00      7    nA -> nY               '138    12    An -> /Yn
//   '02      7                           '148    14    /In -> /An
//   '04      7                           '151    17    Sn -> Y
//   '08      7                           '157    14    S -> nY
//   '11      9                           '164    13    CP -> Qn
//   '14     12    (a Schmitt)
//   '32      8                           '175    14    CP -> Qn
//   '86     11                           '244     9    nAn -> nYn, enable 12
//   '4002   10
//   '74     14    nCP -> nQ, and /SD /RD '273    15    CP -> Qn
//   '125     9    enable 11              '595    16    STCP -> Qn, SHCP -> Q7S,
//   '4051   18    Sn -> Z                              enable 15
//                                        '688    16    Pn -> /P=Q
//                                        2N700x   5    G -> D (the switch only)
//
// The longest chain in a block -- HCLK through the strobe '138, the slot
// '151 and the capture '74 -- is about 45 ns against a 244 ns master tick and
// a 977 ns strobe, so no bench result can hang on these numbers, EXCEPT where
// the board itself races two paths from one edge (RX_OCT's '74 on TX_CLK
// against TX_OCT's '11 on SCAN: pcb/out/inv.md 6, gap 2).  There the answer
// depends on the delays and the harness has to model the '4040's ripple;
// hc_tchk below reports the race instead of hiding it.
//
// Every delay is a parameter of its module, so an instance can be slowed.
//
// ---- TIMING CHECKS ---------------------------------------------------------
//
// A flip-flop here samples D at the instant of the clock edge: zero setup,
// zero hold.  hc_tchk watches each edge-triggered part and prints a line
// beginning 'HC-TIMING' when D moved inside the datasheet's setup or hold
// window -- where the model's answer is the simulator's, not the part's.
// Define HC_NO_TCHK to remove the checks.  Limits are the 4.5 V, 25 C
// minimums, from memory: setup 12 ns (15 for the '74), hold 3 ns.  The
// '595's storage clock is also watched against its own shift register: the
// SHCP-to-STCP set-up, 15 ns, and no hold, because the clocks may be tied.
//
// ---- WHAT IS NOT HERE ------------------------------------------------------
//
// Input thresholds and the '14's hysteresis (a Schmitt is an inverter with a
// longer delay).  Drive strength, fanout and load-dependent delay.  The
// '4051 as an analog switch: it is modelled one way, Yn into Z, and cannot
// carry a signal from Z out to a Y pin.  Minimum pulse widths.  Power-on
// state: a flip-flop starts unknown (x under Icarus, 0 under Verilator's
// two-state default), and a bench that needs it known must reset or clock
// it, as the board must.
//
// The RC networks are MACRO CELLS at the end of this file (rc_det, cr_rel,
// rc_filt), because a digital simulator has no capacitor.  rc_det runs
// port.v's own detector counter on the simulation-only tick_1k, so the
// comparison against the RTL is exact; the R and C values are checked by
// calculation, not here.
`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// THE DELAY CELLS
// ============================================================================

// hc_dly1 -- one output's delay.  Inertial: y takes a's value once a has held
// it for DR (rising) or DF (falling) nanoseconds.  Each change of a forks a
// timer carrying a serial number; when a timer runs out it writes y only if
// no later change has happened since, so a pulse shorter than the delay never
// reaches y.  One writer of y at a time, and nothing has two drivers.
//
// WHY A FORKED TIMER AND NOT A DELAYED NONBLOCKING ASSIGNMENT.  Verilator
// 5.050 keeps ONE pending intra-assignment-delay update per variable: a second
// 'x <= #d v' issued while the first is pending replaces it, and the survivor
// fires at the FIRST one's time.  Measured (pcb/out/dlyx): two changes of a
// inside one delay left y at the old value for good.  Every output in this
// file goes through here, so that was every glitch in a netlist.  A task
// forked per change keeps each timer to itself, in Verilator and Icarus.
//
// A timer is also forked at time 0, at the longer delay, so a tied or constant
// input still reaches the output: Verilator raises no event for a net born at
// its value.  INIT gives y a value from time 0 -- rc_filt's discharged
// capacitor; -1 leaves y unknown until the first timer runs out.
module hc_dly1 #(
    parameter integer DR   = 7,
    parameter integer DF   = DR,
    parameter integer INIT = -1
)(
    input  wire a,
    output reg  y
);
    integer seq;

    task automatic tmr(input integer s, input reg v);
        begin
            if (v === 1'b1) #(DR); else #(DF);
`ifdef HC_TRANSPORT
            y = v;
`else
            if (seq == s) y = v;
`endif
        end
    endtask

    initial begin
        if (INIT >= 0) y = (INIT != 0);
        seq = 0;
        fork begin
            #(DR > DF ? DR : DF);
            if (seq == 0) y = a;
        end join_none
    end

    always @(a) begin
        seq = seq + 1;
        fork tmr(seq, a); join_none
    end
    /*verilator no_inline_module*/
endmodule

// hc_dly -- W outputs, each with its own hc_dly1, all of delay D.  Per bit,
// so one output's change never holds back another's.
module hc_dly #(
    parameter integer W = 1,
    parameter integer D = 7
)(
    input  wire [W-1:0] a,
    output wire [W-1:0] y
);
    genvar i;
    generate for (i = 0; i < W; i = i + 1) begin : bit_
        hc_dly1 #(.DR(D), .DF(D)) u (.a(a[i]), .y(y[i]));
    end endgenerate
    /*verilator no_inline_module*/
endmodule

// hc_tchk -- setup and hold on one edge-triggered input group.  Watches D
// against the rising edge of CP while EN (no asynchronous input is holding
// the part).  A change from an unknown value is the power-on settle, not a
// transition, and is not checked; neither is anything at time 0.
// n_setup and n_hold count, for a bench that wants the number.
module hc_tchk #(
    parameter integer W   = 1,
    parameter integer TSU = 12,
    parameter integer TH  = 3
)(
    input wire         CP,
    input wire         EN,
    input wire [W-1:0] D
);
`ifndef HC_NO_TCHK
    localparam [63:0] SU = {32'd0, TSU[31:0]};
    localparam [63:0] HO = {32'd0, TH[31:0]};
    integer     n_setup, n_hold;
    reg [63:0]  t_d, t_c;
    reg [W-1:0] d_seen;
    reg         c_seen, armed;
    initial begin
        n_setup = 0; n_hold = 0; t_d = 64'd0; t_c = 64'd0; armed = 1'b0;
        d_seen = D; c_seen = CP;
        forever begin
            @(CP or D);
            if (D !== d_seen) begin
                if ($time > 0 && ^d_seen !== 1'bx && armed && $time - t_c < HO) begin
                    n_hold = n_hold + 1;
                    $display("HC-TIMING hold   %m: D moved %0d ns after CP rose, at %0t",
                             $time - t_c, $time);
                end
                d_seen = D; t_d = $time;
            end
            if (CP === 1'b1 && c_seen === 1'b0) begin
                armed = (EN === 1'b1);
                if ($time > 0 && armed && $time - t_d < SU) begin
                    n_setup = n_setup + 1;
                    $display("HC-TIMING setup  %m: D moved %0d ns before CP rose, at %0t",
                             $time - t_d, $time);
                end
                t_c = $time;
            end
            c_seen = CP;
        end
    end
`else
    wire unused_tchk = &{1'b0, CP, EN, D, TSU[0], TH[0]};
`endif
    /*verilator no_inline_module*/
endmodule

// ============================================================================
// GATES
// ============================================================================

// hc00 -- 74HC00, quad 2-input NAND.
//| part hc00 value 74HC00 symbol 74xx:74HC00
//|  pin  port   ds    type
//|    1  A1     1A    in
//|    2  B1     1B    in
//|    3  Y1     1Y    out
//|    4  A2     2A    in
//|    5  B2     2B    in
//|    6  Y2     2Y    out
//|    7  -      GND   power GND
//|    8  Y3     3Y    out
//|    9  A3     3A    in
//|   10  B3     3B    in
//|   11  Y4     4Y    out
//|   12  A4     4A    in
//|   13  B4     4B    in
//|   14  -      VCC   power +5V
module hc00 #(parameter integer TPD = 7) (
    input  wire A1,
    input  wire B1,
    output wire Y1,
    input  wire A2,
    input  wire B2,
    output wire Y2,
    output wire Y3,
    input  wire A3,
    input  wire B3,
    output wire Y4,
    input  wire A4,
    input  wire B4
);
    hc_dly #(4, TPD) u_d (
        .a({~(A4 & B4), ~(A3 & B3), ~(A2 & B2), ~(A1 & B1)}),
        .y({Y4, Y3, Y2, Y1}));
    /*verilator no_inline_module*/
endmodule

// hc02 -- 74HC02, quad 2-input NOR.  The output is pin 1, not pin 3.
//| part hc02 value 74HC02 symbol 74xx:74HC02
//|  pin  port   ds    type
//|    1  Y1     1Y    out
//|    2  A1     1A    in
//|    3  B1     1B    in
//|    4  Y2     2Y    out
//|    5  A2     2A    in
//|    6  B2     2B    in
//|    7  -      GND   power GND
//|    8  A3     3A    in
//|    9  B3     3B    in
//|   10  Y3     3Y    out
//|   11  A4     4A    in
//|   12  B4     4B    in
//|   13  Y4     4Y    out
//|   14  -      VCC   power +5V
module hc02 #(parameter integer TPD = 7) (
    output wire Y1,
    input  wire A1,
    input  wire B1,
    output wire Y2,
    input  wire A2,
    input  wire B2,
    input  wire A3,
    input  wire B3,
    output wire Y3,
    input  wire A4,
    input  wire B4,
    output wire Y4
);
    hc_dly #(4, TPD) u_d (
        .a({~(A4 | B4), ~(A3 | B3), ~(A2 | B2), ~(A1 | B1)}),
        .y({Y4, Y3, Y2, Y1}));
    /*verilator no_inline_module*/
endmodule

// hc04 -- 74HC04, hex inverter.
//| part hc04 value 74HC04 symbol 74xx:74HC04
//|  pin  port   ds    type
//|    1  A1     1A    in
//|    2  Y1     1Y    out
//|    3  A2     2A    in
//|    4  Y2     2Y    out
//|    5  A3     3A    in
//|    6  Y3     3Y    out
//|    7  -      GND   power GND
//|    8  Y4     4Y    out
//|    9  A4     4A    in
//|   10  Y5     5Y    out
//|   11  A5     5A    in
//|   12  Y6     6Y    out
//|   13  A6     6A    in
//|   14  -      VCC   power +5V
module hc04 #(parameter integer TPD = 7) (
    input  wire A1,
    output wire Y1,
    input  wire A2,
    output wire Y2,
    input  wire A3,
    output wire Y3,
    output wire Y4,
    input  wire A4,
    output wire Y5,
    input  wire A5,
    output wire Y6,
    input  wire A6
);
    hc_dly #(6, TPD) u_d (
        .a(~{A6, A5, A4, A3, A2, A1}),
        .y({Y6, Y5, Y4, Y3, Y2, Y1}));
    /*verilator no_inline_module*/
endmodule

// hc08 -- 74HC08, quad 2-input AND.  KiCad has no 74HC08; the 74LS08 symbol
// with Value 74HC08 is the same pinout.
//| part hc08 value 74HC08 symbol 74xx:74LS08
//|  pin  port   ds    type
//|    1  A1     1A    in
//|    2  B1     1B    in
//|    3  Y1     1Y    out
//|    4  A2     2A    in
//|    5  B2     2B    in
//|    6  Y2     2Y    out
//|    7  -      GND   power GND
//|    8  Y3     3Y    out
//|    9  A3     3A    in
//|   10  B3     3B    in
//|   11  Y4     4Y    out
//|   12  A4     4A    in
//|   13  B4     4B    in
//|   14  -      VCC   power +5V
module hc08 #(parameter integer TPD = 7) (
    input  wire A1,
    input  wire B1,
    output wire Y1,
    input  wire A2,
    input  wire B2,
    output wire Y2,
    output wire Y3,
    input  wire A3,
    input  wire B3,
    output wire Y4,
    input  wire A4,
    input  wire B4
);
    hc_dly #(4, TPD) u_d (
        .a({A4 & B4, A3 & B3, A2 & B2, A1 & B1}),
        .y({Y4, Y3, Y2, Y1}));
    /*verilator no_inline_module*/
endmodule

// hc11 -- 74HC11, triple 3-input AND.  Section 1's third input and output are
// pins 13 and 12, across the package from its first two.
//| part hc11 value 74HC11 symbol 74xx:74LS11
//|  pin  port   ds    type
//|    1  A1     1A    in
//|    2  B1     1B    in
//|    3  A2     2A    in
//|    4  B2     2B    in
//|    5  C2     2C    in
//|    6  Y2     2Y    out
//|    7  -      GND   power GND
//|    8  Y3     3Y    out
//|    9  A3     3A    in
//|   10  B3     3B    in
//|   11  C3     3C    in
//|   12  Y1     1Y    out
//|   13  C1     1C    in
//|   14  -      VCC   power +5V
module hc11 #(parameter integer TPD = 9) (
    input  wire A1,
    input  wire B1,
    input  wire A2,
    input  wire B2,
    input  wire C2,
    output wire Y2,
    output wire Y3,
    input  wire A3,
    input  wire B3,
    input  wire C3,
    output wire Y1,
    input  wire C1
);
    hc_dly #(3, TPD) u_d (
        .a({A3 & B3 & C3, A2 & B2 & C2, A1 & B1 & C1}),
        .y({Y3, Y2, Y1}));
    /*verilator no_inline_module*/
endmodule

// hc14 -- 74HC14, hex Schmitt inverter.  The hysteresis is not modelled; the
// longer delay is.
//| part hc14 value 74HC14 symbol 74xx:74HC14
//|  pin  port   ds    type
//|    1  A1     1A    in
//|    2  Y1     1Y    out
//|    3  A2     2A    in
//|    4  Y2     2Y    out
//|    5  A3     3A    in
//|    6  Y3     3Y    out
//|    7  -      GND   power GND
//|    8  Y4     4Y    out
//|    9  A4     4A    in
//|   10  Y5     5Y    out
//|   11  A5     5A    in
//|   12  Y6     6Y    out
//|   13  A6     6A    in
//|   14  -      VCC   power +5V
module hc14 #(parameter integer TPD = 12) (
    input  wire A1,
    output wire Y1,
    input  wire A2,
    output wire Y2,
    input  wire A3,
    output wire Y3,
    output wire Y4,
    input  wire A4,
    output wire Y5,
    input  wire A5,
    output wire Y6,
    input  wire A6
);
    hc_dly #(6, TPD) u_d (
        .a(~{A6, A5, A4, A3, A2, A1}),
        .y({Y6, Y5, Y4, Y3, Y2, Y1}));
    /*verilator no_inline_module*/
endmodule

// hc32 -- 74HC32, quad 2-input OR.  74LS32 symbol.
//| part hc32 value 74HC32 symbol 74xx:74LS32
//|  pin  port   ds    type
//|    1  A1     1A    in
//|    2  B1     1B    in
//|    3  Y1     1Y    out
//|    4  A2     2A    in
//|    5  B2     2B    in
//|    6  Y2     2Y    out
//|    7  -      GND   power GND
//|    8  Y3     3Y    out
//|    9  A3     3A    in
//|   10  B3     3B    in
//|   11  Y4     4Y    out
//|   12  A4     4A    in
//|   13  B4     4B    in
//|   14  -      VCC   power +5V
module hc32 #(parameter integer TPD = 8) (
    input  wire A1,
    input  wire B1,
    output wire Y1,
    input  wire A2,
    input  wire B2,
    output wire Y2,
    output wire Y3,
    input  wire A3,
    input  wire B3,
    output wire Y4,
    input  wire A4,
    input  wire B4
);
    hc_dly #(4, TPD) u_d (
        .a({A4 | B4, A3 | B3, A2 | B2, A1 | B1}),
        .y({Y4, Y3, Y2, Y1}));
    /*verilator no_inline_module*/
endmodule

// hc86 -- 74HC86, quad 2-input exclusive-OR.
//| part hc86 value 74HC86 symbol 74xx:74HC86
//|  pin  port   ds    type
//|    1  A1     1A    in
//|    2  B1     1B    in
//|    3  Y1     1Y    out
//|    4  A2     2A    in
//|    5  B2     2B    in
//|    6  Y2     2Y    out
//|    7  -      GND   power GND
//|    8  Y3     3Y    out
//|    9  A3     3A    in
//|   10  B3     3B    in
//|   11  Y4     4Y    out
//|   12  A4     4A    in
//|   13  B4     4B    in
//|   14  -      VCC   power +5V
module hc86 #(parameter integer TPD = 11) (
    input  wire A1,
    input  wire B1,
    output wire Y1,
    input  wire A2,
    input  wire B2,
    output wire Y2,
    output wire Y3,
    input  wire A3,
    input  wire B3,
    output wire Y4,
    input  wire A4,
    input  wire B4
);
    hc_dly #(4, TPD) u_d (
        .a({A4 ^ B4, A3 ^ B3, A2 ^ B2, A1 ^ B1}),
        .y({Y4, Y3, Y2, Y1}));
    /*verilator no_inline_module*/
endmodule

// hc4002 -- 74HC4002, dual 4-input NOR.  The port circuit's BUSY and /CLR
// (inv.md 4.2).  KiCad has only the CMOS 4002, whose supply pins are named
// VSS and VDD; the pins are the same.
//| part hc4002 value 74HC4002 symbol 4xxx:4002
//|  pin  port   ds    type
//|    1  Y1     1Y    out
//|    2  A1     1A    in
//|    3  B1     1B    in
//|    4  C1     1C    in
//|    5  D1     1D    in
//|    6  -      NC    nc
//|    7  -      GND   power GND
//|    8  -      NC    nc
//|    9  A2     2A    in
//|   10  B2     2B    in
//|   11  C2     2C    in
//|   12  D2     2D    in
//|   13  Y2     2Y    out
//|   14  -      VCC   power +5V
module hc4002 #(parameter integer TPD = 10) (
    output wire Y1,
    input  wire A1,
    input  wire B1,
    input  wire C1,
    input  wire D1,
    input  wire A2,
    input  wire B2,
    input  wire C2,
    input  wire D2,
    output wire Y2
);
    hc_dly #(2, TPD) u_d (
        .a({~(A2 | B2 | C2 | D2), ~(A1 | B1 | C1 | D1)}),
        .y({Y2, Y1}));
    /*verilator no_inline_module*/
endmodule

// ============================================================================
// BUFFERS AND SWITCHES
// ============================================================================

// hc125 -- 74HC125, quad buffer, tri-state, active-low enable.  KiCad has only
// the 74LS125; same pins.
//| part hc125 value 74HC125 symbol 74xx:74LS125
//|  pin  port   ds    type
//|    1  OE1_n  /1OE  in
//|    2  A1     1A    in
//|    3  Y1     1Y    tri
//|    4  OE2_n  /2OE  in
//|    5  A2     2A    in
//|    6  Y2     2Y    tri
//|    7  -      GND   power GND
//|    8  Y3     3Y    tri
//|    9  A3     3A    in
//|   10  OE3_n  /3OE  in
//|   11  Y4     4Y    tri
//|   12  A4     4A    in
//|   13  OE4_n  /4OE  in
//|   14  -      VCC   power +5V
module hc125 #(parameter integer TPD = 9, parameter integer TEN = 11) (
    input  wire OE1_n,
    input  wire A1,
    output wire Y1,
    output wire Y1_oe,
    input  wire OE2_n,
    input  wire A2,
    output wire Y2,
    output wire Y2_oe,
    output wire Y3,
    output wire Y3_oe,
    input  wire A3,
    input  wire OE3_n,
    output wire Y4,
    output wire Y4_oe,
    input  wire A4,
    input  wire OE4_n
);
    hc_dly #(4, TPD) u_o (.a({A4, A3, A2, A1}), .y({Y4, Y3, Y2, Y1}));
    hc_dly #(4, TEN) u_e (.a(~{OE4_n, OE3_n, OE2_n, OE1_n}),
                          .y({Y4_oe, Y3_oe, Y2_oe, Y1_oe}));
    /*verilator no_inline_module*/
endmodule

// hc244 -- 74HC244, octal buffer, tri-state, two groups of four.  The pinout
// interleaves the groups: 1A0 is pin 2 and its 1Y0 is pin 18.
//| part hc244 value 74HC244 symbol 74xx:74HC244
//|  pin  port   ds    type
//|    1  OE1_n  /1OE  in
//|    2  A0_1   1A0   in
//|    3  Y0_2   2Y0   tri
//|    4  A1_1   1A1   in
//|    5  Y1_2   2Y1   tri
//|    6  A2_1   1A2   in
//|    7  Y2_2   2Y2   tri
//|    8  A3_1   1A3   in
//|    9  Y3_2   2Y3   tri
//|   10  -      GND   power GND
//|   11  A3_2   2A3   in
//|   12  Y3_1   1Y3   tri
//|   13  A2_2   2A2   in
//|   14  Y2_1   1Y2   tri
//|   15  A1_2   2A1   in
//|   16  Y1_1   1Y1   tri
//|   17  A0_2   2A0   in
//|   18  Y0_1   1Y0   tri
//|   19  OE2_n  /2OE  in
//|   20  -      VCC   power +5V
module hc244 #(parameter integer TPD = 9, parameter integer TEN = 12) (
    input  wire OE1_n,
    input  wire A0_1,
    output wire Y0_2,
    output wire Y0_2_oe,
    input  wire A1_1,
    output wire Y1_2,
    output wire Y1_2_oe,
    input  wire A2_1,
    output wire Y2_2,
    output wire Y2_2_oe,
    input  wire A3_1,
    output wire Y3_2,
    output wire Y3_2_oe,
    input  wire A3_2,
    output wire Y3_1,
    output wire Y3_1_oe,
    input  wire A2_2,
    output wire Y2_1,
    output wire Y2_1_oe,
    input  wire A1_2,
    output wire Y1_1,
    output wire Y1_1_oe,
    input  wire A0_2,
    output wire Y0_1,
    output wire Y0_1_oe,
    input  wire OE2_n
);
    hc_dly #(8, TPD) u_o (
        .a({A3_2, A2_2, A1_2, A0_2, A3_1, A2_1, A1_1, A0_1}),
        .y({Y3_2, Y2_2, Y1_2, Y0_2, Y3_1, Y2_1, Y1_1, Y0_1}));
    hc_dly #(8, TEN) u_e (
        .a({{4{~OE2_n}}, {4{~OE1_n}}}),
        .y({Y3_2_oe, Y2_2_oe, Y1_2_oe, Y0_2_oe, Y3_1_oe, Y2_1_oe, Y1_1_oe, Y0_1_oe}));
    /*verilator no_inline_module*/
endmodule

// hc4051 -- 74HC4051, 8-channel analog multiplexer, MODELLED ONE WAY: the
// eight Yn are inputs and the common Z is a tri-state output, open while /E
// is high.  It cannot carry a signal from Z to a Y pin; a design that uses it
// as a demultiplexer needs another model.  VEE is a supply pin and belongs on
// GND for 0-5 V logic.  KiCad's symbol names the Yn pins A0..A7 and Z 'A'.
//| part hc4051 value 74HC4051 symbol 74xx:74HC4051
//|  pin  port   ds    type
//|    1  Y4     Y4    in
//|    2  Y6     Y6    in
//|    3  Z      Z     tri
//|    4  Y7     Y7    in
//|    5  Y5     Y5    in
//|    6  E_n    /E    in
//|    7  -      VEE   power GND
//|    8  -      GND   power GND
//|    9  S2     S2    in
//|   10  S1     S1    in
//|   11  S0     S0    in
//|   12  Y3     Y3    in
//|   13  Y0     Y0    in
//|   14  Y1     Y1    in
//|   15  Y2     Y2    in
//|   16  -      VCC   power +5V
module hc4051 #(parameter integer TPD = 18) (
    input  wire Y4,
    input  wire Y6,
    output wire Z,
    output wire Z_oe,
    input  wire Y7,
    input  wire Y5,
    input  wire E_n,
    input  wire S2,
    input  wire S1,
    input  wire S0,
    input  wire Y3,
    input  wire Y0,
    input  wire Y1,
    input  wire Y2
);
    wire [7:0] y = {Y7, Y6, Y5, Y4, Y3, Y2, Y1, Y0};
    hc_dly #(2, TPD) u_d (.a({~E_n, y[{S2, S1, S0}]}), .y({Z_oe, Z}));
    /*verilator no_inline_module*/
endmodule

// ============================================================================
// DECODERS, SELECTORS, COMPARATORS
// ============================================================================

// hc138 -- 74HC138, 3-to-8 decoder.  Enabled when /E1 and /E2 are low and E3
// is high; then /Yn for n = A is low and the rest high.  KiCad calls the
// enables ~E0, ~E1, E2; the pins are the same.
//| part hc138 value 74HC138 symbol 74xx:74HC138
//|  pin  port   ds    type
//|    1  A0     A0    in
//|    2  A1     A1    in
//|    3  A2     A2    in
//|    4  E1_n   /E1   in
//|    5  E2_n   /E2   in
//|    6  E3     E3    in
//|    7  Y7_n   /Y7   out
//|    8  -      GND   power GND
//|    9  Y6_n   /Y6   out
//|   10  Y5_n   /Y5   out
//|   11  Y4_n   /Y4   out
//|   12  Y3_n   /Y3   out
//|   13  Y2_n   /Y2   out
//|   14  Y1_n   /Y1   out
//|   15  Y0_n   /Y0   out
//|   16  -      VCC   power +5V
module hc138 #(parameter integer TPD = 12) (
    input  wire A0,
    input  wire A1,
    input  wire A2,
    input  wire E1_n,
    input  wire E2_n,
    input  wire E3,
    output wire Y7_n,
    output wire Y6_n,
    output wire Y5_n,
    output wire Y4_n,
    output wire Y3_n,
    output wire Y2_n,
    output wire Y1_n,
    output wire Y0_n
);
    wire       en = ~E1_n & ~E2_n & E3;
    wire [7:0] y  = ~({7'd0, en} << {A2, A1, A0});
    hc_dly #(8, TPD) u_d (
        .a(y),
        .y({Y7_n, Y6_n, Y5_n, Y4_n, Y3_n, Y2_n, Y1_n, Y0_n}));
    /*verilator no_inline_module*/
endmodule

// hc148 -- 74HC148, 8-to-3 priority encoder, everything active low.  /I7 is
// the highest priority.  With /EI high every output is high.  With /EI low
// and no input low, /A = 111, /GS high and /EO low (the cascade to the next
// encoder).  Otherwise /A is the complement of the highest active input's
// number, /GS low and /EO high.  KiCad's symbol names the outputs S0-S2 and
// pin 10 "IO" with a letter O.
//| part hc148 value 74HC148 symbol 74xx:74LS148
//|  pin  port   ds    type
//|    1  I4_n   /I4   in
//|    2  I5_n   /I5   in
//|    3  I6_n   /I6   in
//|    4  I7_n   /I7   in
//|    5  EI_n   /EI   in
//|    6  A2_n   /A2   out
//|    7  A1_n   /A1   out
//|    8  -      GND   power GND
//|    9  A0_n   /A0   out
//|   10  I0_n   /I0   in
//|   11  I1_n   /I1   in
//|   12  I2_n   /I2   in
//|   13  I3_n   /I3   in
//|   14  GS_n   /GS   out
//|   15  EO_n   /EO   out
//|   16  -      VCC   power +5V
module hc148 #(parameter integer TPD = 14) (
    input  wire I4_n,
    input  wire I5_n,
    input  wire I6_n,
    input  wire I7_n,
    input  wire EI_n,
    output wire A2_n,
    output wire A1_n,
    output wire A0_n,
    input  wire I0_n,
    input  wire I1_n,
    input  wire I2_n,
    input  wire I3_n,
    output wire GS_n,
    output wire EO_n
);
    wire [7:0] i   = ~{I7_n, I6_n, I5_n, I4_n, I3_n, I2_n, I1_n, I0_n};
    wire       en  = ~EI_n;
    wire       any = |i;
    wire [2:0] num = i[7] ? 3'd7 : i[6] ? 3'd6 : i[5] ? 3'd5 : i[4] ? 3'd4 :
                     i[3] ? 3'd3 : i[2] ? 3'd2 : i[1] ? 3'd1 : 3'd0;
    wire [2:0] a_n = (en & any) ? ~num : 3'b111;
    hc_dly #(5, TPD) u_d (
        .a({~(en & any), ~(en & ~any), a_n}),
        .y({GS_n, EO_n, A2_n, A1_n, A0_n}));
    /*verilator no_inline_module*/
endmodule

// hc151 -- 74HC151, 8-input multiplexer.  Y = In for n = S while /E is low;
// with /E high, Y = L and /Y = H.  /Y is the pin port.v calls W, "the capture
// clock".  KiCad's 74LS151 names Y and /Y 'Z' and '~Z'.
//| part hc151 value 74HC151 symbol 74xx:74LS151
//|  pin  port   ds    type
//|    1  I3     I3    in
//|    2  I2     I2    in
//|    3  I1     I1    in
//|    4  I0     I0    in
//|    5  Y      Y     out
//|    6  Y_n    /Y    out
//|    7  E_n    /E    in
//|    8  -      GND   power GND
//|    9  S2     S2    in
//|   10  S1     S1    in
//|   11  S0     S0    in
//|   12  I7     I7    in
//|   13  I6     I6    in
//|   14  I5     I5    in
//|   15  I4     I4    in
//|   16  -      VCC   power +5V
module hc151 #(parameter integer TPD = 17) (
    input  wire I3,
    input  wire I2,
    input  wire I1,
    input  wire I0,
    output wire Y,
    output wire Y_n,
    input  wire E_n,
    input  wire S2,
    input  wire S1,
    input  wire S0,
    input  wire I7,
    input  wire I6,
    input  wire I5,
    input  wire I4
);
    wire [7:0] i = {I7, I6, I5, I4, I3, I2, I1, I0};
    wire       y = ~E_n & i[{S2, S1, S0}];
    hc_dly #(2, TPD) u_d (.a({~y, y}), .y({Y_n, Y}));
    /*verilator no_inline_module*/
endmodule

// hc157 -- 74HC157, quad 2-input multiplexer, one select and one enable for
// all four: nY = S ? nI1 : nI0 while /E is low, all low while it is high.
// ONE SELECT PER PACKAGE -- which is why block.v:120's "'157 x4" cannot give
// eight ports eight selects (inv.md 0, finding 4).
//| part hc157 value 74HC157 symbol 74xx:74LS157
//|  pin  port   ds    type
//|    1  S      S     in
//|    2  I0_1   1I0   in
//|    3  I1_1   1I1   in
//|    4  Y1     1Y    out
//|    5  I0_2   2I0   in
//|    6  I1_2   2I1   in
//|    7  Y2     2Y    out
//|    8  -      GND   power GND
//|    9  Y3     3Y    out
//|   10  I1_3   3I1   in
//|   11  I0_3   3I0   in
//|   12  Y4     4Y    out
//|   13  I1_4   4I1   in
//|   14  I0_4   4I0   in
//|   15  E_n    /E    in
//|   16  -      VCC   power +5V
module hc157 #(parameter integer TPD = 14) (
    input  wire S,
    input  wire I0_1,
    input  wire I1_1,
    output wire Y1,
    input  wire I0_2,
    input  wire I1_2,
    output wire Y2,
    output wire Y3,
    input  wire I1_3,
    input  wire I0_3,
    output wire Y4,
    input  wire I1_4,
    input  wire I0_4,
    input  wire E_n
);
    wire [3:0] i0 = {I0_4, I0_3, I0_2, I0_1};
    wire [3:0] i1 = {I1_4, I1_3, I1_2, I1_1};
    hc_dly #(4, TPD) u_d (
        .a({4{~E_n}} & (S ? i1 : i0)),
        .y({Y4, Y3, Y2, Y1}));
    /*verilator no_inline_module*/
endmodule

// hc688 -- 74HC688, 8-bit identity comparator.  /P=Q is low when /E is low
// and P = Q, bit for bit.  KiCad's symbol names Q 'R' and the enable 'G'.
//| part hc688 value 74HC688 symbol 74xx:74HC688
//|  pin  port   ds    type
//|    1  E_n    /E    in
//|    2  P0     P0    in
//|    3  Q0     Q0    in
//|    4  P1     P1    in
//|    5  Q1     Q1    in
//|    6  P2     P2    in
//|    7  Q2     Q2    in
//|    8  P3     P3    in
//|    9  Q3     Q3    in
//|   10  -      GND   power GND
//|   11  P4     P4    in
//|   12  Q4     Q4    in
//|   13  P5     P5    in
//|   14  Q5     Q5    in
//|   15  P6     P6    in
//|   16  Q6     Q6    in
//|   17  P7     P7    in
//|   18  Q7     Q7    in
//|   19  P_EQ_Q_n  /P=Q  out
//|   20  -      VCC   power +5V
module hc688 #(parameter integer TPD = 16) (
    input  wire E_n,
    input  wire P0,
    input  wire Q0,
    input  wire P1,
    input  wire Q1,
    input  wire P2,
    input  wire Q2,
    input  wire P3,
    input  wire Q3,
    input  wire P4,
    input  wire Q4,
    input  wire P5,
    input  wire Q5,
    input  wire P6,
    input  wire Q6,
    input  wire P7,
    input  wire Q7,
    output wire P_EQ_Q_n
);
    wire [7:0] p = {P7, P6, P5, P4, P3, P2, P1, P0};
    wire [7:0] q = {Q7, Q6, Q5, Q4, Q3, Q2, Q1, Q0};
    hc_dly #(1, TPD) u_d (.a(~(~E_n & (p == q))), .y(P_EQ_Q_n));
    /*verilator no_inline_module*/
endmodule

// ============================================================================
// FLIP-FLOPS, REGISTERS, LATCHES
// ============================================================================

// hc_dff_sr -- one half of a '74, and the part of this file that most needs
// its reasons written down.  The datasheet's table:
//
//      /SD  /RD   CP    Q   /Q
//       L    H    x     H    L
//       H    L    x     L    H
//       L    L    x     H    H     (not stable once both go high together)
//       H    H    ^     D   /D
//
// Written as the usual 'always @(posedge CP or negedge SD or negedge RD)' it
// gets one row wrong: /SD low, then /RD low, then /RD high while /SD is still
// low must leave Q high, but the usual form's state was last written by /RD.
// So the clock and the asynchronous inputs each keep their own state and the
// time they last wrote it, and the later one is the flip-flop.  Every edge
// of /SD or /RD restamps the asynchronous side, releases included, so a
// clock that arrived while an asynchronous input held the part never takes
// effect.  A clock edge in the same time step as a release loses to it:
// that is a recovery-time violation on the real part, and either answer is
// the part's.
module hc_dff_sr #(
    parameter integer TPD = 14,
    parameter integer TSU = 15,
    parameter integer TH  = 3
)(
    input  wire CP,
    input  wire D,
    input  wire SD_n,
    input  wire RD_n,
    output wire Q,
    output wire Q_n
);
    reg        s_clk, s_asy;
    reg [63:0] t_clk, t_asy;
    initial begin t_clk = 64'd0; t_asy = 64'd0; end

    always @(posedge CP) begin s_clk <= D; t_clk <= $time; end

    always @(posedge SD_n or negedge SD_n or posedge RD_n or negedge RD_n) begin
        t_asy <= $time;
        if (SD_n === 1'b0 && RD_n === 1'b0) s_asy <= 1'bx;   // whichever lets go last decides
        else if (SD_n === 1'b0)             s_asy <= 1'b1;
        else if (RD_n === 1'b0)             s_asy <= 1'b0;
        // both high: a release, and s_asy keeps what the last one held left
    end

    wire st = (t_asy >= t_clk) ? s_asy : s_clk;
    hc_dly #(2, TPD) u_d (
        .a({~RD_n | (SD_n & ~st), ~SD_n | (RD_n & st)}),
        .y({Q_n, Q}));
    hc_tchk #(1, TSU, TH) u_t (.CP(CP), .EN(SD_n & RD_n), .D(D));
    /*verilator no_inline_module*/
endmodule

// hc74 -- 74HC74, dual D flip-flop, positive edge, asynchronous /SD and /RD.
//| part hc74 value 74HC74 symbol 74xx:74HC74
//|  pin  port   ds    type
//|    1  RD1_n  /1RD  in
//|    2  D1     1D    in
//|    3  CP1    1CP   in
//|    4  SD1_n  /1SD  in
//|    5  Q1     1Q    out
//|    6  Q1_n   /1Q   out
//|    7  -      GND   power GND
//|    8  Q2_n   /2Q   out
//|    9  Q2     2Q    out
//|   10  SD2_n  /2SD  in
//|   11  CP2    2CP   in
//|   12  D2     2D    in
//|   13  RD2_n  /2RD  in
//|   14  -      VCC   power +5V
module hc74 #(
    parameter integer TPD = 14,
    parameter integer TSU = 15,
    parameter integer TH  = 3
)(
    input  wire RD1_n,
    input  wire D1,
    input  wire CP1,
    input  wire SD1_n,
    output wire Q1,
    output wire Q1_n,
    output wire Q2_n,
    output wire Q2,
    input  wire SD2_n,
    input  wire CP2,
    input  wire D2,
    input  wire RD2_n
);
    hc_dff_sr #(TPD, TSU, TH) u1 (.CP(CP1), .D(D1), .SD_n(SD1_n), .RD_n(RD1_n), .Q(Q1), .Q_n(Q1_n));
    hc_dff_sr #(TPD, TSU, TH) u2 (.CP(CP2), .D(D2), .SD_n(SD2_n), .RD_n(RD2_n), .Q(Q2), .Q_n(Q2_n));
    /*verilator no_inline_module*/
endmodule

// hc164 -- 74HC164, 8-bit serial-in parallel-out shift register.  On CP's
// rise Q0 takes DSA.DSB and Qn takes Qn-1; /MR low clears it, asynchronously.
// No output latch: the outputs ripple while a word shifts in (block.v 89).
//| part hc164 value 74HC164 symbol 74xx:74HC164
//|  pin  port   ds    type
//|    1  DSA    DSA   in
//|    2  DSB    DSB   in
//|    3  Q0     Q0    out
//|    4  Q1     Q1    out
//|    5  Q2     Q2    out
//|    6  Q3     Q3    out
//|    7  -      GND   power GND
//|    8  CP     CP    in
//|    9  MR_n   /MR   in
//|   10  Q4     Q4    out
//|   11  Q5     Q5    out
//|   12  Q6     Q6    out
//|   13  Q7     Q7    out
//|   14  -      VCC   power +5V
module hc164 #(
    parameter integer TPD = 13,
    parameter integer TSU = 12,
    parameter integer TH  = 3
)(
    input  wire DSA,
    input  wire DSB,
    output wire Q0,
    output wire Q1,
    output wire Q2,
    output wire Q3,
    input  wire CP,
    input  wire MR_n,
    output wire Q4,
    output wire Q5,
    output wire Q6,
    output wire Q7
);
    reg [7:0] st;
    always @(posedge CP or negedge MR_n)
        if (!MR_n) st <= 8'd0;
        else       st <= {st[6:0], DSA & DSB};
    hc_dly #(8, TPD) u_d (.a(st), .y({Q7, Q6, Q5, Q4, Q3, Q2, Q1, Q0}));
    hc_tchk #(2, TSU, TH) u_t (.CP(CP), .EN(MR_n), .D({DSB, DSA}));
    /*verilator no_inline_module*/
endmodule

// hc175 -- 74HC175, quad D flip-flop with /MR, true and complement outputs.
// The block's /WS latch: SCAN[2:0] clocked at CELL_A (block.v 261-270).
//| part hc175 value 74HC175 symbol 74xx:74LS175
//|  pin  port   ds    type
//|    1  MR_n   /MR   in
//|    2  Q0     Q0    out
//|    3  Q0_n   /Q0   out
//|    4  D0     D0    in
//|    5  D1     D1    in
//|    6  Q1_n   /Q1   out
//|    7  Q1     Q1    out
//|    8  -      GND   power GND
//|    9  CP     CP    in
//|   10  Q2     Q2    out
//|   11  Q2_n   /Q2   out
//|   12  D2     D2    in
//|   13  D3     D3    in
//|   14  Q3_n   /Q3   out
//|   15  Q3     Q3    out
//|   16  -      VCC   power +5V
module hc175 #(
    parameter integer TPD = 14,
    parameter integer TSU = 12,
    parameter integer TH  = 3
)(
    input  wire MR_n,
    output wire Q0,
    output wire Q0_n,
    input  wire D0,
    input  wire D1,
    output wire Q1_n,
    output wire Q1,
    input  wire CP,
    output wire Q2,
    output wire Q2_n,
    input  wire D2,
    input  wire D3,
    output wire Q3_n,
    output wire Q3
);
    wire [3:0] d = {D3, D2, D1, D0};
    reg  [3:0] st;
    always @(posedge CP or negedge MR_n)
        if (!MR_n) st <= 4'd0;
        else       st <= d;
    hc_dly #(8, TPD) u_d (
        .a({~st, st}),
        .y({Q3_n, Q2_n, Q1_n, Q0_n, Q3, Q2, Q1, Q0}));
    hc_tchk #(4, TSU, TH) u_t (.CP(CP), .EN(MR_n), .D(d));
    /*verilator no_inline_module*/
endmodule

// hc273 -- 74HC273, octal D flip-flop with /MR.  The port's crosspoint latch
// (port.v 70-73): clocked by its /WR lane, cleared by the release.
//| part hc273 value 74HC273 symbol 74xx:74HC273
//|  pin  port   ds    type
//|    1  MR_n   /MR   in
//|    2  Q0     Q0    out
//|    3  D0     D0    in
//|    4  D1     D1    in
//|    5  Q1     Q1    out
//|    6  Q2     Q2    out
//|    7  D2     D2    in
//|    8  D3     D3    in
//|    9  Q3     Q3    out
//|   10  -      GND   power GND
//|   11  CP     CP    in
//|   12  Q4     Q4    out
//|   13  D4     D4    in
//|   14  D5     D5    in
//|   15  Q5     Q5    out
//|   16  Q6     Q6    out
//|   17  D6     D6    in
//|   18  D7     D7    in
//|   19  Q7     Q7    out
//|   20  -      VCC   power +5V
module hc273 #(
    parameter integer TPD = 15,
    parameter integer TSU = 12,
    parameter integer TH  = 3
)(
    input  wire MR_n,
    output wire Q0,
    input  wire D0,
    input  wire D1,
    output wire Q1,
    output wire Q2,
    input  wire D2,
    input  wire D3,
    output wire Q3,
    input  wire CP,
    output wire Q4,
    input  wire D4,
    input  wire D5,
    output wire Q5,
    output wire Q6,
    input  wire D6,
    input  wire D7,
    output wire Q7
);
    wire [7:0] d = {D7, D6, D5, D4, D3, D2, D1, D0};
    reg  [7:0] st;
    always @(posedge CP or negedge MR_n)
        if (!MR_n) st <= 8'd0;
        else       st <= d;
    hc_dly #(8, TPD) u_d (.a(st), .y({Q7, Q6, Q5, Q4, Q3, Q2, Q1, Q0}));
    hc_tchk #(8, TSU, TH) u_t (.CP(CP), .EN(MR_n), .D(d));
    /*verilator no_inline_module*/
endmodule

// hc595 -- 74HC595, 8-bit shift register with a storage register behind it:
// serial in, tri-state parallel out, serial out.  On SHCP's rise the shift
// register takes DS at bit 0 and bit n-1 at bit n; /MR low clears the SHIFT
// register, asynchronously, and never the storage register.  On STCP's rise
// the storage register takes the shift register, and Qn shows it while /OE
// is low.  Q7S is the shift register's bit 7, a totem pole that /OE does not
// touch: the cascade into the next '595's DS.  With the two clocks tied the
// storage register is one clock behind, as the datasheet says; here both
// edges read the old shift register, so it is.  Two watches: DS against
// SHCP while /MR is high, and the shift register against STCP -- the
// SHCP-to-STCP set-up, TSU_ST -- with no hold, since tied clocks are legal.
// KiCad's symbol uses TI's names: QA..QH, QH', /SRCLR, SRCLK, RCLK, SER.
//| part hc595 value 74HC595 symbol 74xx:74HC595
//|  pin  port   ds    type
//|    1  Q1     Q1    tri
//|    2  Q2     Q2    tri
//|    3  Q3     Q3    tri
//|    4  Q4     Q4    tri
//|    5  Q5     Q5    tri
//|    6  Q6     Q6    tri
//|    7  Q7     Q7    tri
//|    8  -      GND   power GND
//|    9  Q7S    Q7S   out
//|   10  MR_n   /MR   in
//|   11  SHCP   SHCP  in
//|   12  STCP   STCP  in
//|   13  OE_n   /OE   in
//|   14  DS     DS    in
//|   15  Q0     Q0    tri
//|   16  -      VCC   power +5V
module hc595 #(
    parameter integer TPD    = 16,
    parameter integer TEN    = 15,
    parameter integer TSU    = 12,
    parameter integer TH     = 3,
    parameter integer TSU_ST = 15
)(
    output wire Q1,
    output wire Q1_oe,
    output wire Q2,
    output wire Q2_oe,
    output wire Q3,
    output wire Q3_oe,
    output wire Q4,
    output wire Q4_oe,
    output wire Q5,
    output wire Q5_oe,
    output wire Q6,
    output wire Q6_oe,
    output wire Q7,
    output wire Q7_oe,
    output wire Q7S,
    input  wire MR_n,
    input  wire SHCP,
    input  wire STCP,
    input  wire OE_n,
    input  wire DS,
    output wire Q0,
    output wire Q0_oe
);
    reg [7:0] sr, st;
    always @(posedge SHCP or negedge MR_n)
        if (!MR_n) sr <= 8'd0;
        else       sr <= {sr[6:0], DS};
    always @(posedge STCP) st <= sr;
    hc_dly #(9, TPD) u_d (
        .a({sr[7], st}),
        .y({Q7S, Q7, Q6, Q5, Q4, Q3, Q2, Q1, Q0}));
    hc_dly #(8, TEN) u_e (
        .a({8{~OE_n}}),
        .y({Q7_oe, Q6_oe, Q5_oe, Q4_oe, Q3_oe, Q2_oe, Q1_oe, Q0_oe}));
    hc_tchk #(1, TSU, TH)   u_t  (.CP(SHCP), .EN(MR_n), .D(DS));
    hc_tchk #(8, TSU_ST, 0) u_ts (.CP(STCP), .EN(1'b1), .D(sr));
    /*verilator no_inline_module*/
endmodule

// ============================================================================
// DISCRETES
// ============================================================================

// fet_2n7002 -- 2N7002 (SOT-23) as an open drain.  pd = 1 is the FET on,
// pulling its drain net low.  The source is a supply pin and must be on GND;
// a FET with its source anywhere else is not an open drain and the generator
// must refuse it.  TPD is the switch alone -- the pull-up's RC on the drain
// net is the net's, not the part's.  Pins by NUMBER differ from the 2N7000's:
// G, S, D = 1, 2, 3 here.
//| part fet_2n7002 value 2N7002 symbol Transistor_FET:2N7002
//|  pin  port   ds    type
//|    1  G      G     in
//|    2  -      S     power GND
//|    3  pd     D     od
module fet_2n7002 #(parameter integer TPD = 5) (
    input  wire G,
    output wire pd
);
    hc_dly #(1, TPD) u_d (.a(G), .y(pd));
    /*verilator no_inline_module*/
endmodule

// fet_2n7000 -- 2N7000 (TO-92), the same switch in the package synth.md 5
// prefers on the 4-layer header, where SOT-23 GND pins failed to escape.
// S, G, D = 1, 2, 3.
//| part fet_2n7000 value 2N7000 symbol Transistor_FET:2N7000
//|  pin  port   ds    type
//|    1  -      S     power GND
//|    2  G      G     in
//|    3  pd     D     od
module fet_2n7000 #(parameter integer TPD = 5) (
    input  wire G,
    output wire pd
);
    hc_dly #(1, TPD) u_d (.a(G), .y(pd));
    /*verilator no_inline_module*/
endmodule

// ============================================================================
// MACRO CELLS: the RC networks
// ============================================================================
//
// These replace a cluster of parts -- resistors, capacitors, a diode and the
// '14 sections that square the result -- because a digital simulator has no
// capacitor.  The generator substitutes one by sheet or by a field on the
// symbol; their ports are sheet pins, not package pins, and their tables
// have '-' for the pin.  Ports marked 'sim' are simulation-only nets that no
// board has: the master clock, the reset, the 1 kHz tick.

// rc_det -- the supervision detector: a diode and two resistors into an RC,
// squared by a '14 (fabric.md 5.2; port.v 29-35, 134-136, 175-188).  The RC
// is fast up and slow down.  THIS IS port.v's DETECTOR, LINE FOR LINE: on
// each clk that tick_1k is high, a sample that agrees with the output clears
// the count; one that disagrees counts, and the T-th consecutive disagreeing
// sample -- T_ARM when the input is high, T_REL when it is low -- turns the
// output over and clears the count.  So an input that goes back before T
// restarts the climb from zero, as port.v does.  rst_n zeroes both, as
// port.v's does; the real RC has no reset, and a netlist that wants the
// board's behaviour ties it high.  OUT and OUT_n come out through the '14's
// delay.  tb/tb_macro.v runs it against port.v itself.
//| macro rc_det
//|  pin  port     ds       type
//|    -  clk      clk      in    sim
//|    -  rst_n    rst_n    in    sim
//|    -  tick_1k  tick_1k  in    sim
//|    -  IN       IN       in
//|    -  OUT      OUT      out
//|    -  OUT_n    OUT_n    out
module rc_det #(
    parameter [8:0]   T_ARM = 9'd16,    // ms up: port.v's T_ARM
    parameter [8:0]   T_REL = 9'd256,   // ms down: port.v's T_REL
    parameter integer TPD   = 12        // the '14 behind the RC
)(
    input  wire clk,
    input  wire rst_n,
    input  wire tick_1k,
    input  wire IN,
    output wire OUT,
    output wire OUT_n
);
    reg        f;
    reg  [8:0] n;
    wire [8:0] thr = IN ? T_ARM : T_REL;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            f <= 1'b0; n <= 9'd0;
        end else if (tick_1k) begin
            if (IN == f) n <= 9'd0;
            else if (n >= thr - 9'd1) begin
                n <= 9'd0; f <= IN;
            end else n <= n + 1'b1;
        end

    hc_dly #(2, TPD) u_d (.a({~f, f}), .y({OUT_n, OUT}));
    /*verilator no_inline_module*/
endmodule

// cr_rel -- the release: a detector's fall, differentiated by a CR and squared
// by a '14, into the '273's asynchronous /MR (fabric.md 5.2; port.v 136,
// 190-194).  REL is high, and REL_n low, for one pulse per falling edge of IN.
// A rise makes no pulse.
//
//   W_NS > 0   the pulse is W_NS long: the CR's time to the '14's threshold,
//              which the sheet's R and C set
//   W_NS = 0   the pulse lasts to the next rise of clk -- port.v's rel, the
//              registered one-clk pulse, which a write in the same clk loses
//              to (for the lockstep comparison against the RTL)
//
// RISE = 1 pulses on a rise of IN instead: the port card's CR hangs off the
// '14's OUTPUT, /FM or /FE, whose rise is the detector's fall.
//
// A second edge inside a pulse stretches it.  Only a 1-to-0 (or 0-to-1) edge
// counts, so the unknown-to-known settle at power-on makes no pulse.
//| macro cr_rel
//|  pin  port     ds       type
//|    -  clk      clk      in    sim
//|    -  IN       IN       in
//|    -  REL      REL      out
//|    -  REL_n    REL_n    out
module cr_rel #(
    parameter integer W_NS = 0,
    parameter integer RISE = 0,
    parameter integer TPD  = 12
)(
    input  wire clk,
    input  wire IN,
    output wire REL,
    output wire REL_n
);
    integer n_fall, n_done;
    reg     was;
    initial begin n_fall = 0; n_done = 0; end

    always @(posedge IN or negedge IN) begin
        if (IN === (RISE != 0 ? 1'b1 : 1'b0) && was === (RISE != 0 ? 1'b0 : 1'b1)) n_fall <= n_fall + 1;
        was <= IN;
    end

    generate if (W_NS > 0) begin : timed
        always @(n_fall) n_done <= #(W_NS) n_fall;
    end else begin : clocked
        always @(posedge clk) n_done <= n_fall;
    end endgenerate

    wire p = (n_fall != n_done);
    hc_dly #(2, TPD) u_d (.a({~p, p}), .y({REL_n, REL}));
    /*verilator no_inline_module*/
endmodule

// rc_filt -- an RC low-pass as a '14 input sees it: Y rises T_UP after A has
// risen and stayed high, and falls T_DN after A has fallen and stayed low; a
// shorter excursion never reaches the threshold.  INIT is the capacitor at
// power-on -- 0, discharged -- so the node starts low whatever A does and
// rises T_UP after power-on if A is high.  That is the power-on reset, and it
// is the /RESET filter on the block header (block-stack.md 2.1; port.v 38: "also
// /RESET, filtered at the block"): the bus's /RESET through R to C, and the
// '14 after it a real part in the netlist.  Continuous charging and partial
// charge are not modelled; the sheet's R and C set T_UP and T_DN.
//| macro rc_filt
//|  pin  port     ds       type
//|    -  A        A        in
//|    -  Y        Y        out
module rc_filt #(
    parameter integer T_UP = 10000,
    parameter integer T_DN = 10000,
    parameter integer INIT = 0
)(
    input  wire A,
    output wire Y
);
    hc_dly1 #(.DR(T_UP), .DF(T_DN), .INIT(INIT)) u (.a(A), .y(Y));
    /*verilator no_inline_module*/
endmodule

`default_nettype wire

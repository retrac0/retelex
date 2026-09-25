// pulse_reg -- one register: register.md 4's pulse collector.
//
// It reads its caller's hook ITSELF, through its own probe on /HA -- the
// marker does not hand it digits and does not hand it a hook.  The store is
// four digits deep so that a key and an own code can be consumed by
// restarting it and `e b h s` still land in slots 0 to 3 (rtl.md).
//
// Everything on the marker's side of this module is a LEVEL held until the
// other side has seen it.  rtl.md 1: an event on a wire is a race.
//
// One of these lives inside the mini-marker; in the maximal build the same
// module is a pool member on its own card, reached over common-control.md
// 2.1's ribbon, which is these same wires.
`timescale 1ns/1ps
`include "exch.vh"

module pulse_reg #(
    parameter [8:0]  HIT   = 9'd8,
    parameter [8:0]  ID    = 9'd128,
    parameter [8:0]  CLR   = 9'd256,
    // ms attached with no digit going in -- from seizure OR from the last digit
    // (register.md 6, marker.md 4).  10 s is what every document and exch.py's
    // T_NODIGIT say; the RTL carried 12000 with nothing naming it.
    parameter [15:0] NODIG = 16'd10000
)(
    input                   clk,
    input                   rst_n,

    // ---- cable A -----------------------------------------------------------
    input      [2:0]        slotq,
    input                   cap_stb,
    input                   frame_stb,
    input      [`SCANW-1:0] scan,
    input                   ha_n,          // M
    input                   hb_n,          // BUSY, the same bit-time
    input                   tick_1k,

    // ---- from the marker ---------------------------------------------------
    input                   attach,        // one tick: seize me for this caller
    input      [`PW-1:0]    attach_port,
    input                   release_it,    // clear the store and go free
    input                   restart,       // begin the store again, caller unchanged

    // ---- to the marker, all levels -----------------------------------------
    output reg              busy,
    output reg [`PW-1:0]    port,          // the caller
    output reg [2:0]        ndig,          // how many digits are in
    output reg [15:0]       digits,        // four pulse counts, as counted
    output reg              gone,          // CLR: the caller went away
    output reg              nodig,         // the no-digit timeout
    output                  brk,           // a break just counted; the origin guard reads it
    output                  counting,      // a digit is part-collected
    output                  hook           // the caller's M, as the probe has it
);
    // ---- the probe: two '151 and a flip-flop in the old tree, one '688 and
    // half a '74 now.  It watches one port, once every 1 ms, taking that
    // port's M off /HA and its BUSY off /HB in the one bit-time.
    wire p_m, p_busy, p_fresh;
    wire [`PW-1:0] p_port;
    probe u_probe (
        .clk(clk), .rst_n(rst_n), .slotq(slotq), .cap_stb(cap_stb),
        .frame_stb(frame_stb), .scan(scan), .ha_n(ha_n), .hb_n(hb_n),
        .port(port),
        .m(p_m), .busy(p_busy), .port_q(p_port), .fresh(p_fresh));

    assign hook = p_m;

    wire [3:0] cnt;
    wire       dig_stb, clr_stb;
    pulse_rx #(.HIT(HIT), .ID(ID), .CLR(CLR)) u_rx (
        .clk(clk), .rst_n(rst_n), .tick_1k(tick_1k),
        .arm(busy), .m(p_m),
        .cnt(cnt), .dig_stb(dig_stb), .clear(clr_stb),
        .counting(counting), .brk_stb(brk));

    reg [15:0] nd_t;      // the no-digit timer, in milliseconds

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; port <= {`PW{1'b0}}; ndig <= 3'd0; digits <= 16'd0;
            gone <= 1'b0; nodig <= 1'b0; nd_t <= 16'd0;
        end else begin
            if (attach) begin
                busy   <= 1'b1;
                port   <= attach_port;
                ndig   <= 3'd0;
                digits <= 16'd0;     // empty when idle, and empty when handed over
                gone   <= 1'b0;
                nodig  <= 1'b0;
                nd_t   <= 16'd0;
            end else if (release_it) begin
                busy   <= 1'b0;
                ndig   <= 3'd0;
                digits <= 16'd0;
                gone   <= 1'b0;
                nodig  <= 1'b0;
                nd_t   <= 16'd0;
            end else if (busy) begin
                // restart: the key or an own code has been consumed, so the
                // digits after it land in slots 0 to 3 like a local number.
                if (restart) begin
                    ndig   <= 3'd0;
                    digits <= 16'd0;
                    nd_t   <= 16'd0;
                end else if (dig_stb) begin
                    if (ndig != 3'd4) begin
                        digits[ndig*4 +: 4] <= cnt;
                        ndig                <= ndig + 3'd1;
                    end
                    nd_t <= 16'd0;
                end

                if (clr_stb) gone <= 1'b1;

                // The no-digit timeout, held once it fires.  register.md 6 calls
                // `gone` "CLR, OR A PARTIAL-DIAL TIMEOUT", and marker.md 4 says the
                // timer "runs from the last digit as well as from seizure" -- so it
                // runs whenever the register is attached and no digit is part way
                // in, NOT only while the store is empty.  Gating it on ndig == 0
                // froze it at the first digit and a caller who dialled one digit
                // and stopped held the exchange's only register until he hung up.
                // The two branches above already clear nd_t; say so here rather
                // than lean on dig_stb and tick_1k never coinciding, since both
                // assign nd_t in this one block and the later write would win.
                if (tick_1k && !counting && !nodig && !restart && !dig_stb) begin
                    if (nd_t == NODIG - 16'd1) nodig <= 1'b1;
                    else                       nd_t  <= nd_t + 16'd1;
                end
            end
        end
    end

    // the probe's own BUSY and port_q are not this module's business; it
    // watches one port and only wants its hook.
    wire _unused = &{1'b0, p_busy, p_fresh, p_port, 1'b0};
endmodule

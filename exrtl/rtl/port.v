// port -- one of the 64 ports: the crosspoint (exch-fabric.md 3.2) and the
// supervision (3.5).  Five packages and three and a quarter in 74HC.
//
// The crosspoint is a '273 holding [ highway | slot ], two '151s to pick a
// highway, a third to pick the moment, and a '74 pair to keep the answer.  The
// supervision is two RC-and-'14 detectors and a handful of gates, and it is the
// whole of "nobody is in charge of a call": the port rings itself, sends its own
// ringback and clears its own latch.
`timescale 1ns/1ps
`include "exch_defs.vh"

module port #(
    parameter        FITTED = 1'b1,   // a port circuit is populated here
    parameter        RINGS  = 1'b1,   // the card's /ANS left open: a phone, so it rings
    // The two release detectors, in frames at 64 kHz: up in 16 ms, down in 256.
    parameter integer T_RISE = 1024,
    parameter integer T_FALL = 16384
)(
    input             clk,
    input             rst_n,

    // from the clock card
    input      [2:0]  slotq,
    input             cap_stb,
    input             frame_stb,
    input             ring_cad_n,

    // the sixteen highways, from every block
    input      [7:0]  hc,
    input      [7:0]  ha,

    // the card behind this port.  C_TX does not come in here: the ringback
    // substitution ahead of the commutator is the block's '157 (exch-fabric.md
    // 3.1), so a port's only card input is M.
    input             a_tx,          // M: the card's hook
    output            c_rx,
    output            a_rx,

    // to this block's commutators
    output            rb,            // being rung: send RBT instead of C_TX ('157 in the block)
    output            a_hw,
    output            busy_hw,

    // the marker's write, decoded by the block
    input             wr,
    input      [5:0]  src,
    input             bsy_in,
    input             clm_in
);
    // ---- the '273: the crosspoint, and the whole of the connection ----------
    reg [5:0] addr;      // [5:3] highway, [2:0] slot -- the port number as dialled
    reg       busy, claim;

    // ---- the '151s and the '74 pair ----------------------------------------
    wire c_sel = hc[addr[5:3]];                       // highway select, C
    wire a_sel = ha[addr[5:3]];                       // highway select, A
    wire w     = cap_stb && (slotq == addr[2:0]);     // slot select: W, at mid-cell
    reg  c_cap, a_cap;

    assign c_rx = c_cap;
    wire   e    = a_cap;                              // E: the other party's M, come back

    // ---- 3.5, in gates ------------------------------------------------------
    wire m  = a_tx;
    reg  fm, fe;                                      // the two detectors
    reg  fm_d, fe_d;
    wire release_now = (fm_d && !fm) || (fe_d && !fe);   // the fall of either, squared up

    wire on = RINGS && !m && !fm;    // an on-hook port that rings -- and not one that
                                     // hung up a moment ago
    assign rb      = on && e;                             // RB = ON . E
    assign a_rx    = e && !(on && ring_cad_n);            // ring in cadence while ON, else E
    assign busy_hw = busy || fe || (fm && !m);            // busy while either is still timing out
    assign a_hw    = a_tx || claim;   // FIXME exch-fabric.md 3.1 writes this "A out = E + CLAIM".
                                      // Harmless either way while CLAIM is never written, which is
                                      // every block but a trunk block.  See the note in the README.

    // ---- the detectors: fast up, slow down, counted in frames ---------------
    reg [14:0] cm, ce;
    wire [14:0] thr_m = m ? T_RISE[14:0] : T_FALL[14:0];
    wire [14:0] thr_e = e ? T_RISE[14:0] : T_FALL[14:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr <= 6'd0; busy <= 1'b0; claim <= 1'b0;
            c_cap <= 1'b0; a_cap <= 1'b0;
            fm <= 1'b0; fe <= 1'b0; fm_d <= 1'b0; fe_d <= 1'b0;
            cm <= 15'd0; ce <= 15'd0;
        end else if (FITTED) begin
            if (w) begin c_cap <= c_sel; a_cap <= a_sel; end

            if (frame_stb) begin
                fm_d <= fm; fe_d <= fe;
                if (m == fm) cm <= 15'd0;
                else if (cm >= thr_m - 1) begin cm <= 15'd0; fm <= m; end
                else cm <= cm + 1'b1;
                if (e == fe) ce <= 15'd0;
                else if (ce >= thr_e - 1) begin ce <= 15'd0; fe <= e; end
                else ce <= ce + 1'b1;
            end

            // the marker writes; the port clears itself.  A release beats a write.
            if (release_now) begin addr <= 6'd0; busy <= 1'b0; claim <= 1'b0; end
            else if (wr)     begin addr <= src;  busy <= bsy_in; claim <= clm_in; end
        end
    end
endmodule

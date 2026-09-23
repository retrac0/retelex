// su1 -- mk1 CVSD subscriber unit digital, su-1.md.
//
// The set on the simplified four-wire subscriber interface (line_card.v):
// m / tx / rx / e.  The dialer itself is su_dial.v, shared with su_d.v.
//
// Loop-timed, no crystal (su-1.md §5).  The only timebase is bit_stb, the
// recovered 64 kHz strobe off the §9.4 receiver; TICK and the ~1 Hz line LED
// are that divided.  A dead pair is no strobe, so the dialer stops and the
// LED goes dark -- the same "no downstream, no clock" fact that rejected
// carrier-off signalling (subscriber-line.md §6).
//
// On the line (subscriber-line.md §2, su-1.md §2):
//
//   TX = ON-HOOK or dial break ? 1100 : ( off-normal ? 1010 : CVSD )
//
// 1100 is the bit clock / 4 and is what the exchange's Q^Q[n-2] detector
// counts; 1010 is the codec's idle, which is what "mute while off normal"
// puts under every make so the break shortening is one fixed number
// (register.md §1.1).  m is the simplified A bit the RTL exchange reads,
// and it drops on a break the way phone.v and pulse_gen do.
`timescale 1ns/1ps

module su1 #(
    parameter integer PPS       = 10,
    parameter integer BREAK_PCT = 60,
    parameter integer T_OH      = 500,    // seize delay, ms of TICK
    parameter integer T_ID      = 700,    // interdigit pause
    parameter integer DEBOUNCE  = 20,
    parameter integer TICK_DIV  = 64,     // bit_stb per TICK: 64 kHz / 64 = 1 kHz
    parameter integer LED_DIV   = 65536   // bit_stb per LED period (§5)
)(
    input            clk,
    input            rst_n,
    input            bit_stb,             // recovered 64 kHz bit strobe (§5)
    input            carrier,             // §9.4 carrier detect; 0 = dead pair

    input            hook_sw,             // 1 = off-hook
    input     [15:0] key_n,               // Autovon pad, active low
                                          // [0]=1 .. [8]=9, [9]=0, [10]=*,
                                          // [11]=#, [12]=FO, [13]=F, [14]=I, [15]=P

    input            spk_sw,              // 1 = SPEAKER, 0 = HANDSET  (§3.2)
    input            ptt_mode,            // 1 = PTT, 0 = LIVE
    input            ptt,                 // momentary, PTT mode only

    input            rx,                  // C from the exchange (simplified)
    input            e,                   // ring cadence while on-hook
    input            cv_bit,              // encoder bit when talking

    output           m,                   // off-hook with dial breaks
    output           tx,                  // toward the exchange
    output           ring,                // ringer: RING . ON-HOOK
    output           mute,                // encoder silence (off-normal)
    output           bit_dec,             // to decoder: 1010 while ringing
    output           off_normal,          // dial train in progress

    output           mic_en,              // mic gate open (§3.2)
    output           ear_mute,            // handset ear muted
    output           spk_en,              // loudspeaker amp enabled
    output           led,                 // ~1 Hz line LED; dark with no carrier
    output           tick_1k              // the dialer's TICK, for the bench
);
    // ---- the only timebase: the recovered strobe, divided (§5) -----------
    reg [15:0] tdiv;
    reg [15:0] ldiv;
    wire       tick = bit_stb && (tdiv == TICK_DIV[15:0] - 16'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          tdiv <= 16'd0;
        else if (!carrier)   tdiv <= 16'd0;
        else if (bit_stb)    tdiv <= tick ? 16'd0 : tdiv + 1'b1;
    end
    assign tick_1k = tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)        ldiv <= 16'd0;
        else if (!carrier) ldiv <= 16'd0;
        else if (bit_stb)  ldiv <= (ldiv == LED_DIV[15:0] - 16'd1) ? 16'd0
                                                                  : ldiv + 1'b1;
    end
    // Half the period lit.  Watches RX only, never the upstream (§5).
    assign led = carrier && (ldiv < (LED_DIV[15:0] >> 1));

    // ---- the dialer (su-1.md §4) ----------------------------------------
    // The hook reaches the dialer through the carrier.  A loop-timed set with
    // no downstream has no clock and cannot put anything on the upstream at
    // all -- not 1100, not CVSD -- so a cut pair reads as on-hook at the
    // exchange (subscriber-line.md §2) and clears the call like a hang-up
    // (register.md §3.2).  It is the same fact the dark LED reports.
    wire live = hook_sw & carrier;
    wire brk, seized;
    su_dial #(
        .PPS(PPS), .BREAK_PCT(BREAK_PCT),
        .T_OH(T_OH), .T_ID(T_ID), .DEBOUNCE(DEBOUNCE)
    ) u_dial (
        .clk(clk), .rst_n(rst_n), .tick_1k(tick),
        .off_hook(live), .key_n(key_n),
        .seized(seized), .brk(brk), .off_normal(off_normal)
    );
    assign mute = off_normal;
    assign m    = seized && !brk;
    assign ring = e && !hook_sw;

    // ---- the two held patterns (subscriber-line.md §2) -------------------
    // p2 toggles every bit: 1010.  p4[1] changes every two bits: 1100.
    reg [1:0] p4;
    reg       p2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin p4 <= 2'd0; p2 <= 1'b1; end
        else if (bit_stb) begin
            p4 <= p4 + 1'b1;
            p2 <= ~p2;
        end
    end
    wire pat_1100 = p4[1];
    wire pat_1010 = p2;

    assign tx = (!live || brk)    ? pat_1100 :
                mute              ? pat_1010 :
                                    cv_bit;

    // Decoder feed: 1010 while ringing, else the line bit (§4).
    assign bit_dec = ring ? pat_1010 : rx;

    // ---- talk UI (§3.2) --------------------------------------------------
    // SPEAKER sends receive audio to the loudspeaker and mutes the ear; the
    // loudspeaker is also the ringer, so it is enabled on-hook while ringing.
    // The mic gate is dial MUTE first, then LIVE/PTT.
    assign ear_mute = !hook_sw || spk_sw;
    assign spk_en   = ring || (hook_sw && spk_sw);
    assign mic_en   = hook_sw && !mute && (ptt_mode ? ptt : 1'b1);
endmodule

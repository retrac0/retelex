// su1 -- mk1 CVSD subscriber unit digital, su-1.md.
//
// Phone-side dialer and hook on the simplified four-wire subscriber interface
// (line_card.v): m / tx / rx / e.  Autovon keys → 1–16 pulses at 10 pps 60/40.
// Off-normal mutes the encoder (tx idle pattern).  RING · ON-HOOK arms the
// sounder; decoder feed is 1010 while ringing.  Hardware TX during breaks is
// 1100 on the line; here breaks drop m the way phone.v / pulse_gen do.
`timescale 1ns/1ps

module su1 #(
    parameter integer PPS       = 10,
    parameter integer BREAK_PCT = 60,
    parameter integer T_OH      = 500,    // seize delay, ms of TICK
    parameter integer T_ID      = 700,    // interdigit pause
    parameter integer DEBOUNCE  = 20
)(
    input            clk,
    input            rst_n,
    input            frame_stb,
    input            tick_1k,

    input            hook_sw,             // 1 = off-hook
    input     [15:0] key_n,               // Autovon pad, active low
                                          // [0]=1 .. [8]=9, [9]=0, [10]=*,
                                          // [11]=#, [12]=FO, [13]=F, [14]=I, [15]=P

    input            rx,                  // C from the exchange (simplified)
    input            e,                   // ring cadence while on-hook
    input            cv_bit,              // encoder bit when talking

    output           m,                   // off-hook with dial breaks
    output           tx,                  // toward the exchange
    output           ring,                // sounder: RING · ON-HOOK
    output           mute,                // encoder silence (off-normal)
    output           bit_dec,             // to decoder: 1010 while ringing
    output           off_normal           // dial train in progress
);
    localparam IDLE = 3'd0, WAIT = 3'd1, READY = 3'd2,
               BRK  = 3'd3, MK   = 3'd4, IDP   = 3'd5;

    // Crystal path only (su-1.md §4): 10 pps 60/40 from TICK.
    wire [9:0] period  = (10'd1000 / PPS[9:0]);
    wire [16:0] brk_prod = {7'd0, period} * {10'd0, BREAK_PCT[6:0]};
    wire [9:0]  brk_ms   = brk_prod / 10'd100;
    wire [9:0]  mk_ms    = period - brk_ms;
    wire [9:0]  oh_ms    = T_OH[9:0];

    // Same pin→count map as pulse_gen (FO/F/I/P = A–D = 13–16).
    function [4:0] keymap;
        input [15:0] k;
        begin
            if      (!k[ 0]) keymap = 5'd1;
            else if (!k[ 1]) keymap = 5'd2;
            else if (!k[ 2]) keymap = 5'd3;
            else if (!k[ 3]) keymap = 5'd4;
            else if (!k[ 4]) keymap = 5'd5;
            else if (!k[ 5]) keymap = 5'd6;
            else if (!k[ 6]) keymap = 5'd7;
            else if (!k[ 7]) keymap = 5'd8;
            else if (!k[ 8]) keymap = 5'd9;
            else if (!k[ 9]) keymap = 5'd10;
            else if (!k[10]) keymap = 5'd11;
            else if (!k[11]) keymap = 5'd12;
            else if (!k[12]) keymap = 5'd13;
            else if (!k[13]) keymap = 5'd14;
            else if (!k[14]) keymap = 5'd15;
            else if (!k[15]) keymap = 5'd16;
            else             keymap = 5'd0;
        end
    endfunction

    reg [2:0]  st;
    reg [5:0]  db;
    reg        armed, key_stb;
    reg [4:0]  key_n_lat, raw_n;
    reg        q_valid;
    reg [4:0]  q_n;
    reg [4:0]  left;
    reg [9:0]  tmr;

    wire       seized   = (st != IDLE);
    wire       breaking = (st == BRK);
    // Off-normal: digit train or a queued digit waiting to start.
    assign     off_normal = (st == BRK) || (st == MK) || (st == IDP) ||
                            (seized && q_valid);
    assign     mute       = off_normal;
    assign     m          = seized && !breaking;
    assign     ring       = e && !hook_sw;

    wire [4:0] raw = keymap(key_n);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= IDLE;
            db <= 0; armed <= 0; key_stb <= 0; key_n_lat <= 0; raw_n <= 0;
            q_valid <= 0; q_n <= 0; left <= 0; tmr <= 0;
        end else begin
            key_stb <= 1'b0;

            if (!hook_sw) begin
                st <= IDLE; tmr <= 0; left <= 0;
                q_valid <= 0;
                db <= 0; armed <= 0; raw_n <= 0;
            end else begin
                if (tick_1k) begin
                    if (raw == 5'd0) begin
                        db <= 0; armed <= 1'b0; raw_n <= 0;
                    end else if (raw != raw_n) begin
                        raw_n <= raw; db <= 0;
                    end else if (!armed) begin
                        if (db == DEBOUNCE[5:0] - 1) begin
                            key_stb   <= 1'b1;
                            key_n_lat <= raw;
                            armed     <= 1'b1;
                            db        <= 0;
                        end else db <= db + 1'b1;
                    end
                end

                if (st == READY && q_valid) begin
                    left <= q_n; tmr <= 0; st <= BRK;
                    if (key_stb && key_n_lat != 5'd0) q_n <= key_n_lat;
                    else q_valid <= 1'b0;
                end else if (key_stb && !q_valid && key_n_lat != 5'd0) begin
                    q_valid <= 1'b1; q_n <= key_n_lat;
                end

                case (st)
                IDLE: begin
                    st <= WAIT; tmr <= 0;
                end
                WAIT: if (tick_1k) begin
                    if (tmr == oh_ms - 1) begin
                        st <= READY; tmr <= 0;
                    end else tmr <= tmr + 1'b1;
                end
                READY: ;
                BRK: if (tick_1k) begin
                    if (tmr == brk_ms - 1) begin
                        tmr <= 0; st <= MK;
                    end else tmr <= tmr + 1'b1;
                end
                MK: if (tick_1k) begin
                    if (tmr == mk_ms - 1) begin
                        tmr <= 0;
                        if (left == 5'd1) st <= IDP;
                        else begin left <= left - 1'b1; st <= BRK; end
                    end else tmr <= tmr + 1'b1;
                end
                IDP: if (tick_1k) begin
                    if (tmr == T_ID[9:0] - 1) begin
                        tmr <= 0; st <= READY;
                    end else tmr <= tmr + 1'b1;
                end
                default: st <= IDLE;
                endcase
            end
        end
    end

    // Idle / mute pattern 1010 on the bit stream; speech when off-hook and live.
    reg pat;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) pat <= 1'b1;
        else if (frame_stb) pat <= ~pat;
    end

    // On-hook: quiet on simplified C (hardware would hold 1100).
    // Off-normal: encoder muted → 1010-class idle (breaks still drop m).
    // Talking: cv_bit.
    assign tx = !hook_sw ? 1'b0 :
                mute     ? pat  :
                           cv_bit;

    // Decoder feed: 1010 while ringing, else the line bit.
    assign bit_dec = ring ? pat : rx;

endmodule

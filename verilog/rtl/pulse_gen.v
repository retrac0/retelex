// pulse_gen -- hook/pulse generator card, pulse-gen.md.
//
// A line that lifts, with sixteen buttons and no handset.  A_TX is off-hook
// with 10 pps breaks; C_TX is FILL; /ANS is low; the word pin is grounded.
// Two timebases: the socket's crystal divided to 10 pps 60/40, or an
// adjustable RC/DIP source (PPS / BREAK_PCT / T_OH, or the DIP straps).
`timescale 1ns/1ps

module pulse_gen #(
    parameter integer PPS       = 10,
    parameter integer BREAK_PCT = 60,
    parameter integer T_OH      = 500,    // seize delay, ms of TICK
    parameter integer T_ID      = 700,    // interdigit pause
    parameter integer T_DT      = 8,      // tick_1k samples of C_RX != FILL
    parameter integer DEBOUNCE  = 20,
    parameter         USE_DIP   = 1'b0
)(
    input            clk,
    input            rst_n,
    input            tick_1k,
    input            tx_oct,
    input            fill,
    input            c_rx,

    input            hook_sw,
    input     [15:0] key_n,           // one pin a button, active low

    input            use_xtal,        // 1: 10 pps 60/40 from TICK
    input            wait_dt,         // 1: wait for dial tone, else T_OH / DIP
    input      [1:0] dip_pps,         // 0=8, 1=10, 2=12
    input            dip_brk,         // 0=60 %, 1=67 %
    input      [3:0] dip_oh,          // (n+1)*100 ms seize delay when USE_DIP

    output           c_tx,
    output           a_tx,
    output           word_pin,
    output           ans_n
);
    localparam IDLE = 3'd0, WAIT = 3'd1, READY = 3'd2,
               BRK  = 3'd3, MK   = 3'd4, IDP   = 3'd5;

    assign c_tx     = fill;
    assign word_pin = 1'b0;           // grounded: a plain line
    assign ans_n    = 1'b0;           // never rings

    wire [6:0] pct_eff = use_xtal ? 7'd60 :
                         USE_DIP ? (dip_brk ? 7'd67 : 7'd60) :
                         BREAK_PCT[6:0];
    // Period in ms of TICK.  Crystal is 100; DIP/RC divide 1000 by the rate
    // so a scaled bench (PPS=50) is 20 ms, not a 5-bit slice of 50.
    wire [9:0] period  = use_xtal ? 10'd100 :
                         USE_DIP ? ((dip_pps == 2'd0) ? 10'd125 :
                                    (dip_pps == 2'd2) ? 10'd83  : 10'd100) :
                         (10'd1000 / PPS[9:0]);
    wire [16:0] brk_prod = {7'd0, period} * {10'd0, pct_eff};
    wire [9:0]  brk_ms   = brk_prod / 10'd100;
    wire [9:0]  mk_ms    = period - brk_ms;
    wire [9:0] oh_ms   = USE_DIP ? ({6'd0, dip_oh} + 10'd1) * 10'd100
                                 : T_OH[9:0];

    // Hex: pin n (0..15) is n+1 pulses (0 is pin 10, * 11, # 12, A–D 13–16).
    // Lowest pressed pin wins — 2 × '148.
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
    reg [4:0]  dt_n;
    reg        dt_ok;
    wire       seized   = (st != IDLE);
    wire       breaking = (st == BRK);
    assign     a_tx     = seized && !breaking;

    wire [4:0] raw = keymap(key_n);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= IDLE;
            db <= 0; armed <= 0; key_stb <= 0; key_n_lat <= 0; raw_n <= 0;
            q_valid <= 0; q_n <= 0; left <= 0; tmr <= 0;
            dt_n <= 0; dt_ok <= 0;
        end else begin
            key_stb <= 1'b0;

            if (!hook_sw) begin
                st <= IDLE; tmr <= 0; left <= 0;
                q_valid <= 0; dt_n <= 0; dt_ok <= 0;
                db <= 0; armed <= 0; raw_n <= 0;
            end else begin
                if (tick_1k) begin
                    if (c_rx != fill) begin
                        if (dt_n != 5'h1F) dt_n <= dt_n + 1'b1;
                        if (dt_n >= T_DT[4:0] - 1) dt_ok <= 1'b1;
                    end

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

                // Consume a queued digit, then accept a new key into the
                // one-deep queue so a press during a train is not lost.
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
                    if (wait_dt) begin
                        if (dt_ok) st <= READY;
                    end else if (tmr == oh_ms - 1) begin
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
endmodule

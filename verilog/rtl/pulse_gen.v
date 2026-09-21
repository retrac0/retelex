// pulse_gen -- hook/pulse generator card, pulse-gen.md.
//
// A line that lifts, with a keypad and no handset.  A_TX is off-hook with
// 10 pps breaks; C_TX is FILL; /ANS is low; the word pin is grounded.  Two
// timebases: the socket's crystal divided to 10 pps 60/40, or an adjustable
// RC/DIP source (PPS / BREAK_PCT / T_OH, or the DIP straps).
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
    output reg [3:0] row,             // one-hot, active low
    input      [3:0] col,             // active low

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

    function [4:0] keymap;
        input [1:0] r, c;
        begin
            case ({r, c})
                4'b00_00: keymap = 5'd1;
                4'b00_01: keymap = 5'd2;
                4'b00_10: keymap = 5'd3;
                4'b00_11: keymap = 5'd13;     // A
                4'b01_00: keymap = 5'd4;
                4'b01_01: keymap = 5'd5;
                4'b01_10: keymap = 5'd6;
                4'b01_11: keymap = 5'd14;     // B
                4'b10_00: keymap = 5'd7;
                4'b10_01: keymap = 5'd8;
                4'b10_10: keymap = 5'd9;
                4'b10_11: keymap = 5'd15;     // C
                4'b11_00: keymap = 5'd11;     // *
                4'b11_01: keymap = 5'd10;     // 0
                4'b11_10: keymap = 5'd12;     // #
                default:  keymap = 5'd16;     // D
            endcase
        end
    endfunction

    reg [2:0]  st;
    reg [1:0]  scan_r;
    reg [5:0]  db;
    reg        armed, key_stb;
    reg [4:0]  key_n;
    reg        raw_v;
    reg [4:0]  raw_n;
    reg        q_valid;
    reg [4:0]  q_n;
    reg [4:0]  left;
    reg [9:0]  tmr;
    reg [4:0]  dt_n;
    reg        dt_ok;
    wire       seized   = (st != IDLE);
    wire       breaking = (st == BRK);
    assign     a_tx     = seized && !breaking;

    wire       hit   = ~(&col);
    wire [1:0] hit_c = !col[0] ? 2'd0 : !col[1] ? 2'd1 :
                       !col[2] ? 2'd2 : 2'd3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= IDLE; scan_r <= 0; row <= 4'b1110;
            db <= 0; armed <= 0; key_stb <= 0; key_n <= 0;
            raw_v <= 0; raw_n <= 0;
            q_valid <= 0; q_n <= 0; left <= 0; tmr <= 0;
            dt_n <= 0; dt_ok <= 0;
        end else begin
            key_stb <= 1'b0;

            if (!hook_sw) begin
                st <= IDLE; tmr <= 0; left <= 0;
                q_valid <= 0; dt_n <= 0; dt_ok <= 0;
                db <= 0; armed <= 0; raw_v <= 0;
                row <= 4'b1110; scan_r <= 0;
            end else begin
                if (tick_1k) begin
                    if (c_rx != fill) begin
                        if (dt_n != 5'h1F) dt_n <= dt_n + 1'b1;
                        if (dt_n >= T_DT[4:0] - 1) dt_ok <= 1'b1;
                    end

                    // A key is visible one row in four.  Latch it for the
                    // scan, and debounce on the scan wrap, not on the miss
                    // ticks in between.
                    if (hit) begin
                        raw_v <= 1'b1;
                        raw_n <= keymap(scan_r, hit_c);
                    end
                    if (scan_r == 2'd3) begin
                        if (raw_v || hit) begin
                            if (!armed) begin
                                if (db == DEBOUNCE[5:0] - 1) begin
                                    key_stb <= 1'b1;
                                    key_n   <= hit ? keymap(scan_r, hit_c) : raw_n;
                                    armed   <= 1'b1;
                                    db      <= 0;
                                end else db <= db + 1'b1;
                            end
                        end else begin
                            db <= 0; armed <= 1'b0;
                        end
                        raw_v <= 1'b0;
                    end

                    scan_r <= scan_r + 1'b1;
                    row    <= ~(4'b0001 << (scan_r + 1'b1));
                end

                // Consume a queued digit, then accept a new key into the
                // one-deep queue so a press during READY is not lost.
                if (st == READY && q_valid) begin
                    left <= q_n; tmr <= 0; st <= BRK;
                    if (key_stb && key_n != 5'd0) q_n <= key_n;
                    else q_valid <= 1'b0;
                end else if (key_stb && !q_valid && key_n != 5'd0) begin
                    q_valid <= 1'b1; q_n <= key_n;
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

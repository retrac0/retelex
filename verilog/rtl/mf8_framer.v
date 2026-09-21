// mf8_framer -- mf8-spec.md 4, the 16-bit eight-channel frame of mf8-unit.md 4.2.
// One check, one acquisition counter, two up/down counters.
//
//   good frame :=  F == word[sfc]
//                  AND ( sfc != 0  OR  S == 0 )
//                  AND ( sfc != 8  OR  S == 1 )
//
// The word is 1111111111111110: one zero, at state 15, so F == 0 IS the phase
// marker and the superframe phase is READ, not searched.  Acquisition is a hunt
// over sixteen bit alignments, not two hundred and fifty-six combinations.
//
//   acquire :  no candidate yet -> F == 0 loads sfc = 0 and starts the count.
//              Sixteen frames with no zero: this cannot be the F lane, slip one
//              line bit.  With a candidate the check is predictive; any
//              mismatch slips one bit and restarts.  Lock at 32 good frames.
//   track   :  the same check, +2 bad / -1 good, floor 0, trip at 12, on TWO
//              counters.  One is fed by every frame; the other only at the
//              guard states, by the S half alone -- without it a lock whose F
//              always passes and whose guard never does holds forever (4).
`timescale 1ns/1ps

module mf8_framer #(
    parameter integer ACQ  = 32,
    parameter integer TRIP = 12
)(
    input            clk,
    input            rst_n,
    input            bit_stb,
    input            bit_val,
    input            cd,
    output reg       locked,
    output reg [7:0] rx_c,        // C0..C7 packed, slot n of the unit
    output reg [7:0] rx_a         // A0..A7 packed, same order
);
    localparam HUNT = 2'd0, CAND = 2'd1, LOCK = 2'd2;

    reg [1:0] st;
    reg [3:0] bitpos, sfc;
    reg       fbit, sbit, swallow;
    reg [7:0] c_acc;
    reg [5:0] cand;
    reg [4:0] cnt_f, cnt_g;
    reg [3:0] nozero;

    wire       fword  = (sfc != 4'd15);             // 1111111111111110
    wire       gstate = (sfc == 4'd0) || (sfc == 4'd8);
    wire       sok    = (sfc == 4'd0) ? (sbit == 1'b0) : (sbit == 1'b1);
    wire       good   = (fbit == fword) && (!gstate || sok);
    wire       a_seat = (sfc >= 4'd1 && sfc <= 4'd7) || (sfc == 4'd9);
    wire [2:0] a_idx  = (sfc == 4'd9) ? 3'd7 : (sfc[2:0] - 3'd1);

    task do_slip;                                   // slip one line bit and hunt again
        begin
            swallow <= 1'b1; st <= HUNT; locked <= 1'b0;
            cand <= 0; nozero <= 0; cnt_f <= 0; cnt_g <= 0;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= HUNT; bitpos <= 0; sfc <= 0; fbit <= 0; sbit <= 0; swallow <= 0;
            c_acc <= 0; cand <= 0; cnt_f <= 0; cnt_g <= 0; nozero <= 0;
            locked <= 0; rx_c <= 8'b10101010; rx_a <= 0;
        end else if (!cd) begin
            // Loss of signal: squelch, and start again when it comes back.
            st <= HUNT; locked <= 1'b0; cand <= 0; nozero <= 0;
            cnt_f <= 0; cnt_g <= 0; rx_a <= 8'd0;
        end else if (bit_stb) begin
            if (swallow) begin
                swallow <= 1'b0;                    // the slipped bit: drop it, hold the count
            end else begin
                case (bitpos)
                    4'd0: fbit      <= bit_val;
                    4'd1: c_acc[0]  <= bit_val;
                    4'd2: c_acc[1]  <= bit_val;
                    4'd3: c_acc[2]  <= bit_val;
                    4'd4: c_acc[3]  <= bit_val;
                    4'd5: c_acc[4]  <= bit_val;
                    4'd6: c_acc[5]  <= bit_val;
                    4'd7: c_acc[6]  <= bit_val;
                    4'd8: begin
                              sbit <= bit_val;
                              if (locked && a_seat) rx_a[a_idx] <= bit_val;
                          end
                    4'd9: c_acc[7]  <= bit_val;
                    default: ;
                endcase

                if (bitpos == 4'd15) begin          // end of frame: check it
                    case (st)
                    HUNT: begin
                              if (fbit == 1'b0) begin
                                  sfc <= 4'd0;      // that frame was state 15
                                  cand <= 6'd1; nozero <= 0; st <= CAND;
                              end else if (nozero == 4'd15) begin
                                  do_slip;
                              end else nozero <= nozero + 1'b1;
                          end
                    CAND: begin
                              sfc <= sfc + 1'b1;
                              if (!good) do_slip;
                              else if (cand == ACQ[5:0] - 1) begin
                                  st <= LOCK; locked <= 1'b1; cnt_f <= 0; cnt_g <= 0;
                              end else cand <= cand + 1'b1;
                          end
                    LOCK: begin
                              sfc  <= sfc + 1'b1;
                              rx_c <= c_acc;
                              if (!good) begin
                                  if (cnt_f + 2 >= TRIP[4:0]) do_slip;
                                  else cnt_f <= cnt_f + 5'd2;
                              end else if (cnt_f != 0) cnt_f <= cnt_f - 1'b1;

                              if (gstate) begin     // the second counter, guard states only
                                  if (!sok) begin
                                      if (cnt_g + 2 >= TRIP[4:0]) do_slip;
                                      else cnt_g <= cnt_g + 5'd2;
                                  end else if (cnt_g != 0) cnt_g <= cnt_g - 1'b1;
                              end
                          end
                    default: st <= HUNT;
                    endcase
                end
                bitpos <= bitpos + 1'b1;
            end
        end
    end
endmodule

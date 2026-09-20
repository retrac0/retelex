// monitor -- the seeker.  exch-monitor.md.
//
// The only part of the network that reads a digit it was not sent, so it is the
// part that must never be wrong.  It sits on a block that holds trunks and
// reads its trunk ports' M lines directly; it never touches the fabric.
//
//   idle      the trunk's M is low
//   seized    M rises, AND THE MONITOR SAW IT RISE    -> count this seizure
//   counting  register.md 2's windows, on that M
//   decide    first digit is our e   -> read one more
//             second is our b        -> CLAIM
//             either 8 or 9          -> reserved: let go
//             anything else          -> let go, at once
//   done      nothing more until the trunk releases
//
// Rule 1 -- "only a seizure whose rise it saw" -- is what keeps a monitor that
// attached late, in the pause BETWEEN two digits, from counting b as e and h as
// b.  It is true by construction here: the scanner keeps a bit per slot of what
// M was at the last visit, and a rise is M high now and low then.  The scanner
// steps on the 8 kHz octet mark, so a seizure is caught within 1 ms of its
// rise, in which no pulse can fit.  Rule 2, the origin's 128 ms guard, is the
// marker's.
`timescale 1ns/1ps

module monitor #(
    parameter [2:0]   OWN_E = 3'd0,
    parameter [2:0]   OWN_B = 3'd0,
    parameter [2:0]   BLOCK = 3'd0,          // which block these eight slots are
    parameter integer HIT = 8, ID = 128, CLR = 256
)(
    input            clk,
    input            rst_n,
    input            oct_stb,                // 8 kHz: one slot a visit, eight in a ms
    input            tick_1k,
    input      [7:0] m,                      // the block's eight ports' M, direct
    input      [7:0] chan_mask,              // which slots the trunk card owns

    output reg       claim,                  // one pulse: this port is ours
    output reg [5:0] claim_port,
    output reg       held                    // a seizure is being counted
);
    localparam IDLE = 2'd0, WANT_E = 2'd1, WANT_B = 2'd2, DONE = 2'd3;

    reg [2:0] scan;
    reg [7:0] seen;                          // M at the last visit, a bit a slot
    reg [1:0] st;
    reg [2:0] slot;
    reg [9:0] low_ms;

    wire [3:0] d_cnt;
    wire       d_stb, d_clr;

    pulse_rx #(.HIT(HIT), .ID(ID), .CLR(CLR)) u_rx (
        .clk(clk), .rst_n(rst_n), .tick_1k(tick_1k), .arm(held), .m(m[slot]),
        .cnt(d_cnt), .dig_stb(d_stb), .clear(d_clr), .counting(), .brk_stb());

    // e and b are 0-7 and a dialled 0 is ten pulses; 8 and 9 are reserved.
    wire [2:0] val = (d_cnt == 4'd10) ? 3'd0 : d_cnt[2:0];
    wire       bad = (d_cnt == 4'd8) || (d_cnt == 4'd9) || (d_cnt > 4'd10);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan <= 0; seen <= 0; st <= IDLE; slot <= 0; held <= 0;
            claim <= 0; claim_port <= 0; low_ms <= 0;
        end else begin
            claim <= 1'b0;

            if (oct_stb) begin
                // a fresh seizure is M high now and low at the last visit
                if (st == IDLE && chan_mask[scan] && m[scan] && !seen[scan]) begin
                    slot <= scan; held <= 1'b1; st <= WANT_E;
                end
                seen[scan] <= m[scan];
                scan <= scan + 1'b1;
            end

            if (held) begin
                if (d_stb) begin
                    case (st)
                    WANT_E:  if (bad || val != OWN_E) begin held <= 0; st <= IDLE; end
                             else st <= WANT_B;
                    WANT_B:  if (bad || val != OWN_B) begin held <= 0; st <= IDLE; end
                             else begin
                                 claim <= 1'b1; claim_port <= {BLOCK, slot};
                                 st <= DONE;                 // it reads two digits and no more
                             end
                    default: ;
                    endcase
                end
                // the trunk releasing frees the monitor: M low for 256 ms
                if (tick_1k) begin
                    if (m[slot]) low_ms <= 0;
                    else if (low_ms == CLR[9:0]) begin
                        held <= 1'b0; st <= IDLE; low_ms <= 0;
                    end else low_ms <= low_ms + 1'b1;
                end
                if (d_clr) begin held <= 1'b0; st <= IDLE; end
            end
        end
    end
endmodule

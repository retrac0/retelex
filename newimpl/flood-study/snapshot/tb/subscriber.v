// subscriber -- a behavioural CVSD phone on the two-pair line, for a bench.
// subscriber-line.md 4's phone end, and su-1.md's mk1 set in outline.
//
//   TX            = ON-HOOK or dial break ? 1100 : the codec
//   codec input   = dial off normal ? silence (1010) : the microphone
//   ring          = RING . ON-HOOK                  -> the ringer
//   decoder input = RING ? 1010 : Q ; audio muted while ON-HOOK
//
// The hook switch and the dial contact are in series, as on an analog loop,
// and both are INPUTS here: a bench works the phone by its buttons, never by
// reaching into it.  The codec is a repeating sixteen-bit pattern standing in
// for CVSD, so a bench can check the bits arrive in order; its X density --
// the hook detector's one-bit function, Q xor Q[n-2] -- is 0.125, inside the
// 0.00 to 0.53 subscriber-line.md 2 measured for speech.
//
// The phone has its own crystal.  Here it is a free-running cell counter on
// the bench's clock; the receiver at the far end tolerates +-13 % of a cell,
// so it need not be the same crystal, but in this bench it is.
`timescale 1ns/1ps

module subscriber #(
    parameter integer CELL  = 64,            // master ticks a cell: 64 kbps
    parameter [15:0]  VOICE = 16'hAAAF       // the codec, LSB first
)(
    input        clk,
    input        rst_n,

    // ---- the two pairs -------------------------------------------------------
    input        line_dn,        // from the exchange
    output reg   line_up,        // to the exchange

    // ---- the buttons ----------------------------------------------------------
    input        off_hook,       // the hook switch AND the dial contact
    input        dial_on,        // the dial is off normal: the codec is muted

    // ---- what a bench can see --------------------------------------------------
    output       ringing,        // the ringer
    output       q,              // what the decoder hears
    output       q_stb
);
    // ---- the bit clock -------------------------------------------------------
    reg [7:0] cnt;
    wire cell_start = (cnt == 8'd0);
    wire cell_mid   = (cnt == CELL[7:0] / 8'd2);

    // ---- the transmitter -----------------------------------------------------
    // 1100 is the bit clock divided by four; 1010 is divided by two.
    reg [1:0] ph;
    reg [3:0] vi;
    wire tx_bit = !off_hook ? ~ph[1]                     // on-hook, or a break: 1100
                : dial_on   ? ~ph[0]                     // dial off normal: 1010
                :             VOICE[vi];                 // the microphone

    // the encoder: mf8-spec.md 9.2, on the phone's own boundary and mid-cell
    reg tx_l;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 8'd0; ph <= 2'd0; vi <= 4'd0; tx_l <= 1'b1; line_up <= 1'b0;
        end else begin
            cnt <= (cnt == CELL[7:0] - 8'd1) ? 8'd0 : cnt + 8'd1;
            if (cell_start) begin
                line_up <= ~line_up;
                tx_l    <= tx_bit;
                ph      <= ph + 2'd1;
                vi      <= vi + 4'd1;
            end else if (cell_mid && !tx_l) begin
                line_up <= ~line_up;
            end
        end
    end

    // ---- the receiver: the same four packages as the exchange's ------------
    wire carrier, viol;
    dm_rx #(.CELL(CELL)) u_rx (
        .clk(clk), .rst_n(rst_n), .line(line_dn),
        .q(q), .q_stb(q_stb), .carrier(carrier), .viol(viol));

    // ---- the ring detector: subscriber-line.md 3, the phone's reading -------
    // The same RC and comparator as the exchange's hook detector, on /Q: all
    // zeros drive it to 1 and ring; 1010, speech and a dead pair -- whose
    // latch idles at 1 and whose no-carrier forces 1 -- never pass 0.6.
    // Zeros cannot arrive by accident.
    localparam [15:0] HI = 16'd55705;      // 0.85
    localparam [15:0] LO = 16'd45875;      // 0.70
    wire       q_c = q || !carrier;        // no carrier forces 1
    reg [15:0] rc;
    reg        ring;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rc <= 16'd0; ring <= 1'b0; end
        else if (cell_start) begin
            rc <= !q_c ? rc + ((16'hFFFF - rc) >> 8) : rc - (rc >> 8);
            if      (rc > HI) ring <= 1'b1;
            else if (rc < LO) ring <= 1'b0;
        end
    end
    assign ringing = ring && !off_hook;

    wire _unused = &{1'b0, viol, 1'b0};
endmodule

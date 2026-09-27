// tb_chat -- does a CHATTERING clock contact defeat the RIDE entry of the
// poison fix (verifier's rtl_mut/baseband_card.v)?  Card alone, plus one
// pulse_rx fed by a 1 kHz sample of A_TX (as the probe gives a monitor cell).
// Real timers: HIT 8, ID 128, CLR 256.  1 master tick = 244 ns; 64 ticks a
// frame; 4096 ticks = 1 ms.  The far end is in a steady MAKE (a_in = 1).
//   sc A (150 ms): CLK pin chatters for 30 ms: open, with a 0.2 ms closure
//                  every 3 ms placed between probe samples.  A pin fine.
//   sc B (600 ms): CLK and A pins chatter together, same pattern.
//   sc C (1000 ms): control, a clean 30 ms cut of CLK: poison must set.
`timescale 1ns/1ps
module tb_chat;
    reg clk = 0, rst_n = 0;
    always #122 clk = ~clk;
    reg [31:0] n = 0;
    always @(posedge clk) n <= n + 1;
    wire tx_clk = n[5];
    wire far_clk_src = ~n[5];            // far crystal, half a frame off
    reg  contact_clk = 1, contact_a = 1;
    wire clk_in = far_clk_src & contact_clk;
    wire a_in   = 1'b1 & contact_a;       // caller in a make
    wire a_tx, link_up;
    baseband_card dut (.clk(clk), .rst_n(rst_n),
        .tx_clk(tx_clk), .loop_hb(1'b0), .tx_oct(1'b0), .fill(1'b0),
        .c_tx(), .a_tx(a_tx), .rx_clk(1'b0), .rx_oct(1'b0), .c_rx(1'b0), .a_rx(1'b0),
        .mute(1'b0), .word_n(), .ans_n(), .rai_n(),
        .c_out(), .a_out(), .clk_out(), .c_in(1'b0), .a_in(a_in), .clk_in(clk_in),
        .link_up(link_up));
    // the probe: one sample of M a millisecond, at tick_1k
    wire tick_1k = (n[11:0] == 12'd0) && (n != 0);
    reg  arm = 0;
    wire [3:0] cnt; wire dig, clr, brk, cnting, steady;
    pulse_rx #(.HIT(9'd8), .ID(9'd128), .CLR(9'd256)) pr (.clk(clk), .rst_n(rst_n),
        .tick_1k(tick_1k), .arm(arm), .m(a_tx), .cnt(cnt), .dig_stb(dig),
        .clear(clr), .counting(cnting), .brk_stb(brk), .steady(steady));
    real ms; always @* ms = n / 4096.0;
    integer brks = 0, digs = 0, clrs = 0, pois_seen = 0;
    reg pois_d = 0;
    always @(posedge clk) begin
        if (brk) begin brks = brks + 1; $display("%8.2f ms  pulse_rx COUNTED A BREAK (cnt->%0d)", ms, cnt+1); end
        if (dig) begin digs = digs + 1; $display("%8.2f ms  pulse_rx DIGIT %0d", ms, cnt); end
        if (clr) begin clrs = clrs + 1; $display("%8.2f ms  pulse_rx CLEAR (hang-up)", ms); end
        pois_d <= dut.poison;
        if (dut.poison && !pois_d) begin pois_seen = pois_seen + 1; $display("%8.2f ms  card POISONED", ms); end
        if (!dut.poison && pois_d) $display("%8.2f ms  card poison cleared", ms);
    end
    // chatter: open, except 0.2 ms closures at k+0.4 .. k+0.6 ms every 3 ms
    task chatter(input integer t0_ms, input integer len_ms, input both);
        integer k;
        begin
            wait (n >= t0_ms*4096);
            $display("%8.2f ms  --- chatter starts (%s) for %0d ms", ms, both ? "CLK+A" : "CLK only", len_ms);
            for (k = 0; k < len_ms; k = k + 3) begin
                contact_clk = 0; if (both) contact_a = 0;
                wait (n >= (t0_ms+k)*4096 + 1638);        // k+0.4 ms
                contact_clk = 1; if (both) contact_a = 1;
                wait (n >= (t0_ms+k)*4096 + 2458);        // k+0.6 ms
                contact_clk = 0; if (both) contact_a = 0;
                wait (n >= (t0_ms+k+3)*4096);
            end
            contact_clk = 1; contact_a = 1;
            $display("%8.2f ms  --- contact closed for good", ms);
        end
    endtask
    initial begin
        #1000 rst_n = 1;
        wait (n >= 120*4096); arm = 1;
        $display("%8.2f ms  card settled=%0d link_up=%0d a_tx=%0d; register armed", ms, dut.settled, link_up, a_tx);
        chatter(150, 30, 0);
        wait (n >= 550*4096);
        $display("sc A (CLK chatter): breaks %0d, digits %0d, poison %0d", brks, digs, pois_seen);
        chatter(600, 30, 1);
        wait (n >= 950*4096);
        $display("sc B (CLK+A chatter): breaks %0d, digits %0d, poison %0d (cumulative)", brks, digs, pois_seen);
        wait (n >= 1000*4096); contact_clk = 0; $display("%8.2f ms  --- clean cut of CLK, 30 ms", ms);
        wait (n >= 1030*4096); contact_clk = 1; $display("%8.2f ms  --- CLK back", ms);
        wait (n >= 1400*4096);
        $display("sc C (clean cut): breaks %0d, digits %0d, clears %0d, poison %0d (cumulative)", brks, digs, clrs, pois_seen);
        $finish;
    end
endmodule

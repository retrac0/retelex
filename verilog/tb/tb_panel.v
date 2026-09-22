// tb_panel -- the hook/busy display against the two cables.  hookbusy.md 7.
//
// The panel is a passive listener, so it is tested the way the counter card is:
// drive the real clock card, drive ctl_write with the words the marker
// actually sends, and look at the lamps.  What this bench is for is the
// ASYMMETRY -- the two halves of the panel come off different cables, refresh
// at rates three orders of magnitude apart, and fail differently:
//
//   the hook field   HA[0..7], cable A.  All 64 ports, every 15.6 us.
//                    WORKS WITH NO MARKER FITTED -- bring-up step 2
//   the busy field   PB0, cable B.  EIGHT ports -- the block DST[5:3] names.
//                    Refreshed when the scanner comes round, ~9 ms.  Freezes
//                    when the marker stops
//
// Part 6 is the one that needed measuring.  A '259 is TRANSPARENT while
// addressed, and mid-word the '164 holds rippling garbage, so the row the '138
// names walks through every block while PB is briefly undriven and reading
// LOW.  observers.md 3 claims a lamp would be wrongly CLEARED and hold that
// until its block's next visit.  Two identical stacks run side by side here,
// one with the INH one-shot and one without, and the control is the point:
// without it the fault is real and it is not small.
`timescale 1ns/1ps

module tb_panel;
    // the exchange's own crystal, 4.096 MHz
    reg clk = 0, rst_n = 0;
    always #122.0703 clk = ~clk;

    reg reset_n = 0;                    // /RESET, cable B pin 7

    // ---- the clock card ------------------------------------------------
    wire [2:0] tick, slot, slotq;
    wire       hclk, frame_stb;
    clock_card u_clk (
        .clk(clk), .rst_n(rst_n), .tick(tick), .hclk(hclk), .line_hb(),
        .slot(slot), .slotq(slotq), .cap_stb(), .tx_clk(), .frame_stb(frame_stb),
        .tx_oct(), .rx_oct(), .fill(), .ring_cad_n(), .tick_1k());

    // ---- the marker's serialiser, driven by hand -----------------------
    reg        w_req = 0;
    reg  [5:0] w_dst = 0;
    wire       ser_busy, sdata, sclk;
    ctl_write u_ser (.clk(clk), .rst_n(rst_n), .req(w_req), .strobe(1'b0),
                     .g(1'b1), .dst(w_dst), .src(6'd0), .bsy(1'b0), .clm(1'b0),
                     .busy(ser_busy), .sdata(sdata), .sclk(sclk), .wr());

    // ---- what the fabric is carrying ------------------------------------
    // hook_state and busy_state are the 64 ports.  HA is eight highways, each
    // commutated on SLOT; PB0 is ONE wire carrying one block at a time, and
    // which block is whichever one the last sixteen-bit word named.
    reg [63:0] hook_state = 64'd0;
    reg [63:0] busy_state = 64'd0;

    wire [2:0] dst_blk;
    wire [7:0] ha;
    genvar h;
    generate for (h = 0; h < 8; h = h + 1) begin : hw
        assign ha[h] = hook_state[{h[2:0], slot}];
    end endgenerate
    // THE HAND-OVER, modelled.  Whatever the '164 names is what drives PB0,
    // and mid-word the '164 ripples: the decode walks, one block's '244 turns
    // off and the next turns on, and for that instant PB is undriven.  It is
    // pulled LOW at the marker (mainboard.md 6), so an undriven instant
    // reads NOT BUSY.  This is not a pathological case injected by hand -- it
    // happens on every one of the sixteen shifts of every word.
    reg [2:0] dst_d = 3'd0;
    reg [2:0] hand  = 3'd0;
    always @(posedge clk) begin
        dst_d <= dst_blk;
        if (dst_blk !== dst_d) hand <= 3'd3;
        else if (hand != 3'd0)  hand <= hand - 1'b1;
    end
    wire pb0 = (hand != 3'd0) ? 1'b0 : busy_state[{dst_blk, slot}];

    // ---- three stacks ----------------------------------------------------
    wire [127:0] lamp, lamp_naive, lamp_hook;

    // the normal configuration: alternating hook and busy, blocks paired
    hb_panel u_panel (
        .clk(clk), .rst_n(rst_n), .reset_n(reset_n),
        .slotq(slotq), .hclk(hclk), .ha(ha), .sdata(sdata), .sclk(sclk),
        .pb0(pb0), .lamp(lamp), .dst_blk(dst_blk));

    // THE CONTROL: the same stack with the INH one-shot left out
    hb_panel #(.INH_EN(1'b0)) u_naive (
        .clk(clk), .rst_n(rst_n), .reset_n(reset_n),
        .slotq(slotq), .hclk(hclk), .ha(ha), .sdata(sdata), .sclk(sclk),
        .pb0(pb0), .lamp(lamp_naive), .dst_blk());

    // sixteen hook cards: the same PCB, jumpered the other way
    hb_panel #(.HOOK(16'hFFFF)) u_hook (
        .clk(clk), .rst_n(rst_n), .reset_n(reset_n),
        .slotq(slotq), .hclk(hclk), .ha(ha), .sdata(sdata), .sclk(sclk),
        .pb0(pb0), .lamp(lamp_hook), .dst_blk());

    // ---- reading the panel ------------------------------------------------
    integer errs = 0, chk = 0;

    function [7:0] col(input [127:0] p, input integer c);
        col = p[c*8 +: 8];
    endfunction
    function [7:0] row(input [63:0] st, input integer b);
        row = st[b*8 +: 8];
    endfunction

    task want(input [7:0] got, input [7:0] exp, input string what);
        begin
            chk = chk + 1;
            if (got !== exp) begin
                errs = errs + 1;
                $display("     %-52s FAIL  got %08b want %08b", what, got, exp);
            end else $display("     %-52s ok  %08b", what, got);
        end
    endtask

    task wantn(input integer got, input integer exp, input string what);
        begin
            chk = chk + 1;
            if (got !== exp) begin
                errs = errs + 1;
                $display("     %-52s FAIL  got %0d want %0d", what, got, exp);
            end else $display("     %-52s ok  %0d", what, got);
        end
    endtask

    // one probe-steer word, exactly as marker.v sends it: DST names the block
    // the scanner is visiting, and no WR, so nothing anywhere writes a latch.
    task point(input [2:0] b);
        begin
            @(posedge clk); w_dst = {b, 3'd0}; w_req = 1;
            @(posedge clk); w_req = 0;
            @(posedge clk);
            wait (!ser_busy);
            settle;
        end
    endtask

    task settle; repeat (3) @(posedge frame_stb); endtask

    task scan; integer b; for (b = 0; b < 8; b = b + 1) point(b[2:0]); endtask

    // how many busy columns disagree with what the fabric is carrying
    function integer stale(input [127:0] p, input [63:0] st);
        integer b, n;
        begin
            n = 0;
            for (b = 0; b < 8; b = b + 1)
                if (col(p, 2*b + 1) !== row(st, b)) n = n + 1;
            stale = n;
        end
    endfunction

    integer b;
    localparam [63:0] PAT_A = 64'hF0E1_D2C3_B4A5_9687;
    localparam [63:0] PAT_B = 64'h0102_0408_1020_4080;
    localparam [63:0] PAT_C = 64'hAA55_C33C_0FF0_1248;
    localparam [63:0] PAT_D = 64'h1357_9BDF_2468_ACE0;

    initial begin
        $display("");
        $display("  tb_panel -- hookbusy.md, seventeen cards on a stack");
        $display("");

        repeat (8) @(posedge clk); rst_n = 1; reset_n = 1;
        settle;

        // ---- 1. the hook field, with no marker at all --------------------
        // Not one word has been on cable B.  fabric.md 7 step 2 is a
        // clock card and one block, and the hook field is fitted there.
        hook_state = PAT_A; settle;
        $display("  1. the hook field with NO marker fitted -- cable A alone");
        for (b = 0; b < 8; b = b + 1)
            want(col(lamp, 2*b), row(PAT_A, b), $sformatf("block %0d hook, green column %0d", b, 2*b));
        wantn(stale(lamp, 64'd0), 0, "and every busy column still dark");
        $display("");

        // ---- 2. refreshed every frame ------------------------------------
        hook_state = PAT_B; repeat (2) @(posedge frame_stb);
        $display("  2. a new pattern is on the panel within two frames");
        for (b = 0; b < 8; b = b + 1)
            want(col(lamp, 2*b), row(PAT_B, b), $sformatf("block %0d hook", b));
        $display("");

        // ---- 3. the busy field is EIGHT ports wide ------------------------
        busy_state = PAT_C;
        point(3'd3);
        $display("  3. one word naming block 3: eight lamps move, 56 do not");
        want(col(lamp, 7), row(PAT_C, 3), "block 3 busy, orange column 7");
        for (b = 0; b < 8; b = b + 1) if (b != 3)
            want(col(lamp, 2*b + 1), 8'd0, $sformatf("block %0d busy -- never named, still dark", b));
        $display("");

        // ---- 4. the window walks with the scanner -------------------------
        scan;
        $display("  4. the scanner walks 0-7 and the whole field fills");
        wantn(stale(lamp, PAT_C), 0, "all eight busy columns agree with the fabric");
        $display("");

        // ---- 5. a row not named HOLDS -------------------------------------
        busy_state = PAT_D;
        point(3'd5);
        $display("  5. the fabric changes; only the block NAMED is re-read");
        want(col(lamp, 11), row(PAT_D, 5), "block 5 busy -- named, so current");
        want(col(lamp,  7), row(PAT_C, 3), "block 3 busy -- not named, so HISTORY");
        wantn(stale(lamp, PAT_D), 7, "seven of eight columns stale: 9 ms, not 15.6 us");
        $display("");

        // ---- 6. THE INHIBIT, and the control ------------------------------
        // Every word above has already rippled its '164 through every block
        // while PB was undriven at each hand-over.  The INH stack has been
        // blind for the 31 us of each word and has lost nothing; the control
        // has been writing all the way through them.  observers.md 3.
        scan;
        $display("  6. the hand-over, on every word -- INH against no INH");
        wantn(stale(lamp, PAT_D), 0,
              "with INH: not one lamp wrongly cleared");
        chk = chk + 1;
        if (stale(lamp_naive, PAT_D) == 0) begin
            errs = errs + 1;
            $display("     %-52s FAIL  the control did not fail", "without INH: lamps lost");
        end else
            $display("     %-52s ok  %0d of 8 columns corrupted",
                     "without INH: lamps lost", stale(lamp_naive, PAT_D));
        $display("");

        // ---- 7. /RESET ----------------------------------------------------
        // The one signal that clears every latch in the exchange clears all 64
        // busy lamps in the same instant -- and does not put anyone's phone
        // down, because the hook field's /CLR is tied high (observers.md 2).
        hook_state = {64{1'b1}}; settle;
        @(posedge clk); reset_n = 0; repeat (8) @(posedge clk); reset_n = 1;
        settle;
        $display("  7. /RESET: the busy field goes out, the hook field does not");
        for (b = 0; b < 8; b = b + 1)
            want(col(lamp, 2*b), 8'hFF, $sformatf("block %0d hook -- /CLR tied high", b));
        // All 64 cleared in the same instant -- and then the ONE block the
        // stack's own '164 still names is read again within a frame, because
        // nothing cleared the word.  The other seven wait for the scanner.
        want(col(lamp, 15), row(PAT_D, 7), "block 7 busy -- still named, back in a frame");
        wantn(stale(lamp, {PAT_D[63:56], 56'd0}), 0,
              "the other seven dark, and dark until the scanner returns");
        $display("");

        // ---- 8. the same PCB, jumpered the other way ----------------------
        // Sixteen hook cards.  Nothing on cable B is needed for any of them.
        hook_state = PAT_C; settle;
        $display("  8. sixteen hook cards -- one PCB, a different jumper");
        for (b = 0; b < 8; b = b + 1) begin
            want(col(lamp_hook, 2*b),     row(PAT_C, b), $sformatf("block %0d, column %0d", b, 2*b));
            want(col(lamp_hook, 2*b + 1), row(PAT_C, b), $sformatf("block %0d, column %0d -- the pair agrees", b, 2*b+1));
        end
        $display("");

        if (errs == 0) $display("  tb_panel: %0d checks, all ok", chk);
        else           $display("  tb_panel: %0d checks, %0d FAILED", chk, errs);
        $display("");
        if (errs) $fatal(1);
        $finish;
    end
endmodule

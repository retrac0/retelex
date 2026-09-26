// tb_ltu -- two exchanges and a local eight-channel highway trunk, patched by
// hand.  trunks.md §3; network.md §1, §8.
//
// Exchange A and exchange B each have the unit on block 1 (ports 10-17) and
// eight phones on block 2 (20-27), and run on two crystals.  Nothing here
// dials: each exchange's latches are written by hand over its own cable B --
// A's 2k to its 1k, B's 1k to its 2k -- so A's phone 2k is wired through
// channel k to B's phone 2k, eight hotlines on one cable.
//
// What it proves: every channel reads its unit's word (class, glare,
// direction) at both ends; a cut cable busies the whole group through
// MUTE_BLK with no latch written, and reads NONE on all eight; bits cross all
// eight channels both ways, in order, a bit a frame, and no channel carries
// another's; A crosses channel by channel, end to end, and a dial break keeps
// its length; a cut drops A and sends FILL; and with the crystals 1000 ppm
// apart the channels slip, one bit at a time, and still carry their own
// traffic and nobody else's.
//
// A SLIP ON A.  Through an exchange a channel's A is E, captured once a pass,
// so an edge reaches the unit once a millisecond at most and a slip lands on
// one about once in a thousand.  So a second pair of units stands beside the
// first with nothing behind their headers: the bench drives their C_RX and
// A_RX itself, a random bit a frame on C AND on A, on each end's own clocks.
// Half the frames carry an A edge, so half of all slips land on one.  Each
// slip must be one bit doubled or dropped, never more; A and C in a channel
// must slip together, since one '273 edge crosses both; and no A bit may ever
// land on another channel's port.
//
// Does not cover: dialling across the unit (tb_lnet, tb_lfull and tb_lchain
// do), or the eye at 512 kbps on a real cable.
`timescale 1ns/1ps
`include "exch.vh"

module tb_ltu;
    integer chk = 0, errs = 0;
    task ck(input cond, input [8*72-1:0] what);
        begin chk = chk + 1;
             if (!cond) begin errs = errs + 1; $display("    FAIL  %0s", what); end
        end
    endtask

    // B's crystal is a variable so the slip section can pull it 1000 ppm off
    reg  clk_a = 1'b0, clk_b = 1'b0, rst_n = 1'b0;
    real hp_b = 122.070;
    always #122.070 clk_a = ~clk_a;
    initial begin #40; forever #(hp_b) clk_b = ~clk_b; end

    localparam [7:0] WA = {2'd2, 1'b0, 3'b010, 2'b11};   // A's unit faces E
    localparam [7:0] WB = {2'd3, 1'b1, 3'b010, 2'b11};   // B's faces W, with glare
    localparam [63:0] PF = 64'h0000_0000_00FF_FF00;      // blocks 1 and 2, full

    // ---- the cable, and a cut in it ------------------------------------------
    // A cut is receivers whose failsafe reads 1 on an open line: every
    // conductor high, HCLK included, so no edge arrives.
    reg  cut = 1'b0;
    wire a_c_out, a_a_out, a_h_out, a_k_out, b_c_out, b_a_out, b_h_out, b_k_out;

    // ---- one exchange: exch, the unit on block 1, phones on block 2 ---------
    reg  [63:0] a_ctx = 64'd0, a_atx = 64'd0, b_ctx = 64'd0, b_atx = 64'd0;
    wire [63:0] a_crx, a_arx, a_busy, b_crx, b_arx, b_busy;
    wire a_hw_n, a_ws_n, a_fs, a_cap, a_txclk, a_oct, a_rxoct, a_fill, a_t1k, a_hclk;
    wire b_hw_n, b_ws_n, b_fs, b_cap, b_txclk, b_oct, b_rxoct, b_fill, b_t1k, b_hclk;
    wire [2:0] a_slotq, b_slotq;
    wire [`SCANW-1:0] a_scan, b_scan;
    wire a_sd, a_sc, a_wr, a_oe, b_sd, b_sc, b_wr, b_oe;
    wire [7:0] a_l_ctx, a_l_atx, a_l_word, a_l_ans, b_l_ctx, b_l_atx, b_l_word, b_l_ans;
    wire a_mute, b_mute, a_up, b_up;

    // The phones' pins by hand: word grounded, a plain line; /ANS open.
    reg [63:0] a_c_in, a_a_in, b_c_in, b_a_in, a_word, b_word, a_ans, b_ans;
    always @* begin
        a_c_in = a_ctx; a_c_in[15:8] = a_l_ctx;   a_a_in = a_atx; a_a_in[15:8] = a_l_atx;
        b_c_in = b_ctx; b_c_in[15:8] = b_l_ctx;   b_a_in = b_atx; b_a_in[15:8] = b_l_atx;
        a_word = {64{1'b1}}; a_word[23:16] = 8'd0; a_word[15:8] = a_l_word;
        b_word = {64{1'b1}}; b_word[23:16] = 8'd0; b_word[15:8] = b_l_word;
        a_ans  = {64{1'b1}}; a_ans[15:8] = a_l_ans;
        b_ans  = {64{1'b1}}; b_ans[15:8] = b_l_ans;
    end

    exch #(.PORT_FITTED(PF), .BLOCK_FITTED(8'b0000_0110)) u_a (
        .clk(clk_a), .rst_n(rst_n),
        .c_tx(a_c_in), .a_tx(a_a_in), .ans_n(a_ans), .word_n(a_word),
        .c_rx(a_crx), .a_rx(a_arx), .mute_blk({6'd0, a_mute, 1'b0}), .rbt_in(1'b0),
        .sdata(a_oe && a_sd), .sclk(a_oe && a_sc), .wr(a_oe && a_wr), .ws_n(a_ws_n), .hw_n(a_hw_n),
        .hc(), .ha_n(), .hb_n(), .tick(), .slot(), .slotq(a_slotq),
        .hclk(a_hclk), .cap_stb(a_cap), .tx_clk(a_txclk),
        .frame_stb(a_fs), .clk_8k(a_oct), .rx_oct(a_rxoct), .oct_stb(),
        .scan(a_scan), .pass_stb(), .fill(a_fill), .ring_cad_n(), .tick_1k(a_t1k),
        .port_busy(a_busy));

    exch #(.PORT_FITTED(PF), .BLOCK_FITTED(8'b0000_0110)) u_b (
        .clk(clk_b), .rst_n(rst_n),
        .c_tx(b_c_in), .a_tx(b_a_in), .ans_n(b_ans), .word_n(b_word),
        .c_rx(b_crx), .a_rx(b_arx), .mute_blk({6'd0, b_mute, 1'b0}), .rbt_in(1'b0),
        .sdata(b_oe && b_sd), .sclk(b_oe && b_sc), .wr(b_oe && b_wr), .ws_n(b_ws_n), .hw_n(b_hw_n),
        .hc(), .ha_n(), .hb_n(), .tick(), .slot(), .slotq(b_slotq),
        .hclk(b_hclk), .cap_stb(b_cap), .tx_clk(b_txclk),
        .frame_stb(b_fs), .clk_8k(b_oct), .rx_oct(b_rxoct), .oct_stb(),
        .scan(b_scan), .pass_stb(), .fill(b_fill), .ring_cad_n(), .tick_1k(b_t1k),
        .port_busy(b_busy));

    // HOLDOFF cut to 64 frames so the bench does not sit through 100 ms
    local_trunk #(.WORD(WA), .HOLDOFF(16'd64)) u_la (
        .clk(clk_a), .rst_n(rst_n),
        .c_tx(a_l_ctx), .a_tx(a_l_atx), .word_n(a_l_word), .ans_n(a_l_ans),
        .c_rx(a_crx[15:8]), .a_rx(a_arx[15:8]),
        .tx_clk(a_txclk), .tx_oct(a_oct), .fill(a_fill), .hclk(a_hclk), .mute_blk(a_mute),
        .c_out(a_c_out), .a_out(a_a_out), .hclk_out(a_h_out), .clk_out(a_k_out),
        .c_in(cut ? 1'b1 : b_c_out), .a_in(cut ? 1'b1 : b_a_out),
        .hclk_in(cut ? 1'b1 : b_h_out), .clk_in(cut ? 1'b1 : b_k_out),
        .link_up(a_up));

    local_trunk #(.WORD(WB), .HOLDOFF(16'd64)) u_lb (
        .clk(clk_b), .rst_n(rst_n),
        .c_tx(b_l_ctx), .a_tx(b_l_atx), .word_n(b_l_word), .ans_n(b_l_ans),
        .c_rx(b_crx[15:8]), .a_rx(b_arx[15:8]),
        .tx_clk(b_txclk), .tx_oct(b_oct), .fill(b_fill), .hclk(b_hclk), .mute_blk(b_mute),
        .c_out(b_c_out), .a_out(b_a_out), .hclk_out(b_h_out), .clk_out(b_k_out),
        .c_in(cut ? 1'b1 : a_c_out), .a_in(cut ? 1'b1 : a_a_out),
        .hclk_in(cut ? 1'b1 : a_h_out), .clk_in(cut ? 1'b1 : a_k_out),
        .link_up(b_up));

    // ---- the bare pair: two more units, their headers on the bench's pins ------
    reg  [7:0] xa_c = 8'd0, xa_a = 8'd0, xb_c = 8'd0, xb_a = 8'd0;
    wire [7:0] xa_ctx, xa_atx, xb_ctx, xb_atx;
    wire       xa_co, xa_ao, xa_ho, xa_ko, xb_co, xb_ao, xb_ho, xb_ko, xa_up, xb_up;

    local_trunk #(.WORD(WA), .HOLDOFF(16'd64)) u_xa (
        .clk(clk_a), .rst_n(rst_n),
        .c_tx(xa_ctx), .a_tx(xa_atx), .word_n(), .ans_n(),
        .c_rx(xa_c), .a_rx(xa_a),
        .tx_clk(a_txclk), .tx_oct(a_oct), .fill(a_fill), .hclk(a_hclk), .mute_blk(),
        .c_out(xa_co), .a_out(xa_ao), .hclk_out(xa_ho), .clk_out(xa_ko),
        .c_in(xb_co), .a_in(xb_ao), .hclk_in(xb_ho), .clk_in(xb_ko),
        .link_up(xa_up));

    local_trunk #(.WORD(WB), .HOLDOFF(16'd64)) u_xb (
        .clk(clk_b), .rst_n(rst_n),
        .c_tx(xb_ctx), .a_tx(xb_atx), .word_n(), .ans_n(),
        .c_rx(xb_c), .a_rx(xb_a),
        .tx_clk(b_txclk), .tx_oct(b_oct), .fill(b_fill), .hclk(b_hclk), .mute_blk(),
        .c_out(xb_co), .a_out(xb_ao), .hclk_out(xb_ho), .clk_out(xb_ko),
        .c_in(xa_co), .a_in(xa_ao), .hclk_in(xa_ho), .clk_in(xa_ko),
        .link_up(xb_up));

    // ---- a master on each cable B, and a word reader on each /WS, by hand -----
    reg  [1:0]  a_pn = 2'b00, b_pn = 2'b00;
    reg  [29:0] a_pd = 30'd0, b_pd = 30'd0;
    reg         a_rq = 1'b0, b_rq = 1'b0;
    reg  [`PW-1:0] a_rp = 6'd0, b_rp = 6'd0;
    wire        a_rd, b_rd, a_ovf, b_ovf, a_emp, b_emp;
    wire [7:0]  a_rw, b_rw;
    wire        a_ws_pd, b_ws_pd;

    ctl_queue #(.DEPTH(4), .NP(2)) u_ma (
        .clk(clk_a), .rst_n(rst_n),
        .sdata(a_sd), .sclk(a_sc), .wr(a_wr), .oe(a_oe),
        .go(1'b1), .pending(), .empty(a_emp),
        .push_v(a_pn), .push_d(a_pd), .room(), .ovf(a_ovf), .sent());
    ctl_queue #(.DEPTH(4), .NP(2)) u_mb (
        .clk(clk_b), .rst_n(rst_n),
        .sdata(b_sd), .sclk(b_sc), .wr(b_wr), .oe(b_oe),
        .go(1'b1), .pending(), .empty(b_emp),
        .push_v(b_pn), .push_d(b_pd), .room(), .ovf(b_ovf), .sent());

    assign a_ws_n = ~a_ws_pd;
    assign b_ws_n = ~b_ws_pd;
    word_rx u_ra (
        .clk(clk_a), .rst_n(rst_n),
        .slotq(a_slotq), .cap_stb(a_cap), .frame_stb(a_fs), .scan(a_scan),
        .hw_n(a_hw_n), .ws_n(a_ws_n), .ws_pd(a_ws_pd),
        .rd_req(a_rq), .rd_port(a_rp), .busy(), .done(a_rd), .word(a_rw));
    word_rx u_rb (
        .clk(clk_b), .rst_n(rst_n),
        .slotq(b_slotq), .cap_stb(b_cap), .frame_stb(b_fs), .scan(b_scan),
        .hw_n(b_hw_n), .ws_n(b_ws_n), .ws_pd(b_ws_pd),
        .rd_req(b_rq), .rd_port(b_rp), .busy(), .done(b_rd), .word(b_rw));

    function [14:0] ent(input [`PW-1:0] d, input [`PW-1:0] s);
        ent = {1'b1, 1'b0, 1'b1, s, d};          // G, no CLAIM, BSY
    endfunction

    task patch_a(input [`PW-1:0] x, input [`PW-1:0] y);
        begin
            @(posedge clk_a); a_pn = 2'b11; a_pd = {ent(y, x), ent(x, y)};
            @(posedge clk_a); a_pn = 2'b00;
            @(posedge clk_a); while (!a_emp) @(posedge clk_a);
        end
    endtask
    task patch_b(input [`PW-1:0] x, input [`PW-1:0] y);
        begin
            @(posedge clk_b); b_pn = 2'b11; b_pd = {ent(y, x), ent(x, y)};
            @(posedge clk_b); b_pn = 2'b00;
            @(posedge clk_b); while (!b_emp) @(posedge clk_b);
        end
    endtask
    reg [7:0] got;
    task read_a(input [`PW-1:0] p);
        begin
            @(posedge clk_a); a_rp = p; a_rq = 1'b1; @(posedge clk_a); a_rq = 1'b0;
            while (!a_rd) @(posedge clk_a); got = a_rw;
        end
    endtask
    task read_b(input [`PW-1:0] p);
        begin
            @(posedge clk_b); b_rp = p; b_rq = 1'b1; @(posedge clk_b); b_rq = 1'b0;
            while (!b_rd) @(posedge clk_b); got = b_rw;
        end
    endtask

    // ---- bits across: eight patterns each way, a bit a frame -----------------
    // Each phone sends its own 16-bit LFSR from its own seed.  Each end keeps
    // the last 64 bits each phone sent and each phone received; at every
    // receiving frame, channel k's last 32 bits are looked for in EVERY
    // sender's history at delays 0-16.  Its own sender: a hit.  Another's: a
    // cross, which must never happen.  The delay of each hit is kept, so a
    // slip shows as the delay moving by one.
    reg [15:0] la [0:7];
    reg [15:0] lb [0:7];
    reg [63:0] s_ab [0:7];   // sent by A's 2k
    reg [63:0] s_ba [0:7];   // sent by B's 2k
    reg [63:0] r_ab [0:7];   // received at B's 2k
    reg [63:0] r_ba [0:7];   // received at A's 2k
    reg        drive = 1'b0, meas = 1'b0;
    integer    hit_ab [0:7], hit_ba [0:7], win_ab [0:7], win_ba [0:7];
    integer    dmin_ab [0:7], dmax_ab [0:7], dmin_ba [0:7], dmax_ba [0:7];
    integer    n_cross = 0;
    integer    k, j, d;
    // Sixteen points 4 095 or more apart on the one m-sequence, so no two
    // phones' patterns are within the 16-frame search of each other.  Seeds
    // picked by formula once landed two of them 5 steps apart, and the bench
    // reported crosstalk that was only the patterns agreeing.
    localparam [127:0] SEED_A = {16'h1CBB, 16'h5276, 16'h7D51, 16'h9F9D, 16'hD6C2, 16'h00D2, 16'h37A6, 16'hACE1};
    localparam [127:0] SEED_B = {16'h2B91, 16'hDFE4, 16'hE948, 16'h038F, 16'h6C22, 16'h0E17, 16'hBAB4, 16'h1ABD};

    initial begin
        for (k = 0; k < 8; k = k + 1) begin
            la[k] = SEED_A[k*16 +: 16]; lb[k] = SEED_B[k*16 +: 16];
            s_ab[k] = 64'd0; s_ba[k] = 64'd0; r_ab[k] = 64'd0; r_ba[k] = 64'd0;
        end
    end
    task clear_counts;
        begin
            for (k = 0; k < 8; k = k + 1) begin
                hit_ab[k] = 0; hit_ba[k] = 0; win_ab[k] = 0; win_ba[k] = 0;
                dmin_ab[k] = 99; dmax_ab[k] = -1; dmin_ba[k] = 99; dmax_ba[k] = -1;
            end
            n_cross = 0;
        end
    endtask

    function [15:0] step(input [15:0] x);
        step = {x[14:0], x[15] ^ x[13] ^ x[12] ^ x[10]};
    endfunction

    integer ka, kb;
    always @(posedge clk_a) if (a_fs) begin
        for (ka = 0; ka < 8; ka = ka + 1) begin
            if (drive) begin la[ka] = step(la[ka]); a_ctx[16 + ka] <= la[ka][0]; end
            s_ab[ka] = {s_ab[ka][62:0], a_ctx[16 + ka]};
            r_ba[ka] = {r_ba[ka][62:0], a_crx[16 + ka]};
        end
        if (meas) look(1'b0);
    end
    always @(posedge clk_b) if (b_fs) begin
        for (kb = 0; kb < 8; kb = kb + 1) begin
            if (drive) begin lb[kb] = step(lb[kb]); b_ctx[16 + kb] <= lb[kb][0]; end
            s_ba[kb] = {s_ba[kb][62:0], b_ctx[16 + kb]};
            r_ab[kb] = {r_ab[kb][62:0], b_crx[16 + kb]};
        end
        if (meas) look(1'b1);
    end

    // at_b: B has just received a frame, so look at A-to-B; else B-to-A
    integer lk, lj, ld, dd;
    reg     hh;
    task look(input at_b);
        begin
            for (lk = 0; lk < 8; lk = lk + 1) begin
                hh = 1'b0; dd = -1;
                for (lj = 0; lj < 8; lj = lj + 1)
                    for (ld = 0; ld <= 16; ld = ld + 1)
                        if (at_b ? (r_ab[lk][39:8] == s_ab[lj][ld+8 +: 32])
                                 : (r_ba[lk][39:8] == s_ba[lj][ld+8 +: 32])) begin
                            if (lj == lk) begin hh = 1'b1; dd = ld; end
                            else n_cross = n_cross + 1;
                        end
                if (at_b) begin
                    win_ab[lk] = win_ab[lk] + 1;
                    if (hh) begin
                        hit_ab[lk] = hit_ab[lk] + 1;
                        if (dd < dmin_ab[lk]) dmin_ab[lk] = dd;
                        if (dd > dmax_ab[lk]) dmax_ab[lk] = dd;
                    end
                end else begin
                    win_ba[lk] = win_ba[lk] + 1;
                    if (hh) begin
                        hit_ba[lk] = hit_ba[lk] + 1;
                        if (dd < dmin_ba[lk]) dmin_ba[lk] = dd;
                        if (dd > dmax_ba[lk]) dmax_ba[lk] = dd;
                    end
                end
            end
        end
    endtask

    // worst channel's hit fraction, in thousandths; and whether any slipped
    integer worst, slipped;
    task tally;
        begin
            worst = 1000; slipped = 0;
            for (k = 0; k < 8; k = k + 1) begin
                if (win_ab[k] == 0 || win_ba[k] == 0) worst = 0;
                else begin
                    if (1000 * hit_ab[k] / win_ab[k] < worst) worst = 1000 * hit_ab[k] / win_ab[k];
                    if (1000 * hit_ba[k] / win_ba[k] < worst) worst = 1000 * hit_ba[k] / win_ba[k];
                end
                if (dmax_ab[k] > dmin_ab[k] || dmax_ba[k] > dmin_ba[k]) slipped = slipped + 1;
            end
        end
    endtask

    // ---- the bare pair's traffic: C and A, a bit a frame each -----------------
    // C A-to-B from SEED_A and A A-to-B from SEED_B; the other way round going
    // back.  The sixteen seeds are all 4 095 apart, so within one direction no
    // channel's A can match another's by accident.  Each receiving frame looks
    // for its channel's last 32 A bits at delays 0-16 in every sender's A
    // history, and its last 32 C bits in its own sender's C history.
    reg [15:0] xla_c [0:7], xla_a [0:7], xlb_c [0:7], xlb_a [0:7];
    reg [63:0] xs_ab_c [0:7], xs_ab_a [0:7], xs_ba_c [0:7], xs_ba_a [0:7];
    reg [63:0] xr_ab_c [0:7], xr_ab_a [0:7], xr_ba_c [0:7], xr_ba_a [0:7];
    reg        xdrive = 1'b0, xmeas = 1'b0;
    // A SLIP IS A DELAY CHANGE AFTER A GAP.  The delay measured here also moves,
    // with no gap, when the sender's frame edge crosses the receiver's: the
    // same bits, counted from a different edge.  A doubled or dropped bit
    // spoils every window that spans it first, so only a change that follows
    // missed windows is counted as a slip.
    integer    xwin, xhit, xcross, xslip, xjump, xmism, xch;   // over both directions
    integer    xprev [0:15];                                    // last A delay, a direction-channel
    integer    xsl [0:15];                                      // A slips, a direction-channel
    integer    xgap [0:15];                                     // windows missed since the last hit

    initial begin
        for (k = 0; k < 8; k = k + 1) begin
            xla_c[k] = SEED_A[k*16 +: 16]; xla_a[k] = SEED_B[k*16 +: 16];
            xlb_c[k] = SEED_B[k*16 +: 16]; xlb_a[k] = SEED_A[k*16 +: 16];
            xs_ab_c[k] = 64'd0; xs_ab_a[k] = 64'd0; xs_ba_c[k] = 64'd0; xs_ba_a[k] = 64'd0;
            xr_ab_c[k] = 64'd0; xr_ab_a[k] = 64'd0; xr_ba_c[k] = 64'd0; xr_ba_a[k] = 64'd0;
        end
    end
    task xclear;
        begin
            xwin = 0; xhit = 0; xcross = 0; xslip = 0; xjump = 0; xmism = 0; xch = 0;
            for (k = 0; k < 16; k = k + 1) begin xprev[k] = -1; xsl[k] = 0; xgap[k] = 0; end
        end
    endtask

    integer xka, xkb;
    always @(posedge clk_a) if (a_fs) begin
        for (xka = 0; xka < 8; xka = xka + 1) begin
            if (xdrive) begin
                xla_c[xka] = step(xla_c[xka]); xa_c[xka] <= xla_c[xka][0];
                xla_a[xka] = step(xla_a[xka]); xa_a[xka] <= xla_a[xka][0];
            end
            xs_ab_c[xka] = {xs_ab_c[xka][62:0], xa_c[xka]};
            xs_ab_a[xka] = {xs_ab_a[xka][62:0], xa_a[xka]};
            xr_ba_c[xka] = {xr_ba_c[xka][62:0], xa_ctx[xka]};
            xr_ba_a[xka] = {xr_ba_a[xka][62:0], xa_atx[xka]};
        end
        if (xmeas) xlook(1'b0);
    end
    always @(posedge clk_b) if (b_fs) begin
        for (xkb = 0; xkb < 8; xkb = xkb + 1) begin
            if (xdrive) begin
                xlb_c[xkb] = step(xlb_c[xkb]); xb_c[xkb] <= xlb_c[xkb][0];
                xlb_a[xkb] = step(xlb_a[xkb]); xb_a[xkb] <= xlb_a[xkb][0];
            end
            xs_ba_c[xkb] = {xs_ba_c[xkb][62:0], xb_c[xkb]};
            xs_ba_a[xkb] = {xs_ba_a[xkb][62:0], xb_a[xkb]};
            xr_ab_c[xkb] = {xr_ab_c[xkb][62:0], xb_ctx[xkb]};
            xr_ab_a[xkb] = {xr_ab_a[xkb][62:0], xb_atx[xkb]};
        end
        if (xmeas) xlook(1'b1);
    end

    integer xk, xj, xd, xda, xdc, xi;
    reg [31:0] xw_a, xw_c;
    task xlook(input at_b);
        begin
            for (xk = 0; xk < 8; xk = xk + 1) begin
                xi  = at_b ? xk : 8 + xk;
                xw_a = at_b ? xr_ab_a[xk][39:8] : xr_ba_a[xk][39:8];
                xw_c = at_b ? xr_ab_c[xk][39:8] : xr_ba_c[xk][39:8];
                xda = -1; xdc = -1;
                for (xd = 0; xd <= 16; xd = xd + 1) begin
                    if (xw_c == (at_b ? xs_ab_c[xk][xd+8 +: 32] : xs_ba_c[xk][xd+8 +: 32])) xdc = xd;
                    for (xj = 0; xj < 8; xj = xj + 1)
                        if (xw_a == (at_b ? xs_ab_a[xj][xd+8 +: 32] : xs_ba_a[xj][xd+8 +: 32])) begin
                            if (xj == xk) xda = xd;
                            else xcross = xcross + 1;
                        end
                end
                xwin = xwin + 1;
                if (xda >= 0) begin
                    xhit = xhit + 1;
                    if (xprev[xi] >= 0 && xda != xprev[xi]) begin
                        if (xda - xprev[xi] > 1 || xprev[xi] - xda > 1) xjump = xjump + 1;
                        else if (xgap[xi] > 0) begin xslip = xslip + 1; xsl[xi] = xsl[xi] + 1; end
                    end
                    xprev[xi] = xda; xgap[xi] = 0;
                    if (xdc >= 0) begin
                        xch = xch + 1;
                        if (xdc != xda) xmism = xmism + 1;
                    end
                end else xgap[xi] = xgap[xi] + 1;
            end
        end
    endtask
    integer xslipped;
    task xtally;
        begin
            xslipped = 0;
            for (k = 0; k < 16; k = k + 1) if (xsl[k] > 0) xslipped = xslipped + 1;
        end
    endtask

    task ms(input integer n); begin repeat (n) @(posedge a_t1k); end endtask

    // ---- A's edges on channel 3: into A's unit, out of B's -------------------
    realtime a_up_t = 0, a_dn_t = 0, b_up_t = 0, b_dn_t = 0;
    always @(posedge a_arx[6'o13]) a_up_t = $realtime;
    always @(negedge a_arx[6'o13]) a_dn_t = $realtime;
    always @(posedge b_l_atx[3])   b_up_t = $realtime;
    always @(negedge b_l_atx[3])   b_dn_t = $realtime;

    integer n_ok;
    initial begin
        $display("\n  tb_ltu -- two exchanges, one eight-channel highway trunk, patched by hand");
        clear_counts;
        repeat (20) @(posedge clk_a);
        rst_n = 1'b1;
        ms(3);

        // ---- the word, eight times at each end --------------------------------
        n_ok = 0;
        for (k = 0; k < 8; k = k + 1) begin
            read_a(6'o10 + k[5:0]); if (got === WA) n_ok = n_ok + 1;
            read_b(6'o10 + k[5:0]); if (got === WB) n_ok = n_ok + 1;
        end
        ck(n_ok == 16, "all sixteen channels read their unit's word: trunk, glare, direction");
        ck(a_up && b_up && !a_mute && !b_mute, "the link is up both ways: far HCLK arriving, MUTE_BLK off");
        ck(a_busy[15:8] === 8'd0 && b_busy[15:8] === 8'd0, "and the group is idle: no port BUSY");

        // ---- a cut with no call: MUTE_BLK busies the group ---------------------
        cut = 1'b1; ms(2);
        ck(a_mute && b_mute, "a cut cable: both units assert MUTE_BLK");
        ck(a_busy[15:8] === 8'hFF && b_busy[15:8] === 8'hFF,
           "and all sixteen ports read BUSY, with no latch written");
        read_a(6'o14); ck(got === 8'h00, "a channel of a cut group reads NONE");
        read_b(6'o17); ck(got === 8'h00, "at the other end too");
        ck(b_l_ctx === {8{b_fill}}, "a cut group sends FILL into the block on every C");
        cut = 1'b0; ms(2);
        ck(!a_mute && !b_mute && a_busy[15:8] === 8'd0 && b_busy[15:8] === 8'd0,
           "mended: MUTE_BLK falls and the group is free again");
        read_a(6'o14); ck(got === WA, "and reads its word again");

        // ---- eight hotlines: A 2k -- A 1k ~~ B 1k -- B 2k ----------------------
        for (k = 0; k < 8; k = k + 1) begin
            patch_a(6'o20 + k[5:0], 6'o10 + k[5:0]);
            patch_b(6'o10 + k[5:0], 6'o20 + k[5:0]);
        end
        ck(a_busy[23:8] === 16'hFFFF && b_busy[23:8] === 16'hFFFF,
           "thirty-two latches written, BUSY at each");

        // ---- bits across, one crystal's frequency ------------------------------
        drive = 1'b1; xdrive = 1'b1; ms(3);
        clear_counts; xclear; meas = 1'b1; xmeas = 1'b1; ms(20); meas = 1'b0; xmeas = 1'b0;
        tally; xtally;
        ck(worst == 1000, "all eight channels, both ways: every bit in order, a bit a frame");
        ck(xa_up && xb_up && xhit == xwin && xwin > 0 && xslipped == 0 && xmism == 0,
           "the bare pair, A a random bit a frame: every A bit in order, level with its C");
        ck(n_cross == 0, "and no channel ever carried another channel's bits");
        ck(slipped == 0, "at one frequency the delay never moves");

        // ---- A, channel by channel, end to end --------------------------------
        drive = 1'b0; xdrive = 1'b0;
        n_ok = 0;
        for (k = 0; k < 8; k = k + 1) begin
            a_atx[16 + k] = 1'b1; ms(4);
            if (b_arx[23:16] === (8'd1 << k)) n_ok = n_ok + 1;
            a_atx[16 + k] = 1'b0;
            b_atx[16 + k] = 1'b1; ms(4);
            if (a_arx[23:16] === (8'd1 << k)) n_ok = n_ok + 1;
            b_atx[16 + k] = 1'b0; ms(4);
        end
        ck(n_ok == 16, "a phone lifting is E at the far phone on its channel, and only there");

        // ---- dial pulses on channel 3: 60 ms breaks, 40 ms makes --------------
        repeat (3) begin
            a_atx[6'o23] = 1'b1; #40_000_000; a_atx[6'o23] = 1'b0; #60_000_000;
        end
        ms(4);
        ck((b_up_t - a_up_t) < 100_000 && (b_dn_t - a_dn_t) < 100_000,
           "each edge of A crosses the unit in under 0.1 ms");
        ck(((b_dn_t - b_up_t) - (a_dn_t - a_up_t)) < 50_000 &&
           ((a_dn_t - a_up_t) - (b_dn_t - b_up_t)) < 50_000,
           "and a make keeps its length to 0.05 ms");

        // ---- a cut in a call ---------------------------------------------------
        b_atx[6'o25] = 1'b1; ms(4);
        ck(a_arx[6'o25] === 1'b1, "B's 25 off-hook is E at A's 25");
        cut = 1'b1; ms(2);
        ck(a_l_atx === 8'd0 && b_l_atx === 8'd0, "a cut: every unit A_TX falls, so every call releases");
        ck(a_l_ctx === {8{a_fill}}, "and every C into A's block is FILL");
        b_atx[6'o25] = 1'b0;
        cut = 1'b0; ms(3);

        // ---- two crystals 1000 ppm apart: slips, and only slips ----------------
        // A slip a channel every 15.6 ms, so about ten in 150 ms across the
        // sixteen directions: enough to see, few enough to leave most windows
        // whole.  A 32-bit window is spoilt for 32 frames around each slip.
        hp_b = 122.070 * 1.001;
        drive = 1'b1; xdrive = 1'b1; ms(3);
        clear_counts; xclear; meas = 1'b1; xmeas = 1'b1; ms(150); meas = 1'b0; xmeas = 1'b0;
        tally; xtally;
        $display("     1000 ppm: %0d of 8 channels slipped; the worst direction kept %0d.%0d %% of its windows whole",
                 slipped, worst / 10, worst % 10);
        ck(slipped > 0, "1000 ppm apart the delay moves: the channels slip");
        ck(worst >= 900, "and between slips every channel still carries its bits in order");
        ck(n_cross == 0, "and no slip ever lands a channel's bits on another channel");

        // ---- the same 150 ms on the bare pair: slips landing on A ---------------
        $display("     a slip on A: %0d slips in %0d of 16 directions; %0d of %0d A windows whole",
                 xslip, xslipped, xhit, xwin);
        ck(xslipped == 16, "every channel's A slipped, both ways: A a bit a frame, the slips land on it");
        ck(xjump == 0, "each slip on A is one bit doubled or dropped, never more");
        ck(xhit * 10 >= xwin * 9, "and between slips A carries its bits in order");
        ck(xmism == 0, "A and C in a channel slip together: the same '273 edge crosses both");
        ck(xcross == 0, "and no slip ever lands an A bit on another channel's port");
        drive = 1'b0; xdrive = 1'b0;

        ck(!a_ovf && !b_ovf, "neither master's queue refused a write");

        $display("\n  %0d checks, %0d errors.  %s\n", chk, errs,
                 (errs == 0) ? "PASS" : "FAIL");
        if (errs) $fatal(1);
        $finish;
    end

    initial begin #1_500_000_000; $display("  TIMEOUT"); $fatal(1); end

    wire _unused = &{1'b0, a_rxoct, b_rxoct, a_l_ans, b_l_ans, 1'b0};
endmodule

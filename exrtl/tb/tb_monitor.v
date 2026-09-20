// tb_monitor -- the seeker's pool and its seizure rule, on their own.
//
// A system test cannot reach the interesting cases: making two seizures land on
// ONE block wants two registers at the far exchange, and making a claim come
// back wants a transit.  Driving the eight M and BUSY lines directly reaches
// all of it in a tenth of a second.
`timescale 1ns/1ps

module tb_monitor;
    localparam integer NMON = 2;
    localparam integer HIT = 1, ID = 16, CLR = 32;
    localparam [2:0] OWN_E = 3'd2, OWN_B = 3'd3;
    localparam integer BRK = 12_000_000, MK = 8_000_000, PAUSE = 60_000_000;

    reg clk = 0, rst_n = 0;
    always #122.0703 clk = ~clk;

    // the two strobes the block gives a monitor
    // 4.096 MHz: a 64 kHz frame is 64 clocks, an 8 kHz octet 512, a 1 kHz
    // tick 4096.  (Getting these wrong makes every dial break longer than CLR,
    // and the pool frees itself on the first pulse of every digit.)
    reg [12:0] div = 0;
    wire oct_stb = (div[8:0]  == 9'd0);           // 8 kHz, the octet mark
    wire tick_1k = (div[11:0] == 12'd0);          // 1 kHz, the register's tick
    always @(posedge clk) div <= div + 1'b1;

    reg  [7:0] m = 8'h00, busy = 8'h00;
    wire       claim, held, all_busy;
    wire [5:0] claim_port;

    monitor #(.NMON(NMON), .OWN_E(OWN_E), .OWN_B(OWN_B), .BLOCK(3'd0),
              .HIT(HIT), .ID(ID), .CLR(CLR)) dut (
        .clk(clk), .rst_n(rst_n), .oct_stb(oct_stb), .tick_1k(tick_1k),
        .m(m), .busy(busy), .chan_mask(8'b1110_1110),
        .claim(claim), .claim_port(claim_port), .held(held), .all_busy(all_busy));

    integer errs = 0, chk = 0, nclaim = 0;
    reg [7:0] claimed_slots = 0;
    always @(posedge clk) if (claim) begin
        nclaim <= nclaim + 1;
        claimed_slots <= claimed_slots | (8'd1 << claim_port[2:0]);
    end

    task want(input v, input string what);
        begin
            chk = chk + 1;
            if (!v) begin errs = errs + 1; $display("     %-54s FAIL", what); end
            else $display("     %-54s ok", what);
        end
    endtask

    // dial n pulses on slot s
    task dial(input integer s, input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                m[s] = 1'b0; #(BRK); m[s] = 1'b1; #(MK);
            end
            #(PAUSE);
        end
    endtask

    initial begin
        $display("MONITOR (RTL) -- the seeker's pool, and the three terms of its rule.\n");
        #4000 rst_n = 1; #(2_000_000);

        // ---- 1. two seizures at once, both ours -------------------------
        $display("  1. Two seizures on one block, overlapping.  e b = 2 3 on both.");
        m[1] = 1'b1; #(3_000_000);
        want(held, "the first was caught");
        m[2] = 1'b1; #(3_000_000);
        want(!all_busy || NMON == 2, "the second went to the other cell");
        dial(1, 2); dial(2, 2);                 // e = 2 on both
        dial(1, 3); dial(2, 3);                 // b = 3 on both -> claim
        #(40_000_000);
        want(nclaim == 2, "both claimed");
        want(claimed_slots == 8'b0000_0110, "and named their own slots, 01 and 02");
        m[1] = 1'b0; m[2] = 1'b0; #(60_000_000);
        want(!held, "both cells freed when the trunks released");

        // ---- 2. the pool full: a seizure goes unwatched, for good --------
        $display("\n  2. With every cell held, a further seizure is unwatched.");
        nclaim = 0; claimed_slots = 0;
        m[1] = 1'b1; #(2_000_000); m[2] = 1'b1; #(2_000_000);
        want(all_busy, "the pool is full");
        m[3] = 1'b1; #(3_000_000);              // a third seizure, nowhere to go
        dial(3, 2); dial(3, 3);                 // it dials OUR code
        #(40_000_000);
        want(nclaim == 0, "it was never counted, so never claimed");
        m[1] = 0; m[2] = 0; m[3] = 0; #(60_000_000);

        // ---- 3. a claim coming back is not a seizure --------------------
        $display("\n  3. Backward A rising on a trunk THIS exchange already seized.");
        nclaim = 0;
        busy[5] = 1'b1;                         // the marker patched it a while ago
        #(3_000_000);                           // ... and a visit goes by
        m[5]    = 1'b1;                         // now the far end claims: M rises
        #(3_000_000);
        want(!held, "not latched: BUSY was set at the last visit");
        dial(5, 2); dial(5, 3);
        #(40_000_000);
        want(nclaim == 0, "and no claim was made on it");
        m[5] = 0; busy[5] = 0; #(60_000_000);

        // ---- 4. but a real seizure the marker beat us to IS caught -------
        $display("\n  4. A real seizure, with the marker marking it busy first.");
        nclaim = 0; claimed_slots = 0;
        m[6] = 1'b1;                            // M rises on an idle port
        #(200_000);                             // less than one visit later...
        busy[6] = 1'b1;                         // ... the marker marks it busy
        #(3_000_000);
        want(held, "still caught: BUSY was clear at the last visit");
        dial(6, 2); dial(6, 3);
        #(40_000_000);
        want(nclaim == 1 && claimed_slots == 8'b0100_0000, "and it claimed slot 06");

        $display("\n  %0d checks, %0d errors.  %s", chk, errs, (errs == 0) ? "PASS" : "FAIL");
        $finish;
    end

    initial begin #3_000_000_000; $display("  TIMEOUT"); $finish; end
endmodule

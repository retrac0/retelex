// marker -- the common control.  exch-marker.md 2-4, exch-network.md 3.
//
// A scanner, a probe, a sequencer and a diode matrix.  It holds nothing about
// the exchange: no route table, no translation, no record of where anything is.
// It reads what a port IS from the card's own word at every visit, hunts a
// class in fixed order from 00, writes two latches, and leaves.  Everything
// after those two writes is done by the ports.
//
//   first key   2-7   highway h; wait for the slot digit s; called = h s
//               0     hunt the operator          9  hunt an outside line
//               1     the network: 1 e b h s     8  cannot-complete
//
// The network part is exch-network.md 3's pulse flood, at the origin:
//
//   the first digit is in, and it is 1  -> seize a free trunk, pointed AT THE
//       CALLER, so their remaining digits go down it live as dial pulses.
//   our own e b      -> release the trunk and carry on locally
//   an e or b of 8/9 -> reserved: release, cannot-complete
//   a break within 128 ms of the seizure -> abandon (exch-monitor.md 3, rule 2)
//   the trunk's M rises -> it claimed; when the last digit is in, point the
//       caller at it and free the register
//   no claim 2 s after the last digit -> cannot-complete
//
// and at the far end, where the monitor -- not the marker -- decides:
//
//   a seizure arriving on a trunk -> hold it BUSY, listening to idle, so
//       backward A stays 0 and nothing has claimed yet
//   the monitor claims            -> re-point it with CLAIM set, so backward A
//       rises, and give a register the trunk's port: it is a line here now
`timescale 1ns/1ps

module marker #(
    parameter [2:0]   OWN_E     = 3'd2,
    parameter [2:0]   OWN_B     = 3'd2,
    parameter [5:0]   DIALTONE  = 6'o10,
    parameter [5:0]   NOGO      = 6'o14,
    parameter         HAS_NET   = 1'b1,
    parameter integer T_GUARD   = 128,      // ms: the origin's guard
    parameter integer T_CLAIM   = 2000      // ms: give up waiting for a claim
)(
    input            clk,
    input            rst_n,

    // the clock card
    input      [2:0] slotq,
    input      [2:0] tick,
    input            frame_stb,
    input            oct_stb,
    input            tick_1k,

    // the probe: M off the A highway, BUSY and the card's word off PB
    input      [7:0] ha,
    input            pb_busy,
    input            pb_word,

    // cable B, serial (exch-mainboard.md 2.3)
    output           sdata,
    output           sclk,
    output           wr,

    // the register
    output reg       reg_attach,
    output reg [5:0] reg_port,
    input            reg_busy,
    input      [3:0] reg_cnt,
    input            reg_dig_stb,
    input            reg_gone,
    input            reg_brk,
    output reg       reg_release,

    // the monitor
    input            mon_claim,
    input      [5:0] mon_port
);
    localparam C_NONE = 3'd0, C_LINE = 3'd1, C_OPER = 3'd2, C_SRC  = 3'd3,
               C_OUT  = 3'd4, C_TRUNK= 3'd5, C_DATA = 3'd6, C_CONF = 3'd7;

    // ---------------- scanner and probe ---------------------------------
    reg [5:0] scan;
    reg       m_acc, b_acc;
    reg [7:0] wsr;
    reg       p_m, p_busy;
    reg [7:0] p_word;
    reg [5:0] p_port;
    reg       visit;

    // With the control bus serial, /BLK is the block's own '138 on DST[5:3], so
    // the block that drives PB is the block THE SHIFT REGISTER NAMES.  A probe
    // taken while the marker was shifting a word for another block reads that
    // other block's BUSY and word.  `pv` follows the visit and is cleared by
    // anything that makes the reading untrustworthy; only a visit that survives
    // it may be acted on.  This interlock is new with the serial bus: the
    // parallel bus held BLK = one-hot(scan) continuously and probing was free.
    reg       pv, p_valid;
    reg [2:0] pb_blk;

    wire [7:0] wsr_next = {pb_word, wsr[7:1]};
    wire [2:0] p_cls    = p_word[2:0];
    // A trunk's option bits (ex-extensions.md 2.2): which way its link goes,
    // its glare bit, and whether the link is strapped (exch-network.md 3.3).
    wire [1:0] p_dir    = p_word[4:3];
    wire       p_g      = p_word[5];
    wire       p_n      = p_word[6];
    wire       p_free   = !p_busy && !p_m;

    // ---------------- the write queue and the serialiser ----------------
    // The sequencer's whole output is latch writes, and a write is one
    // sixteen-bit word on one wire.  The SAME serialiser also steers the
    // probe: /BLK is the block's own '138 on DST[5:3], so the block that
    // answers PB is the block the shift register names.  Between writes the
    // marker keeps a word there naming the block its scanner is visiting,
    // shifted with strobe low so that nothing is written.
    reg [13:0] wq [0:7];
    reg [2:0]  wh, wt;
    reg [1:0]  wst;
    reg        ser_req, ser_strobe;
    reg [5:0]  ser_dst, ser_src;
    reg        ser_bsy, ser_clm;
    reg        probe_dirty;
    wire       ser_busy;
    wire       w_pend = (wh != wt);

    ctl_write u_ser (.clk(clk), .rst_n(rst_n), .req(ser_req), .strobe(ser_strobe),
                     .dst(ser_dst), .src(ser_src), .bsy(ser_bsy), .clm(ser_clm),
                     .busy(ser_busy), .sdata(sdata), .sclk(sclk), .wr(wr));

    task push(input [5:0] pt, input [5:0] sr, input b, input c);
        begin wq[wt] = {c, b, sr, pt}; wt = wt + 1'b1; end
    endtask

    // ---------------- the hunt ------------------------------------------
    reg       hunt_arm, hunt_run, hunt_done, hunt_ok;
    reg [2:0] hunt_cls;
    reg [5:0] hunt_port;
    // exch-network.md 3: "one scan finds a free trunk in each other direction".
    // One pass, four candidates -- not four passes.
    reg       hunt_dirs;               // this hunt is the network's, not a class hunt
    reg [5:0] cand [0:3];
    reg [3:0] cand_ok;

    // ---------------- the sequencer -------------------------------------
    localparam M_IDLE=4'd0,  M_FIRST=4'd1,  M_SECOND=4'd2, M_PROBE=4'd3,
               M_HUNTW=4'd4, M_NET_E=4'd5,  M_NET_B=4'd6,  M_NET_H=4'd7,
               M_NET_S=4'd8, M_WAITCL=4'd9, M_SEIZE=4'd10;

    reg [3:0]  mst;
    reg [5:0]  caller, called, trunk;
    // exch-network.md 3.2: the trunks an origin seized, "a '574 a direction in
    // a bank a register".  On the claim it keeps the one whose M rose and
    // releases the others.
    reg [5:0]  d_trunk [0:3];
    reg [3:0]  d_held;
    reg [2:0]  dh, de;
    reg        claimed, guarding;
    // A claimed trunk keeps CLAIM set for the whole of the call it brought in:
    // "a trunk port with CLAIM set sends backward A = 1, steadily, until
    // release" (exch-network.md 3).  Every later write to this context's port
    // carries it, or backward A drops and every patch behind it releases.
    reg        ctx_clm;
    reg [15:0] tmr;

    wire [2:0] val  = (reg_cnt == 4'd10) ? 3'd0 : reg_cnt[2:0];
    wire       svc  = (reg_cnt == 4'd8) || (reg_cnt == 4'd9) || (reg_cnt > 4'd10);

    task nogo;                                     // cannot-complete, and let go
        begin
            push(caller, NOGO, 1'b1, ctx_clm);
            reg_release <= 1'b1; mst <= M_IDLE; claimed <= 1'b0; guarding <= 1'b0;
        end
    endtask

    task drop_trunk;                    // let go of every trunk this call holds
        integer k;
        begin
            for (k = 0; k < 4; k = k + 1)
                if (d_held[k]) push(d_trunk[k], 6'o00, 1'b0, 1'b0);
            d_held = 4'd0;
        end
    endtask

    task drop_others;                   // keep the one that claimed, release the rest
        integer k;
        begin
            for (k = 0; k < 4; k = k + 1)
                if (d_held[k] && d_trunk[k] != trunk)
                    push(d_trunk[k], 6'o00, 1'b0, 1'b0);
            d_held = 4'd0;
        end
    endtask

    task start_hunt(input [2:0] c);
        begin
            hunt_cls <= c; hunt_arm <= 1'b1; hunt_done <= 1'b0; hunt_ok <= 1'b0;
            hunt_dirs <= 1'b0;
        end
    endtask

    task start_dir_hunt;               // the network's: a trunk in every direction
        begin
            hunt_cls <= C_TRUNK; hunt_arm <= 1'b1; hunt_done <= 1'b0; hunt_ok <= 1'b0;
            hunt_dirs <= 1'b1; cand_ok <= 4'd0;
        end
    endtask

    // ---------------- the forwarder --------------------------------------
    // exch-network.md 3: a seizure arriving on a trunk is patched onward into
    // every OTHER direction, and the exchange forgets it -- no register, no
    // digits, nothing but two latches.  It runs on its own so that a transit
    // is never held up by a local call the marker is setting up.
    //
    // "A seizure is never forwarded INTO a strapped link, nor forwarded ONWARD
    // from one" (3.3) -- the n bit, which is how a ring is kept from circling.
    localparam F_IDLE = 2'd0, F_RUN = 2'd2, F_GO = 2'd3;
    reg [1:0] fst;
    reg [5:0] f_in, f_cand, f_start;
    reg [1:0] f_dir;
    reg       f_ok;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan <= 0; m_acc <= 0; b_acc <= 0; wsr <= 0;
            p_m <= 0; p_busy <= 0; p_word <= 0; p_port <= 0; visit <= 0;
            pv <= 0; p_valid <= 0; pb_blk <= 0;
            wh <= 0; wt <= 0; wst <= 0; probe_dirty <= 1'b1;
            ser_req <= 0; ser_strobe <= 0; ser_dst <= 0; ser_src <= 0;
            ser_bsy <= 0; ser_clm <= 0;
            reg_attach <= 0; reg_port <= 0; reg_release <= 0;
            hunt_arm <= 0; hunt_run <= 0; hunt_done <= 0; hunt_ok <= 0;
            hunt_cls <= 0; hunt_port <= 0;
            mst <= M_IDLE; caller <= 0; called <= 0; trunk <= 0;
            d_held <= 4'd0; cand_ok <= 4'd0; hunt_dirs <= 1'b0;
            fst <= F_IDLE; f_in <= 0; f_cand <= 0; f_dir <= 0; f_ok <= 0;
            f_start <= 0;
            for (i = 0; i < 4; i = i + 1) begin d_trunk[i] <= 6'd0; cand[i] <= 6'd0; end
            dh <= 0; de <= 0; claimed <= 0; guarding <= 0; tmr <= 0; ctx_clm <= 0;
            for (i = 0; i < 8; i = i + 1) wq[i] <= 14'd0;
        end else begin
            reg_attach  <= 1'b0;
            reg_release <= 1'b0;
            visit       <= 1'b0;

            // ---- probe -------------------------------------------------
            // M, BUSY and the card's word all arrive in this port's own cell:
            // the highways and both probe-bus commutators are addressed by SLOT.
            if (tick == 3'd4 && slotq == scan[2:0]) begin
                m_acc <= ha[scan[5:3]];
                b_acc <= pb_busy;
                wsr   <= wsr_next;              // one bit a frame, eight in a visit
            end
            if (oct_stb) begin
                p_m <= m_acc; p_busy <= b_acc; p_word <= wsr; p_port <= scan;
                p_valid <= pv;
                visit <= 1'b1;
                // A re-point cannot finish before the visit it governs -- the
                // word takes 31 us and the visit's first sample is 1 us in --
                // so a disturbed visit is REPEATED, not lost.  Without this the
                // first port of every block is never read, and 20 is the first
                // port of block 2.  It costs the scan about one visit a block.
                if (pv) scan <= scan + 1'b1;
                pv    <= 1'b1;                  // a fresh visit starts trusted
            end
            if (ser_busy || ser_req || pb_blk != scan[5:3])
                pv <= 1'b0;                     // ... and anything here breaks it

            // ---- the write sequencer -----------------------------------
            // A block turns over only when the scanner ACTUALLY advances.  Keyed
            // on oct_stb alone this re-fires on every repeated visit of slot 7,
            // and each re-point clears pv again: the scanner never leaves.
            if (oct_stb && pv && scan[2:0] == 3'd7) probe_dirty <= 1'b1;
            ser_req <= 1'b0;
            case (wst)
            2'd0: if (!ser_busy && !ser_req) begin
                      if (w_pend) begin
                          ser_dst <= wq[wh][5:0];  ser_src <= wq[wh][11:6];
                          ser_bsy <= wq[wh][12];   ser_clm <= wq[wh][13];
                          ser_strobe <= 1'b1; ser_req <= 1'b1; wst <= 2'd1;
                      end else if (probe_dirty) begin
                          // point the probe: DST names the block, nothing is written
                          ser_dst <= {scan[5:3], 3'd0}; ser_src <= 6'd0;
                          ser_bsy <= 1'b0; ser_clm <= 1'b0;
                          ser_strobe <= 1'b0; ser_req <= 1'b1;
                          probe_dirty <= 1'b0; wst <= 2'd1;
                      end
                  end
            2'd1: if (ser_busy) wst <= 2'd2;
            2'd2: if (!ser_busy) begin
                      pb_blk <= ser_dst[5:3];   // this is who answers PB now
                      if (ser_strobe) begin wh <= wh + 1'b1; probe_dirty <= 1'b1; end
                      wst <= 2'd0;
                  end
            default: wst <= 2'd0;
            endcase

            // ---- the hunt, in fixed order from 00 ----------------------
            if (visit && p_valid) begin        // a repeated visit is not a second port
                if (hunt_arm && p_port == 6'd63) begin
                    hunt_arm <= 1'b0; hunt_run <= 1'b1;
                end else if (hunt_run) begin
                    if (hunt_dirs) begin
                        // A free trunk in each direction.  The glare bit has one
                        // end of a link take the LAST it finds and not the first,
                        // so the two ends never meet in the middle.
                        if (p_cls == C_TRUNK && p_free && (!cand_ok[p_dir] || p_g)) begin
                            cand[p_dir] <= p_port;
                            cand_ok[p_dir] <= 1'b1;
                        end
                    end else if (!hunt_ok && p_cls == hunt_cls && p_free) begin
                        hunt_ok <= 1'b1; hunt_port <= p_port;
                    end
                    if (p_port == 6'd63) begin hunt_run <= 1'b0; hunt_done <= 1'b1; end
                end
            end

            // ---- the forwarder ------------------------------------------
            if (visit && p_valid && fst == F_RUN) begin
                if (p_cls == C_TRUNK && p_free && !p_n && p_dir != f_dir &&
                    (!f_ok || p_g)) begin
                    f_cand <= p_port; f_ok <= 1'b1;
                end
                // one scan, from wherever the seizure was seen, back to it
                if (p_port == f_start) fst <= F_GO;
            end
            if (fst == F_GO) begin
                // One found: patch it, two latches, and forget.  More than one
                // direction would fan out here, which wants the resolvers of
                // exch-network.md 3.2; with none, 3.2 says to patch into the
                // first direction found, as a chain would.
                if (f_ok) begin
                    push(f_cand, f_in,   1'b1, 1'b0);
                    push(f_in,   f_cand, 1'b1, 1'b0);
                end
                fst <= F_IDLE;
            end

            // ---- the claim coming back on a seized trunk ---------------
            // An origin that seized several keeps the one whose M rises.
            if (visit && p_valid && p_m && !claimed &&
                (mst == M_NET_E || mst == M_NET_B || mst == M_NET_H ||
                 mst == M_NET_S || mst == M_WAITCL)) begin
                for (i = 0; i < 4; i = i + 1)
                    if (d_held[i] && p_port == d_trunk[i]) begin
                        claimed <= 1'b1;
                        trunk   <= p_port;
                    end
            end

            // ---- the origin's 128 ms guard (exch-monitor.md 3, rule 2) --
            if (guarding && tick_1k) begin
                if (tmr == T_GUARD[15:0]) guarding <= 1'b0;
                else tmr <= tmr + 1'b1;
            end

            // ---- the monitor claims: this call is ours -----------------
            if (mon_claim) begin
                if (!reg_busy && mst == M_IDLE) begin
                    push(mon_port, 6'o00, 1'b1, 1'b1);   // CLAIM: backward A rises
                    reg_attach <= 1'b1; reg_port <= mon_port;
                    caller <= mon_port; mst <= M_FIRST; claimed <= 1'b0;
                    ctx_clm <= 1'b1;               // it stays claimed until release
                end else begin
                    // claimed, cannot complete -- the caller hears it at once
                    push(mon_port, NOGO, 1'b1, 1'b1);
                end
            end

            // ---- the caller went away ----------------------------------
            if (reg_gone && mst != M_IDLE) begin
                if (mst == M_NET_E || mst == M_NET_B || mst == M_NET_H ||
                    mst == M_NET_S || mst == M_WAITCL) drop_trunk;
                mst <= M_IDLE; claimed <= 1'b0; guarding <= 1'b0;
            end else if (guarding && reg_brk) begin
                // a break inside the guard: the far monitors cannot have seen
                // the rise cleanly, so abandon rather than risk a wrong number
                drop_trunk; nogo;
            end

            // ---- a digit ------------------------------------------------
            else if (reg_dig_stb) begin
                case (mst)
                M_FIRST:
                    if (reg_cnt == 4'd1) begin
                        if (HAS_NET) begin
                            push(caller, 6'o00, 1'b1, ctx_clm);  // dial tone off
                            start_dir_hunt; mst <= M_SEIZE;
                        end
                        else nogo;                       // no network card fitted
                    end
                    else if (reg_cnt == 4'd8)  nogo;     // spare
                    else if (reg_cnt == 4'd9)  begin start_hunt(C_OUT);  mst <= M_HUNTW; end
                    else if (reg_cnt == 4'd10) begin start_hunt(C_OPER); mst <= M_HUNTW; end
                    else if (svc) nogo;
                    else begin
                        push(caller, 6'o00, 1'b1, ctx_clm);    // dial tone off
                        dh <= val; mst <= M_SECOND;
                    end
                M_SECOND: begin called <= {dh, val}; mst <= M_PROBE; end
                M_NET_E:  if (svc) begin drop_trunk; nogo; end
                          else begin de <= val; mst <= M_NET_B; end
                M_NET_B:  if (svc) begin drop_trunk; nogo; end
                          else if (de == OWN_E && val == OWN_B) begin
                              drop_trunk; mst <= M_FIRST;      // our own code: carry on locally
                          end else mst <= M_NET_H;
                M_NET_H:  begin dh <= val; mst <= M_NET_S; end
                M_NET_S:  begin mst <= M_WAITCL; tmr <= 0; end
                default: ;
                endcase
            end

            // ---- the states that wait ----------------------------------
            else begin
                case (mst)
                M_SEIZE: if (hunt_done) begin
                             hunt_done <= 1'b0;
                             if (cand_ok != 4'd0) begin
                                 // Seize one free trunk in EVERY direction, all
                                 // listening to the CALLER, so their remaining
                                 // digits go down the flood live as they dial.
                                 for (i = 0; i < 4; i = i + 1)
                                     if (cand_ok[i]) begin
                                         push(cand[i], caller, 1'b1, 1'b0);
                                         d_trunk[i] <= cand[i];
                                     end
                                 d_held   <= cand_ok;
                                 trunk    <= 6'd0;
                                 guarding <= 1'b1; tmr <= 0; mst <= M_NET_E;
                             end else nogo;              // no free trunk anywhere
                         end
                M_HUNTW: if (hunt_done) begin
                             hunt_done <= 1'b0;
                             if (hunt_ok) begin
                                 push(caller,    hunt_port, 1'b1, ctx_clm);
                                 push(hunt_port, caller,    1'b1, 1'b0);
                                 reg_release <= 1'b1; mst <= M_IDLE;
                             end else nogo;
                         end
                M_PROBE: if (visit && p_valid && p_port == called) begin
                             if (called == caller || p_cls == C_NONE ||
                                 p_cls == C_TRUNK || p_busy || p_m) nogo;
                             else begin
                                 push(caller, called, 1'b1, ctx_clm);
                                 push(called, caller, 1'b1, 1'b0);
                                 reg_release <= 1'b1; mst <= M_IDLE;
                             end
                         end
                M_WAITCL: if (claimed) begin
                             drop_others;               // the ones that did not claim
                             push(caller, trunk, 1'b1, ctx_clm);
                             reg_release <= 1'b1; mst <= M_IDLE; claimed <= 1'b0;
                         end else if (tick_1k) begin
                             if (tmr == T_CLAIM[15:0]) begin drop_trunk; nogo; end
                             else tmr <= tmr + 1'b1;
                         end
                M_IDLE: if (visit && p_valid && p_m && !p_busy) begin
                            if (p_cls == C_TRUNK) begin
                                // a seizure arriving: hold it busy, listening to
                                // idle, so backward A stays 0 -- no claim yet
                                push(p_port, 6'o00, 1'b1, 1'b0);
                                // and hand it to the forwarder, unless it came in
                                // on a strapped link (exch-network.md 3.3)
                                if (fst == F_IDLE && !p_n) begin
                                    f_in <= p_port; f_dir <= p_dir;
                                    f_start <= p_port;
                                    f_ok <= 1'b0; fst <= F_RUN;
                                end
                            end else if (p_cls == C_LINE || p_cls == C_OPER) begin
                                if (!reg_busy) begin
                                    reg_attach <= 1'b1; reg_port <= p_port;
                                    push(p_port, DIALTONE, 1'b1, 1'b0);
                                    caller <= p_port; mst <= M_FIRST;
                                    claimed <= 1'b0; guarding <= 1'b0; ctx_clm <= 1'b0;
                                end
                            end
                        end
                default: ;
                endcase
            end
        end
    end
endmodule

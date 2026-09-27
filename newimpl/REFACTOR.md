# The markers and the network unit in 74HC — a refactor proposal

What in `mini_marker.v`, `marker.v` and `net_unit.v`, and the parts they
share, keeps the RTL from being drawn as 74HC boards; what each card becomes
when it is; the order to get there with the benches green at every step; and
what is Joel's to decide. The main line is a refactor: behaviour is unchanged
or moves only in time. Anything observable is listed in §6 as a decision.

> **Status: a proposal; nothing in `rtl/`, `tb/` or `faults.py` has changed.**
> What is **measured**:
>
> - Two bench pilots, in gitignored copies under `build/t68-*` (§4):
>   - The mini marker card with no queue, on board-form shared parts. All 18
>     benches are green at HEAD's counts (584 checks), and 18 faults behave as
>     designed.
>   - The network unit's four exact steps. They are bit-identical to HEAD on
>     the bus: every word and every `/WS` select lands on the same master
>     tick, on all five network benches.
> - The class marker's first step: identical on `tb_max`.
> - Nine `tb_net` experiments on HEAD, which settle how F03 and F05 hold.
>
> Sizes are yosys generic synthesis, a proxy. **Every package count is a hand
> count** (±15–20 %), and the unit's is not sketched.
>
> **Argued and not run:** the unit's stepping writer, the ribbon as levels, the
> class marker's write rows, the grid serialiser and the bank bus. Each has had
> an adversarial review against the RTL, and the fixes it found are part of the
> design (§3.4, §3.6).

---

## 0. In one page

**The cards as written are two to three times the board they describe.** Four
things are not the board:

- **a write queue**, which the queue's own header calls a model part;
- **copies of latches** the board holds once;
- **comparators where the board has counter taps**;
- **a probe with two port latches** the board does not need.

The model also leans on **one-tick strobes**, and each one forces a guard.

| (yosys, own logic + submodules) | FF bits | gates | 2:1 mux | the largest single cause |
|---|---|---|---|---|
| mini marker card, HEAD | 378 | 1648 | 288 | `ctl_queue(8,2)`: 148 / 375 / 246 |
| class marker card, HEAD | 342 | 1645 | 269 | `ctl_queue(8,2)` again |
| network unit, HEAD | 931 | 5150 | 1352 | `ctl_queue(16,5)`: 269 / 915 / 1211, **unbuildable at any count** (five pushes in a tick) |

**Five moves** fix it. Each is what a document already says the board does.

1. **No queue: every write is a row of the sequencer, and a row's only exit is
   `sent`.** `bus.md` §5: "on a board a master's sequencer holds until its word
   is away, and there is no queue." DRAIN, `bus_idle`, `y_nogo`, 11 `room`
   guards in the mini, 14 in the class marker and the unit's popcounts all go.
   "Do not return to IDLE with writes queued" stops being a rule and becomes the
   structure.
2. **The comment is the circuit.** A word table, one row per write state, is
   literally the select logic of six '153s onto the '165s' parallel inputs.
   CLM is one rule, where the files now spell it out eight times. One region is
   one package, counted honestly.
3. **The shared sub-circuits take their board form.**
   - The probe is one '74 on SCAN, or a '688 and a '74 when pointed.
   - `word_rx` has one window '161.
   - Every timer is a ripple counter clocked by TICK, with a first-reach decode
     of its value.
4. **Every copy is deleted.**
   - The caller is the register's `port`.
   - The highway is read out of the store.
   - The unit's sweep writes into its owner's bank.
   - `st` is the '164 ring its comment already describes.
   - The monitor cells sample from the unit's own probe.
5. **The unit writes through a stepping writer.** A '148 picks an owner and a
   '161 steps the owner's direction mask, one word at a time. It has the six
   guards the adversarial review found (§3.4).

| card | 74HC packages, as written → after (hand) | two-layer Eurocards (30–40 DIPs) | measured |
|---|---|---|---|
| mini marker (`top_net`) | ≈140 → **≈79** | 4–5 → 2–3 | pilot: 378/1648/288 → **153/844/38**, all benches green |
| mini marker (`top_min`) | ≈109–117 → **≈70** | 3–4 → 2 | `top_min` whole: 555/2108/309 → **330/1304/59** |
| class marker (`top_max`) | ≈101–104 → **≈70** | 3 → 2 | first step: identical trace, 116 → 108 own FF |
| network unit (NMON = NRES = 2) | ≈334 → **≈165**, ≈132 with the bank bus | 9–12 → 5, 4 with the bank bus | exact steps: own 508/3755/137 → **450/3022/99**, bit-identical |

`top_net`'s common control goes from about 14 cards to about 7. The pilots'
RTL reads as the documents' tables: §3.2 shows the mini's word table.

**What it costs.**

- 42 of the 52 faults anchor in these files and must be re-expressed, each in
  the step that moves it. This was done for all the piloted faults.
- `mk_state` widens to 4 bits in seven bench and site files.
- Six `ovf` checks become vacuous.
- F03's form changes: today it holds by one master tick (§1.8).

**What is Joel's** is listed in §6. There are twelve questions. The ones that
shape the work are:

- the ribbon as levels;
- SCLK from `SLOT1`;
- whether `net_unit` becomes board modules;
- the bank bus;
- the fix for the mini marker's lockout with `/NET` low.

---

## 1. Why the RTL is hard to build today

### 1.1 The queue

`ctl_queue.v` is a FIFO with a same-tick multi-slot push.

- **On a marker** it is larger than the marker itself: 148 FF against the mini
  marker's own 69. Built literally it would be eight '670s plus pointers,
  about 19 packages.
- **On the unit**, NP = 5 puts five words into a one-write-port memory in one
  tick, which no part does.

The queue also shapes the sequencers:

- **Room guards.** Every write site first checks `room >= N`: 11 sites in
  `mini_marker.v`, 14 in `marker.v`, and 5 in `net_unit.v` with four popcounts
  feeding them.
- **The mini re-reads.** When there is no room on the tick a read completes,
  it re-issues the read (`mini_marker.v`: "no room: rd_done is gone, so read
  again").
- **The class marker reads ahead.** It demands `room >= 5'd4` before issuing a
  read, so the connect can be pushed on the read's one-tick `rd_done`.
- **DRAIN** exists only to wait for the queue to empty.
- **The markers push, and the queue orders.** Both markers push a connect's two
  words in one tick, and the unit pushes a CLAIM and four drops.

### 1.2 Copies

- **The caller's number is held four times.** Copies:
  - `pulse_reg.port`;
  - the marker's `caller`;
  - `attach_port` (yosys merges it with `caller`);
  - the unit's `caller`.
- **The read port is held twice.** `word_rx` holds its own; each card holds
  another.
- **The mini copies the first digit into `hwy`** while the store still holds it.
- **The class marker copies `called` into `h_num`**, and it is never different.
- **The sweep's answer is copied three times.** On the unit, `h_cand` →
  `o_cand` → `d_trunk`, and `h_cand` → `f_cand` → `rs_leg`: 72 FF of copies,
  because the sweep clears `h_cand` at its next start.

### 1.3 Comparators where the board has taps

Every timer is a counter compared against a parameter:

- `pulse_rx`: three 9-bit equalities and a `>=`;
- `pulse_reg`: a 16-bit `nd_t` with `== NODIG-1` and `>= SETTLE`;
- the unit's `tmr`: 16 bits, with `< t_guard`, `>= T_KEY` and `>= T_CLAIM`;
- `cls_ms`: `> T_ARM+1`;
- the unit's `wcnt`: `== WAIT-1`;
- the class marker's `wgap`: `>= WALK`, saturating.

**On a board each is a ripple counter and an AND of taps.**

### 1.4 The probe

`probe.v`'s header counts "one 74HC688, a quarter of a '08 and half a '74".
The RTL holds 19 flip-flops: `acc_port` and `port_q` are two 6-bit latches the
board does not need. The pair is republished at the next frame edge instead of
at the capture, so the port must be carried a frame. `top_net` fits six probes,
which is 96 FF of artefact.

### 1.5 The unit's comparators

About 30 six-bit compares run against the probe's port:

- `mine` alone has 20 at NRES = 2;
- the claim watch;
- the resolver watch;
- the confirm pass;
- the monitor cells, each with its own probe and an arming '688.

`st[63:0]` is written by index. Its comment says "eight '164", and the indexed
form costs 516 gates the ring does not (measured, §4.3).

### 1.6 One-tick strobes

Each one-tick strobe forces a guard on the receiving side. From the unit, the
markers receive:

- **`u_nogo`** is caught in `y_nogo`, because the marker may lack room that
  tick.
- **`u_local`** is followed by `hold <= 2'd3`: three ticks for a restart that
  crosses two registers.
- **The refusal** cannot take the tick of `u_local`, `u_done` or `u_nogo`, nor
  of `rd_done`, because it is a branch in front of the `case`.

The unit's side has its own:

- **`flood_go`** is sampled only in `N_IDLE`, which is safe only by an argument
  that two events do not coincide. `STYLE.md` §5 forbids such arguments.
- **`att_ack`** is answered in exactly one tick, with zero slack.

### 1.7 Comments that undercount

`STYLE.md` §2 says a reader counting packages from the comments must get the
board. The pilots found the headers wrong, measured against their own lists:

| sub-circuit | the header says | the list or RTL shows |
|---|---|---|
| probe | half a '74 | 19 FF |
| word_rx | "about six" and "seven and a half" | eight ICs and a FET |
| pulse_reg | "about fourteen" | 13 |
| ctl_write | "two '165 and a little sequencing" | about 9 |
| word_dec | "a few gates" | a '30 and a '4078 as well |

`mini_marker.v`'s comments name about 20 packages of a card of about 140.

### 1.8 Two double holds are thinner than README §4 says

Measured on HEAD, `tb_net`, nine experiments (§4.1):

**F03 holds by one master tick.**

- Today's three-patch F03 is GREEN, 88/0.
- Make the mini's queue start its word **one tick sooner**. It then passes
  alone (88/0), but with F03's mutation it is **RED**, 2 errors: "B's trunk
  listens to 03, not 00".
- **Why:** the marker's push-to-start is two ticks, and the unit's
  `att_ack`-to-`/UREQ` is one.
- **Consequence:** every stepping writer in this proposal acks the refusal at
  its own `sent`, and every one of them would turn today's F03 red. The mini
  pilot does (RED, 2).
- **The one-line form** holds by the full 640-tick `WAIT`: GREEN on HEAD, on
  the fast queue and on the pilot. It is `CL_WAIT` raising `att` at the claim
  decision while the CLAIM is still queued and `/UREQ` is already low. Its
  F03b (plus a marker deaf to `/UREQ`) is RED, 5 errors, from the named check.

**F05's second hold is the mini's `S_TAKE`, and in one window it is the only
hold.**

- With TAKE removed (the caller taken at READ's result) the bench passes 88/0,
  and dial tone comes 0.88 ms sooner. Add F05's mutation and it is **RED**,
  10 errors: "B's marker did NOT take the trunk's M as a call". So the common
  idea "the held read result retires `S_TAKE`" is withdrawn: **TAKE stays.**
- **A coverage hole.** With F05's mutation on HEAD, B's marker does take
  trunk 11 as a caller, in scenario 2's release tail. It writes `11←01` at
  2315.156 ms and `11←00` at 2378.0 ms: 40 words from B's marker where HEAD
  has 38 (the trace diff). No check looks there. There, READ's word test is
  the only hold. A check in scenario 2 would turn F05 red, and "held twice" would
  narrow to F03 (§6, Q12).

---

## 2. The idioms: one form a construct

| construct in the RTL | 74HC form | where |
|---|---|---|
| port == a held port, at the probe's turn | one '688, the held port on A and SCAN on B, read on the fresh tick. **SCAN is the port on the fresh tick**: no `port_q` latch | every card |
| compare with a constant | a gate on the bits (`'30`, `'4078`, `'11`), or the counter's RCO | `wq == 77`, `is_trunk`, `k_none` |
| timer ≥ N | a '4040 (12 stages) or '4020 (14) clocked by TICK (SCAN5's fall), cleared by the event that starts the time; **the first reach of the AND of N's one-bits is exactly N**, so any N costs at most one '30 and a power of two costs one tap. **A '4020 has no Q2 or Q3**: values with bit 1 or 2 set go on a '4040 or are model-only | `pulse_rx`, `pulse_reg`, `tmr`, `cls_ms`, `wgap`, the unit's grant |
| a saturating count | the count enable is the inverted terminal decode (RCO, or the clock gated by the top tap) | `pulse_rx` `cnt`, `wgap` |
| a port counter 01..77 that wraps | a '161 pair whose 77 decode (RCO·Q4·Q5, a third of a '11) loads 000001 | the walk `wq`, the hunt `p` |
| stride +9 | a '161 pair loaded from a '283 pair with B strapped to 001001 | the sweep `h_idx` |
| a bit a port | eight '164s recirculating one step a port turn, read at the head | the unit's `st` |
| first free of N cells | a two-gate chain at N = 2, or a '148 and a '138 up to 8 | monitor cells, resolvers |
| a write word | **no word register**: the '165s' parallel inputs are the latch. DST and SRC are '153 buses selected by the row's decode; a tone is an address 00–03, so SRC's top four bits are grounded; BSY and CLM are gates on the decode | every master |
| the sequencer | state in a '175 (4 bits), decoded by a '154; each row waits for **one** condition; `STATE[3]` means "a word is owed" | the markers; the unit's machines |
| a fact for the other card | a level held until the other side has acted (`register.md` §3's own rule); a strobe only between cards on one clock, named `_stb` | the ribbons |

Two model artefacts stay and are named where they are used:

- **The 4.096 MHz tick** that clocks every sequencer. No common-control card
  receives it (Q9).
- **`ctl_write`'s ÷32**, until Joel decides on SCLK (Q2).

---

## 3. The cards after

### 3.1 Shared sub-circuits

| module | after | class | measured |
|---|---|---|---|
| `probe` | at the capture strobe a '688 compares `port` with SCAN and a '74 takes `/HA` and `/HB`; `fresh` a tick later; `port_q` is an assign of SCAN, valid on `fresh`. Tied to SCAN it is one '74 and the '688 is not fitted. Port list unchanged | **timing-only**: `fresh` 28 ticks earlier in the same frame | 19 → 3 FF; all 18 benches green |
| `word_rx` | one '161 loaded with 8 at any select and counting **up** to RCO; a `mine` flop for our read. Port list unchanged | **none**: `word`, `tie` and `ltu` traces tick-identical | 25 → 22 FF |
| `pulse_rx` | a '4040 on TICK, stopping at CLR; HIT, ID, CLR and SETTLE are first-reach decodes of N; `steady` is a '74 | **timing-only, one tick** (sampled form) | 19/90 → 21/86 |
| `pulse_reg` | `nd_t` a '4020 with a '30 at NODIG; `settled`'s `>= SETTLE` a '74 half. Ribbon unchanged | timing-only, one tick | 45/220 → 44/148 |
| `ctl_write` | unchanged until Q2; then SCLK = oe·!last·SLOT1, WR a SLOTQ cell decode, the unit's grant after 18 steps | — | grid sketch 34/113 → 24/75 |
| `ctl_queue` | leaves every card; moves to `tb/` as the bench writer of `tb_word`, `tb_tie` and `tb_ltu` | — | — |

**The probe step reaches the unit in two ways**, both timing-only and both
invisible to every check:

- Every write after a sweep moves **+36 ticks**, because `H_CONFIRM`'s 64
  samples start one port later.
- In `chain` C, one `/WS` select reorder: the classifier now reaches the
  unit's one reader before the sweep's next step.

A timer tap can be taken two ways. **Taken combinationally** on the registered
count, it is exact in the model; the unit pilot did this. **Sampled one tick
later**, it is what a board does; the mini pilot did this, and it is +1 tick.
Use the sampled form on every card.

### 3.2 The mini marker

**Region order** is the same in both markers:

1. the bus front end;
2. the register;
3. the digits;
4. the call's latches;
5. the word table;
6. the sequencer.

**States** are 4 bits, with IDLE = 0 and `STATE[3]` meaning "a word is owed".

- **Deciding states:** IDLE, READ, TAKE, KEY, SLOT, PROBE, WATCH, YIELD.
- **Write rows:** W_TAKE, W_OFF, W_FAIL, W_ABANDON, W_CONN_A, W_CONN_B, W_FREE.

The word table, from the pilot (`build/t68-mini/newimpl/rtl/mini_marker.v`):

```
    //              DST      SRC      BSY   CLM        then, at `sent`
    //  W_TAKE      called   01        1    0          KEY
    //  W_OFF       caller   00        1    ctx_clm    SLOT; on key 1 the flood,
    //                                                 the restart, YIELD
    //  W_FAIL      caller   03        1    ctx_clm    release, IDLE
    //  W_ABANDON   caller   00        0    0          release, IDLE
    //  W_CONN_A    caller   called    1    ctx_clm    W_CONN_B
    //  W_CONN_B    called   caller    1    0          restart, WATCH
    //  W_FREE      called   00        0    0          gone: release, IDLE;
    //                                                 else W_FAIL
    //  refusal     att      03        1    1          att_ack
    wire d_called = (state == W_TAKE) || (state == W_CONN_B) || (state == W_FREE);
    ...
    assign w_dst = (own_rf || !seq_w) ? u_att_port : (d_called ? called : caller);
    assign w_src = own_rf               ? NOGO   :
                   (state == W_CONN_A)  ? called :
                   (state == W_CONN_B)  ? caller : tone;
    assign w_bsy = own_rf || !((state == W_ABANDON) || (state == W_FREE));
    assign w_clm = own_rf || (ctx_clm && w_bsy && !d_called);
```

**What goes:**

- **The queue**, `push_v`/`push_d`, every room guard, DRAIN and `y_nogo`.
- **The `caller` and `r_port` copies.** `caller` is `pulse_reg.port`, and
  `attach_port` is the DST mux at the attach tick.
- **`hwy`**: the highway is read out of the store's slot 0, which nothing
  restarts between the two digits.
- **`rd_port`**: the reader reads `called`.
- **`rd_caller`**: `r_busy` says whether a read is for a caller or a number.

**What stays:**

- **S_TAKE**, as F05's second hold (§1.8).
- **The `called == caller` '688.** The probe would refuse one's own number too,
  but that is an argument about a hang-up at the probe instant, not a proof.
- **`hold`, and the ribbon's strobes**, until Q1.
- **The probe re-point and the tap**, until Q11.

**The writer** drives today's `ctl_write` with a **one-tick** request:

- It is raised only while `!t`. `t` is set on that edge (it is the '244
  enable) and cleared at `sent`, which is `busy`'s fall.
- It never starts on the tick `sent` is seen.
- Its start samples `/UREQ` high.

A level request would repeat the word: `ctl_write` reloads while `req` is
high, measured at 5 WRs in 3000 ticks.

**The claim refusal is a second requester.** It is:

- asked for only while no row is live and not in WATCH, so it can never split
  a pair;
- given the serialiser first;
- acked at its own `sent`.

`att_take` is gated `!rf` and allowed only in IDLE and TAKE.

**BOM** (the pilot's header; a '74 half counts as a half):

| region | contents | packages |
|---|---|---|
| bus front end | probe 2.75, address '157 ×1.5, TICK 1.25, `word_rx` 8 + 2N7002, `ctl_write` 8, start '74 ×2.5, '244 | ≈25 |
| register | `pulse_reg` 13, `pulse_rx` 7, its probe 2.75 | ≈23 |
| digits | '08 ×1.5, '85, half '21, third '27 | ≈4 |
| call's latches | `called` '174 + '157 ×1.5, `ctx_clm`/`keyed` '74, `hold` '74, the '688 | ≈6 |
| word table | DST '153 ×3, SRC '153 ×3, BSY/CLM gates, the refusal's half '74 | ≈8 |
| sequencer | '175, '154, ≈8 packages of next-state gates, ribbon '74 ×3 | ≈13 |
| **total** | `top_net`; on `top_min`, no `word_rx` and no network ribbon: **≈70** | **≈79** |

The "≈8 packages of next-state gates" is the soft figure: yosys puts the
mini's own logic at 347 gates, and no gate map was drawn.

### 3.3 The class marker

**Step one, measured `none` on `tb_max`** (a byte-identical trace: 110
cable-B words and 5920 selects):

- The probe goes. `s_m` and `s_b` are taken at the card's own select,
  `a_stb·ws_pd`, the instant the probe sampled.
- The `p_port == rd_port` '688 goes.
- `called`, `h_num` and `h_p` become **`num`** (the number dialled, a '174)
  and **`p`** (the port in hand, then the hunt pointer, a '161 pair).
- It saves about 5.5 packages; marker own logic goes from 116 to 108 FF.

**The hunt needs both registers.** Using `called` as both the number and the
pointer fails one of two ways:

- If the pointer, `tb_max`'s "0 → 04, then 05" goes red.
- If the number, WATCH's free word after an answers-to hunt frees the
  **dialled** port and leaves the **found** one BUSY for good.

`tb_max` cannot see the second failure. A scratch bench, `tb_mhunt`, can:

- 20 and 21 are talking;
- 22 dials 21, and the hunt finds 26, which answers to 21;
- 22 hangs up at the connect.

The mutant fails 2 of 6. Its six checks should join `tb_max` (92 → 98).

**Step two is the mini's rows**, text-aligned, plus the class-only ones:

- W_NAIL uses DST/SRC's fourth inputs, `nail_p` and `nail_d`, so it costs no
  mux.
- W_CONN_A is `one_way` for a source.
- W_FAIL's tone is 02 when `h_ans·own_busy`.

Its terms:

- **`w_state` stays HEAD's**, so the walk's selects do not move.
- **The nail memory stays**: removing it is observable (Q6).
- **The walk's take**:
  `w_take = w_done·IDLE·!att_take·!rf·!r_busy·w_ask·((d_caller·(d_pri+!pwait))+d_cnail+d_out)`,
  with the first word waiting in W_TAKE for `/UREQ`. That is today's
  behaviour.
- **`make skel`** (twenty lines of Python run by `make lint`) extracts the
  `COMMON`-tagged regions of both markers and fails if they differ. The class
  marker's network half then cannot drift from the mini's, which five
  benches cover.

**`tb_maxnet` comes first.** No bench runs the class marker with the unit
fitted (`marker.md` §7), so a two-site `top_max` bench must come before step
two. The review listed the ten cases it must cover (§4.4).

**BOM ≈70** (≈64–78), counting `num` + `p` and the nail memory. Soft figures:
next-state gates, and '74 halves.

### 3.4 The network unit

**The exact steps are measured `none`** (§4.3): identical traces on all five
network benches, a silent shadow checker, and the same glare try. They keep
the queue, `WAIT` and the ribbon.

- **S1 — `st` as the '164 ring.** `if (sp_fresh) st <= {st[62:0], sp_m && (sp_busy || cls_seen || st_head)}`.
  −516 gates.
- **S2 — the sweep writes into its owner's bank.** `h_cand`, `o_cand` and
  `h_n` go (and the dead `h_g`). The end test is `h_idx + 9 == 01`. `mine`,
  the confirm pass and the claim watch share 8 compares instead of 16.
  −55 FF.
- **S3 — the timers as taps.** `tmr` is a '4020 with the guard on a jumper to
  Q8–Q11, and T_KEY and T_CLAIM are '30s at 5000 and 2000. `cls_ms` is a
  '4040 at 18 = Q5·Q2.
- **S4 — the monitor cells sample from the unit's probe.** Each cell is a
  '688 (`sp_port == m_port`), which is both its sample strobe and its arm,
  plus a '74 half. Its digit test is monitor-rules' 4-bit code compare. The
  two cell probes go.

In sum, own logic goes from 508/3755/137 to 450/3022/99, and the hierarchy
from 931 to 835 FF. By hand that is about −46 to −53 packages.

**Then the stepping writer.** It goes through `ctl_queue(2,1)` first, so that
`un_ovf` stays a live check, then drives `ctl_write` directly. A '148 picks
the owner in today's order (claim > classifier > origin > forwarder >
resolvers > events). A '175 latches the owner, and a '161 steps the owner's
direction mask. It removes the queue, `push_v`/`push_d`, the popcounts and
`room`.

**The adversarial review found six ways this breaks**, reasoned against HEAD's
lines and each fixed by a rule:

1. **`taken` is the '165 load, not the pick.** Otherwise a one-word batch
   (UNHOLD, an event) is read after its machine has moved on. The classifier
   has then overwritten `cls_port`, so the hold is never written away and
   the trunk stays BUSY for good.
2. **`dn` is the last word's `sent`, and `/UREQ` = any request | batch
   latched | word in flight.** Otherwise `/UREQ` rises between words or during
   the last one. The result is a `b_clash`, a CLAIM overwritten by the
   refusal, or a marker abandon passing a waiting `N_DONE`.
3. **Pick only when no batch is latched, and clear `rs_act` with `rs_busy` at
   `dn`.** Otherwise a resolver freed by the claim batch is picked again on
   the same edge and rewrites the trunk without CLAIM.
4. **Latch the claimed resolver's index at the pick**, or compare `rs_in` with
   `att_port`. Otherwise `rs_mine` goes blank the tick after the pick, and the
   forward's legs are never dropped.
5. **`F_WRITE` honours `f_cancel`.** Otherwise an UNHOLD that wins the
   priority is followed by the forward's legs, which re-seize a dead trunk
   with no edge to release it. HEAD has the same hole for 1–2 ticks; the
   writer would widen it to a batch wait.
6. **Keep `caller` and `trunk` through this step.**
   - `caller`: a marker release inside a batch would otherwise change `r_port`
     under the seize words.
   - `trunk`: `EV_GLARE` must name the right trunk. Otherwise gate `N_WANT`'s
     sweep start on `!ev_glare`; never hold `N_IDLE`, which would lose
     `flood_go`.

**Then the per-region structure.**

- **One always block per region.** Verilator's MULTIDRIVEN then proves that no
  region writes another's register. Today that rests on unstated
  later-assignment-wins at the claim's push.
- **Modules for the sub-circuits the card repeats**, if Q3 says so: a monitor
  cell, a leg bank, a resolver.

**The compares stay parallel.** They are pruned to about 18 '688s, each drawn
beside the latch it reads, with `mine` an OR of bank hits (today's coverage,
so F35 stands).

**The bank bus is optional, the last step, and piloted** (Q4). It is three
8-cell buses on SLOTQ, one '688 each, with banks in '670. The review found
three fixes it needs first:

- `port_q` latched at the capture;
- `better` and the flag clears registered before a separate write strobe;
- the '670 write-through is otherwise a runt write.

It is worth about 30 packages and one card. It moves every watch to the
frame's end.

**BOM ≈165** (150–185) with parallel '688s, ≈132 with the bank bus. Each
extra monitor cell adds about 10.5 packages; each extra resolver about 18, or
7–9 on the bank bus.

### 3.5 The register card (`top_max`)

The same `pulse_reg` with the taps: ≈21–35 → ≈17–20 packages. It makes its own
TICK from SCAN, where `top_max.v` now feeds it `exch`'s. `digits[15:12]` is on
the ribbon and in a '175, and nothing reads it (Q11).

### 3.6 The ribbon as levels (Q1)

- **`/FLOOD`** is the marker's YIELD decode, replacing `flood_go`.
- **`OUT[1:0]`** means working, local, done or nogo. It is raised only once
  the unit's own last word for the call is away, and held until `/FLOOD`
  falls.
- **The unit's `restart` goes.** On `local` the marker restarts the register
  itself and stays in YIELD until `r_ndig == 0`, which replaces `hold`.
- **`att_ack` becomes four-phase**, and the unit raises `att` again only with
  `att_ack` low.

This removes `y_nogo`, `hold`, the refusal's strobe guards and the `N_IDLE`
coincidence argument. The unit ribbon goes from 15 conductors to 13.

The review found five fixes and they are part of the design:

- every `N_END` exit waits for `/FLOOD` to fall, including abandon;
- nothing takes the marker out of YIELD but the end of its part in the call;
- the restart on `local` is held until `r_ndig == 0`, or `e` is read as `h`;
- the unit's claim pick is gated on `!att_ack`;
- `OUT = nogo` does not wait for the `EV_NOTRUNK` event.

`network.md` §3.6's table changes, by gist to whoever holds the spec.

---

## 4. The evidence

The pilots live in gitignored copies. Paths are under `newimpl/build/`.

### 4.1 HEAD experiments (`t68-head/exp`), all `tb_net`

| run | change | result |
|---|---|---|
| f03a | today's F03 | 88/0 GREEN |
| fast | the mini's queue starts one tick sooner | 88/0 |
| f03d | fast + today's F03 | **88/2 RED**: "B's trunk listens to 03, not 00…", "A20 hears B's cannot-complete…" |
| f03b | one-line F03 | 88/0 GREEN; only the refusal moves, 3 ticks earlier |
| f03bfast | one-line F03 + fast | 88/0 GREEN |
| f03c | one-line F03 + marker deaf to `/UREQ` (F03b) | **88/5 RED** |
| notake | no S_TAKE: take at READ's result | 88/0; the first dial tone 0.88 ms sooner |
| f05nt | no S_TAKE + F05 | **88/10 RED**: "B's marker did NOT take the trunk's M as a call" |
| f05head | today's F05 | 88/0 GREEN, but B takes trunk 11 as a caller in scenario 2's release tail (§1.8) |

### 4.2 The mini marker card pilot (`t68-mini/newimpl`)

- **Benches:** all 18 green at HEAD's counts: clock 8, fabric 9, ctl 17, ha
  13, probe 9, dial 36, mini 42, debug 18, line 23, word 26, tie 16, ltu 30,
  net 88, chain 32, lnet 37, lchain 48, lfull 40 (glare at try 0, as HEAD),
  max 92.
- **Lint:** clean on all 24 modules.
- **Bench edits:** `mk_state` is 4 bits in seven bench and site files, and
  `tb_probe` latches the port on `h_fresh` (the check text is unchanged).
- **Traces:**
  - `mini`, `max`, `lnet`, `lchain` and `lfull`: the same order per exchange.
  - `word`, `tie` and `ltu`: tick-identical.
  - The `dt` classes are all explained: −29 and −28 (the probe and the
    missing queue tick), +1 (the sampled tap), +36 (post-sweep), and whole
    passes where a stimulus is anchored on a marker event.
- **Order differences:** three cross-master swaps (net A, chain A, chain B).
  The marker and the unit react to the same `r_nodig` or `r_gone`, and the
  pilot's writer is one tick quicker than the queue. The swapped words are on
  disjoint ports. Adding back HEAD's queue tick (`exp1`) restores HEAD's order
  exactly. The unit's `/UREQ` fix (§3.4, rule 2) is the right cure, not an
  artificial tick.
- **Faults** (re-anchored ones marked \*):
  - F14\*, F21\*, F37\*, F38\*, F39\*, F26\*, F03b\*, F10, F36, F09 and F05b
    are RED from named checks.
  - The bite checks F12, F18 and F35 are RED.
  - F05 is GREEN.
  - The one-line F03n is GREEN, and its F03bn is RED.
  - Today's three-patch F03 is **RED**, as §1.8 predicts.
- **Size:**
  - the card: 378/1648/288 → 153/844/38;
  - the mini's own logic: 69/691/26 → 26/347/20. Of the 26 FF, 5 are today's
    `ctl_write` handshake, which the grid serialiser removes.

### 4.3 The unit's exact steps (`t68-unit/s4`, shadow in `s4x`)

- **Traces:** identical to HEAD, tick for tick, on net (2398 lines), chain
  (968), lnet (648), lchain (853) and lfull (1574; glare at try 0 as HEAD).
- **Shadow checker:** it runs HEAD's form of each step beside the pilot and is
  silent on all five benches. Two mutant copies proved it live.
- **Faults:**
  - RED from named checks: F07\*, F08\*, F19\*, F20\*, F11, F27, F12, F35.
  - F19b, the pilot's own fault for "the sweep writes only its owner's bank",
    is **GREEN**: no bench checks which port the origin's DROP names. A check
    is needed before S2 lands (chain scenario 4 continued).
- **Size**, own logic per step:

  | step | FF | gates | 2:1 mux |
  |---|---|---|---|
  | HEAD | 508 | 3755 | 137 |
  | S1 | 508 | 3239 | 65 |
  | S2 | 453 | 3026 | 112 |
  | S3 | 447 | 2981 | 114 |
  | S4 | 450 | 3022 | 99 |

- **T_CLAIM 250** needs Q2, which a '4020 lacks. The pilot decodes it in the
  model and names it model-only (Q8).

### 4.4 The class marker (`t68-adv2`)

- **Step one:** `tb_max` 92/92, byte-identical trace.
- **`tb_mhunt`:** HEAD 6/6 and step one 6/6. The mutant that frees `num`
  instead of `p` fails 2.
- **What `tb_maxnet` must cover:**
  1. a flood through the class marker, and a hang-up in YIELD;
  2. a claim taken, with CLM on every word;
  3. a claim refused after the CLAIM, never in WATCH;
  4. the walk with `/UREQ` low;
  5. the walk reading a flood trunk before the unit's hold;
  6. `/WS` shared by the walk, the hunt, the classifier and the sweep;
  7. `u_local`;
  8. a claimed trunk dialling a busy number that has a free answers-to port;
  9. PWAIT with a claim pending;
  10. WATCH-gone and nodig on a claimed caller.

### 4.5 The mini marker's lockout with `/NET` low (`marker.md` §7)

**The mechanism is confirmed.** READ sends a port whose word says trunk or
none back to IDLE. The read ends eight frames after its select, so IDLE's
next offer is port p+8. Then p comes round again. So p is read every other
pass, and **p+1 to p+7 are never offered**.

Measured on a scratch `tb_stuck` (20 off-hook with its word pin open):

| option | lifters served | cost | behaviour |
|---|---|---|---|
| HEAD | 4 of 5 get nothing in 60 ms | — | — |
| (c) **resume after p** (a flop: take no offer until p's next turn) | **5 of 5 within 4 ms** | ½ '74 + a gate | all five network benches green; F05 GREEN; F05b RED 23 |
| (a) a bit a port ('164 ring) | 5 of 5 within 3 ms | ≈9 packages | a port that becomes a line while off-hook is locked out until it hangs up |
| (b) the class marker's walk | — | ≈5.5 packages | every network bench lifts, waits 10 ms and dials; with up to 252 ms to dial tone they all go red, and 65 lifts must be rewritten |

A random frame model of 150 sets of 2–6 stuck ports agrees. (c) starves none
of them, with a worst wait of 15 ms. A skip-once variant starves 128.

---

## 5. Order of work

Every step is one commit. It stages only its own paths, re-expresses the
faults it moves, and shows them RED from a named check. Wall times assume
one network bench at a time under the 3 GB cap: `net` and `lfull` take
8–25 min under load, `max` 6–16 min, `mini` 2–10 min.

| step | content | class | gate |
|---|---|---|---|
| **S0** | Harden `faults.py`: verdicts RED(check) / GREEN / TIMEOUT / BROKEN / NOT-APPLIED; exit non-zero unless the table is the contract's; ROOT from the environment; the worker count an option; a `--check` mode that only applies anchors; harness timeout 3000 s (a loaded `net` took 2176 s). Replace F03/F03b with the one-line forms and change README §4's prose | none | `--check` 0 NOT-APPLIED; F03 GREEN, F03b RED on HEAD |
| **S1** | The unit's exact steps S1–S4 (§3.4), with F07, F08, F19 and F20 re-anchored; add the DROP-names-B13 check for F19b | none | five network benches, identical traces; the eight unit faults RED |
| **S2** | Shared sub-circuits (§3.1): `word_rx` (none), then the taps (one tick), then the probe (timing) | as listed | all 18 benches; traces diffed per card; F10, F26, F36, F38, F39 RED |
| **S3** | The mini marker card (§3.2) | timing-only | all 18 benches; F09, F14, F21, F37, F05b, F03b RED; F05 GREEN; bites F12, F18, F35 |
| **S4** | The class marker, step one, and `tb_mhunt` into `tb_max` | none | `tb_max` 98, identical trace; F41, F42, F43 RED |
| **S5** | `tb_maxnet` (§4.4) | new bench | its checks, each shown able to fail |
| **S6** | The class marker's rows + `make skel` | timing-only | `max`, `maxnet`; F40–F53 RED; `skel` clean |
| **S7** | The unit's writer through `ctl_queue(2,1)`, with the six rules | timing-only | five network benches; `un_ovf` live; F03, F03b, F06, F16, F19, F22, F35 as designed; trace: batches whole and in order, cross-owner swaps listed |
| **S8** | The unit's queue out; `ctl_queue` to `tb/`; the vacuous `ovf` checks deleted (584 → 578, Q7) | timing-only | everything; F16 re-anchored on the unit's CLM |
| **S9** | Per-region always blocks; the repeated sub-circuits as modules (Q3); every BOM comment honest; "cable B" becomes "the bus" | none | identical traces; lint with MULTIDRIVEN |
| after | Q1 ribbon; Q2 grid `ctl_write`; Q5 lockout (c); Q4 bank bus, each its own step and pilot | per question | per question |

**The pilots are most of S1–S3 already.** Review them against `STYLE.md` and
land them as those steps, rather than rewriting from this document.

**Add two faults** for the "not optional" rules that have none:

- act on the port in hand (mutate `called <= p_port` to SCAN + 1);
- a row's only exit is `sent` (mutate one row to leave on its decision).

**Add faults for the writer:** the `!t` gate, and the refusal's `!seq_w`.

**Keep the Makefile's forms.** `pcb/sim/run.py` (`make netcheck`, the block
stack's schematics run on these benches) reads `newimpl/Makefile`'s
one-line `RTL :=` and its `TB_<bench> :=` lines. When `ctl_queue` moves to
`tb/` and new modules arrive, keep those forms, or netcheck breaks.

---

## 6. Decisions for Joel

Each question is followed by options and a recommendation.

> **Status, 2026-09-26:** Joel has answered every question but Q10, which
> waits on the pros and cons of the fold, which he asked for. The sequencer
> form is decided (§7): gates, behind a seam that a diode matrix can replace.
> **S0 is done** (2026-09-26): all 52 verdicts are the contract's, 51 RED from
> named checks and F03 GREEN, and `tb_net` passes 89 of 89. **S1–S9 and the
> steps after wait** for another session's analysis of the pulse-flood
> protocol, because it may bear on them. Each step updates the documents its
> change touches, in its own commit.

1. **The marker↔unit ribbon as levels** (§3.6): `/FLOOD`, `OUT[1:0]`, no unit
   `restart`, four-phase `att_ack`.
   - **Recommend yes**, after both writers (S8), with the five fixes. It is
     `register.md` §3's own rule, and it removes the one argument from
     coincidence in the unit.
   - **Decided (Joel, 2026-09-26): yes, after S8.**
2. **SCLK from `SLOT1`, and the unit's grant after 18 serialiser steps**
   (`bus.md` §7 "SCLK is not a tap").
   - **Recommend yes**, as its own step. `tb_ctl`'s exact-tick checks (the
     545-tick word, the 32-tick period, the 8-tick WR margin) must be
     re-derived, and that is a change to what they assert. It needs 18 steps,
     not 9 frame edges: 9 edges can hand the bus over on the very step a
     marker word ends.
   - **Decided (Joel, 2026-09-26): `SCLK` from `SLOT1`, as its own step.**
3. **STYLE.md §1: may a sub-circuit the board repeats be a module** (monitor
   cell, leg bank, resolver), each a KiCad sheet? And which region of
   `net_unit.v` goes on which of its ≈5 cards?
   - **Recommend yes to both.** "A module is a board" is not true of the unit
     under any plan.
   - **Decided (Joel, 2026-09-26): yes to both.** `STYLE.md` §1 gains the
     repeated sub-circuit as a module, one KiCad sheet each. The partition of
     `net_unit.v`'s regions onto cards goes to Joel for review before S9 cuts
     it.
4. **The bank bus.**
   - **Recommend the last step, piloted, with the parallel '688s kept as a
     shadow checker.** It is worth one card of five.
   - **Decided (Joel, 2026-09-26): as recommended.**
5. **The mini marker's lockout with `/NET` low.**
   - **Recommend (c), resume after p**, as its own observable step between S3
     and S7.
   - **Decided (Joel, 2026-09-26): (c), resume after p**, as recommended.
6. **The class marker's nail memory** (13 FF). Making a nail only at a read in
   IDLE delays a re-nail by up to a round.
   - **Recommend keep.** It costs no mux, and removing it is observable and
     unbenched.
   - **Decided (Joel, 2026-09-26): remove it**, against the recommendation. A
     nail is made only when the walk reads it with the marker IDLE, so a
     re-nail can wait up to a round longer, about 250 ms. This supersedes
     §3.3's "the nail memory stays" and takes about two packages off its BOM.
     No bench covers the change yet: S6 should add a case in which a nail
     found unmade during a call is made on a later round.
7. **The six `ovf` checks**, vacuous once the queues go.
   - **Recommend delete** them with the step that empties each queue
     (584 → 578), and keep `ctl_queue`'s own checks in `tb/`.
   - **Decided (Joel, 2026-09-26): delete them.** They are in net, chain, lnet,
     lchain, lfull and max. Each of those benches keeps its live clash check.
8. **Bench values a '4020 cannot decode.** 250 (T_CLAIM) and 1250 (tb_max
   NODIG) need Q2; `tb_max`'s SETTLE 4 needs Q3.
   - **Recommend moving them to 256 and 1248**, and naming SETTLE 4
     model-only (or putting it on a '4040). Every board value (10000, 5000,
     2000, 128–1024, 18, 32) decodes.
   - **Decided (Joel, 2026-09-26): T_CLAIM 256 and NODIG 2048**, both a single
     tap (Q9 and Q12), "reasonable for now". SETTLE 4 is named model-only.
     T_CLAIM 250 is set in chain, lnet and lchain, and NODIG 1250 in those
     three and in max, not in `tb_max` alone. None of those four benches names
     the no-digit timeout, and their idle helpers wait on a hang-up, so the
     longer NODIG should cost only simulated time. S2's taps step runs all
     18 benches, which tests that.
9. **What clocks a common-control sequencer on the board.**
   - **Recommend naming the 4.096 MHz tick as a model artefact now.** Re-time
     onto HCLK edges only if the KiCad check needs tick alignment, and then
     with every one-tick strobe (`sent`, `done`, `fresh`, `dig_stb`, `brk`)
     widened to a level. One panel sketch that skipped this deadlocked on
     `sent`.
   - **Decided (Joel, 2026-09-26): name it a model artefact now.**
10. **The one-forwarder limit**, which folding the forwarder into the
    resolvers would lift.
    - **Recommend keep it, and no fold.** Lifting it is observable, and a
      queued forward's hop costs about 9 ms of guard.
    - **Open (2026-09-26):** Joel asked for the fold's pros and cons before
      deciding. It waits for the pulse-flood analysis, which bears on the
      forwarder directly.
11. **Drop `digits[15:12]` and the mini's probe tap?** Nothing reads either.
    - **Recommend yes**, with the ribbon step.
    - **Decided (Joel, 2026-09-26): drop both, with the ribbon step.** `ndig`
      still counts to 4, because the unit's `o_last` needs it. `tb_mini` wires
      the tap but no check reads it.
12. **F05's "held twice".** A check in `tb_net` scenario 2's release tail
    would turn F05 red (§1.8).
    - **Recommend adding the check** and narrowing README §4's double-hold
      statement to F03.
    - **Decided (Joel, 2026-09-26): add the check.** F05 becomes an ordinary
      RED fault, F05b stays, and README §4 and the header of `faults.py` narrow
      "held twice" to F03.

---

## 7. What this does not do

**Behaviour stays apart.** It does not merge the two markers' behaviour. A
merge would change eleven observable things — the way in, who may call, 0
and 9, busy, one's own number, an empty slot, a dialled trunk, a source, a
data line, failure timing, the claim take — and would contradict "the walk is
the class marker's only way in". Only the text and the sub-circuits are
unified, held by `make skel`.

**The following stay:**

- the stride-9 sweep: a monotone sweep is 64 ms and the 128 ms guard would
  cover about two hops;
- the per-port memory on the unit;
- one origin bank;
- `/NET` gating with no parameter;
- the register inside the mini marker and outside the class marker;
- the unit's rank with no grant.

**It does not propose** the following, which were considered and rejected:

- the '189 role RAM (asynchronous write strobes);
- the "hush" replacing `mine` (it replaces a measured fix with an argument);
- diode-matrix microsequencers (a '150 and diodes): about 16 packages fewer
  on the mini marker and 6–12 on the class marker. They read worse against
  the documents' tables, and one sketch of the form deadlocked. They are
  Joel's call if he wants the literal form.
  - **Correction (2026-09-26): the 16 and the 6–12 are not the sequencer's.**
    They are the difference between two whole-card estimates: the
    board-literal panel's card, about 62 after a judge's recount, and this
    main line's, about 78. That gap comes from a leaner serialiser (Q2), the
    reader, the probe (no re-point, no tap), the register and the word
    former. The panel's own sequencer was 9.5 packages, 14 on the judge's
    recount, against about 13 here. Its "diodes or gates" choice was worth 3
    packages on the mini and 4 on the class.
  - **Board area, sketched (2026-09-26).** The mini marker's part that
    differs comes to about 60 cm² as gates and about 75 cm² as a diode matrix.
    The matrix costs area at every crossing, fitted or not, and is only 25–40 %
    full. A matrix also cannot settle within one 4.096 MHz tick (about 0.4 µs
    with 10 k pull-ups), so it would bring Q9's re-timing onto HCLK forward.
  - **Decided (Joel, 2026-09-26): gates, with the sequencer behind a seam so
    that a diode matrix can be swapped in later.** Each marker's sequencer is
    its own module (one KiCad sheet, the same allowance as Q3). Its inputs are
    the events it waits on, and its outputs are the state, the word table's
    selects and the strobes. It has a `step` enable, tied to every tick for
    now. Before a slower sequencer can be swapped in, its one-tick inputs
    (`sent`, `rd_done`, `p_here`) must be held as levels (Q9).

**Documents.** The spec now describes what `newimpl` builds. Each step that
changes a documented mechanism edits that document in the same commit, and
logs what it replaced in one line in `decisions.md` (Joel, 2026-09-26). The
mechanisms are:

- `bus.md` §5 (the queue);
- `marker.md` §3, §4 and §7 (the states, the lockout, F05);
- `register.md` §3 (the ribbon);
- `network.md` §3.2–§3.6 and §10 (the writer, the ribbon, the unit's parts);
- `debugger.md` (if the sweep's timing moves).

---

Sources:

- analysis and the design panel: session scratch, summarised here;
- pilots: `newimpl/build/t68-{head,mini,unit,adv1,adv2}` (gitignored; may be
  cleaned);
- documents: `bus.md` §5, §7; `marker.md` §1–§7; `register.md` §2–§4;
  `network.md` §3, §4.1, §6, §10; `card-word.md` §2; `numbering.md` §1;
  `analysis/monitor-rules.md`; `newimpl/STYLE.md` §1–§7; `newimpl/README.md`
  §4, §6.

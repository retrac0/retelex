# How this tree is written

The rules below are the ones the code already follows. Where one is quoted, it
is quoted from the file that follows it, so a reader can check the rule
against the tree rather than take it on trust. When code and this document
disagree, one of them is wrong and it is usually this one.

---

## 1. Modules are boards

A module is a thing you could point at in a rack, and its port list is a
connector. `exch` is one exchange: the clock card, the mainboard, eight
blocks. `block`, `port`, `clock_card`, `mainboard` are boards. Everything that
*plugs in* — a marker, a register, a lamp field, the debugger — is
instantiated **beside** `exch`, never inside it:

> `exch` — ONE exchange: the clock card, the mainboard and the eight block
> positions. Nothing that plugs in — no marker, no register, no network unit,
> no card. Those are instantiated beside it, which is why a port has no idea
> what it is and why a trunk card can tap HC and /HA from outside.

Port lists are grouped by the connector the signals arrive on, under a rule:

```
    // ---- cable A -----------------------------------------------------------
    // ---- cable B -----------------------------------------------------------
    // ---- the channel socket (common-cards.md 1) ---------------------------
```

The order of the six cable-A signals (`slotq, cap_stb, frame_stb, scan, ha_n,
hb_n, tick_1k`) is the same in every module that takes them. There is no
bundle for them, on purpose: a bundle is not a board.

**A module reaches nothing it is not wired to.** No hierarchical references,
in RTL or in a bench. A bench that wants to see inside a board brings the
signal out on a port marked *for a bench*, and says so.

**A card is its socket.** There is no interface construct both simulators
accept, so the channel socket is a port list: the fourteen signal pins of
`common-cards.md` §1, in socket order, with the same names in the same order
on every card, declared whether or not the card has a part on the pin. A card
drives a5 and a6 totem-pole and a12–a14 open-drain — modelled at the pin, 0
pulled low, 1 left open — and listens to the rest. It has no master clock:
`clk` is the simulation's timebase, and every edge it acts on comes off the
socket's clock waveforms. `cvsd_line_card.v` is the reference; a site
instantiates any card by that list and connects it to socket `[p][s]`.

---

## 2. Comments are the BOM, and the argument

**A '151 is an `assign` under a comment that says so.** There is no chip
library. The comment names the package, and one region of code is one
package:

```
    // 74HC688 -- is the plane carrying the port we are listening to?
    wire eq_src = (scan == addr);

    // ---- 2N7002 x2: the open drains onto /HA and /HB ----------------------
```

A reader counting packages from the comments must get the board's count. That
is why the eight per-slot banks in `block.v` are written **once** each — one
'138, one bank of '157s — and not eight times: written eight times, the
comments claimed eight '138s.

**The comment carries the reason, not the mechanism.** The mechanism is the
line below it. What goes above it is *why this and not the obvious thing*,
with the number that decided it:

> 64 taps and 2 m of ribbon is ≈300 pF, so τ ≈ 1.4 µs against 8.79 µs of
> settling — six time constants.

> A word takes 133 us and a port comes round every 1 ms, so idling early
> seizes the same caller twice.

**It records what was tried and why it was wrong.** The failed design stays
in the comment as the argument for the working one:

> THE PER-PORT CLEAR IS NOT OPTIONAL. The old marker accumulated M with no
> clear, which was harmless only because a visit was eight frames and the
> last sample won. With ONE sample a port, an uncleared accumulator hands the
> reader the PREVIOUS port's hook.

**It names the model's artefacts.** Where the RTL differs from the board
because it is RTL — a strobe standing in for a clock edge, a counter standing
in for an RC, a reset state that reads as a frame edge — the comment says so,
so nobody optimises the artefact:

> Release detectors are RC networks. The RTL counts TICK only because the
> model has no analogue.

**One sentence a region in CAPITALS**: the one a reader must not skim past.
`ONE TURN, BOTH FACTS.` `A RELEASE BEATS A WRITE.` `NOTHING IN THE EXCHANGE
CAN STOP IT.` More than one a region and none of them is the one.

**Every module header ends with its sources**, by document and section:

```
//   mainboard.md 2.3, 2.3.1, 2.3.2
```

Cite by section, never by line number: the line numbers in `marker.md`
rotted by 28 within a week of being written. When quoting code, quote the
identifier and the line's text, which survive.

**`// MINIMAL` / `// MAXIMAL` / `// MINIMAL+MAXIMAL`** mark which build a
region or a module belongs to, and **`// NETWORK`** what only `top_net` stuffs
-- the network unit, its trunk cards, and the mini marker's network half. What
a build does not use is brought out and left unused, and the unused sink says
which build wants it:

```
    // Carried for a channel card on the block ribbon, not used by the exchange
    // logic: the captures run off SLOTQ and the detectors off TICK.
    wire _unused = &{1'b0, tick, hclk, line_hb, tx_clk, clk_8k, rx_oct,
                     oct_stb, slot, 1'b0};
```

---

## 3. Names

The documents' conductor names are the code's, lower-cased, with two suffixes
that mean exactly one thing each:

| suffix | means | examples |
|---|---|---|
| `_n` | low-true on the wire | `ha_n`, `hb_n`, `hw_n`, `blk_n`, `ans_n`, `word_n`, `clr_n` |
| `_stb` | one master tick, at an edge | `cap_stb`, `frame_stb`, `pass_stb`, `dig_stb`, `a_stb` |
| `_pd` | "this circuit is pulling the wire down" — a one, before the wired-OR inverts it | `ha_pd`, `hb_pd`, `hw_pd` |
| `_k` | the per-slot copy inside a block | `ha_pd_k` |

Prefixes say whose signal it is where it crosses a connector: `p_` off a
probe, `r_` off a register, `s_` off the serialiser, `w_` a field of the
mirrored control word. In a bench, `f_` is a fault being injected and `dbg_`
is the debugger's view of a signal after the fault.

**A module holds no copy of a fact a card states about itself.** A trunk
card's class, glare and direction are in its word, and a board that needs them
reads them off `/HW` when it needs them; nothing is strapped to agree with a
card that could be pulled and replaced by another.

**Everything on the marker's side of a register is a LEVEL, held until read.**
`rtl.md` §1: an event on a wire is a race. A one-tick pulse crosses a
connector only as a `_stb`, and the receiver samples it, never edge-detects
it. `probe.fresh` is the one exception that proves it — it is *the* strobe
that says "the levels beside me have just been renewed."

Parameters are `UPPER`. Defines in `exch.vh` are the fabric's geometry and
nothing else: `` `PW ``, `` `SCANW ``, `` `CWW ``, `` `CELL_A ``, the tick
positions.

---

## 4. Parameters are straps and stuffing, never features

A parameter is a jumper, a shunt, or whether a part is stuffed: `FITTED`,
`BLOCK`, `POS`, `SHUNT`, `SHUNT_FITTED`, `PORT_FITTED`, `RBT_IS_FILL` (no
ringback card fitted). A parameter that would change what the board *does*
rather than what is *on* it is a feature, and features are cards. The one
exception is `` `PW ``, and every site that would widen with it says so:

```
    // WIDENS WITH `PW: at nine bits this is a '688 and half an '85.
```

Two things follow. A parameter never selects behaviour in an `if`; it selects
what is instantiated or what a constant is. And each fact the board reads off
a strap comes from **one** strap, on the board that owns the fact: a block's
number is its own header jumper (`BLOCK_NUM[p]`, read once by a '148 and used
three ways — highway, `/BLK`, the ports' turn); a port card's slot is its own
2 × 3 jumper (`POS`). The mainboard holds no strap at all. When two straps
could disagree, one of them is a bug waiting for the non-default value — and
where a strap must agree with a socket, the comment says so.

A bench overrides a parameter to make a slow thing fast — a 1 s no-digit
timer, a 24 ms ring cadence — and says why in the instantiation: *"so the
bench does not sit through the real ten seconds twice."*

---

## 5. The language

Verilog-2001, plus the SystemVerilog that **both** simulators accept. Verilator
is what to use while working; Icarus is the reference; a construct one of them
rejects is not in the language. Probed against Icarus 13.0 and Verilator
5.050:

| in | out |
|---|---|
| `logic`, `typedef` on signals, `always_comb` | packed **array parameters** and localparams — Icarus: *"not supported yet"* |
| `for (int i …; i++)` inside `always_comb` | packed **struct parameters** and `'{…}` assignment patterns — Icarus: syntax error |
| `generate for (genvar …)` with `assign` and instances | interfaces — not probed; assume out |
| packed 2-D **signals and ports** (`logic [7:0][7:0] c_tx`, indexed `c_tx[p][s]`) | unpacked array parameters |
| a packed 2-D `wire` copied from a flat parameter, for readable indexing | |
| Verilog-2001 constant functions returning a **flat** vector | |
| size casts `3'(x)` | |

So parameters stay **flat vectors** with part-selects — `SHUNT[p*3 +: 3]`,
`PORT_FITTED[p*8 +: 8]` — and the readable two-dimensional form lives on
signals and in loops. Inside `always_comb`, a constant part-select of an `int`
loop variable (`c[2:0]`) draws an Icarus *"not fully supported"* note; compare
against a `localparam` in a generate instead.

**Loops are for identical things.** Eight identical boards in eight identical
connectors is a generate (`exch.v`'s blocks, `mainboard.v`'s shunt columns).
Each still exists in the hierarchy as `pos[p].u_blk`. A bank of gates that is
one package is written once, never eight times (§2). Where eight instances
differ in anything but an index, they are written out.

Lint is `verilator -Wall`, every module on its own, and **nothing is waived**.
The one waiver there was -- a deliberate blocking assignment in `mini_marker`'s
queue -- went with the queue into `ctl_queue`, where arriving entries are
placed by an `always_comb` and a sequencer hands over a slot mask. A loop
variable belongs to one process: two `always` blocks that share an `integer`
are two drivers of it. `make lint` fails if any module does not lint.

**Ordering tricks are stated.** When a later nonblocking assignment is meant
to win over an earlier one in the same block, the comment says so:

> These win: same signals, later assignment, and every right-hand side above
> read the old values.

When two branches could both write a register on one tick, they are gated
against each other explicitly, never by an argument that the two strobes
happen not to coincide.

---

## 6. Modelling the board honestly

- There are **no gate delays**, and every claim about nanoseconds is outside
  what the RTL can see. The README says so in its Status block.
- A wired-OR is `~(|drains)` at the mainboard, with the comment that the
  mainboard does the inversion; the drains are `_pd`, active high.
- Two drivers on one conductor read as `1'bx`, because that is what two '244s
  on one wire are.
- A conductor with no driver is pulled to what the clock card pulls it to
  (`fill`), not to a convenient zero.
- Where the hardware has a real clock wire the RTL makes both the waveform,
  for a card that wants an edge, and a one-tick strobe, for the synchronous
  logic — and says which is which.
- Absence is one mechanism. An unstuffed slot, an unstuffed block, a pulled
  card and a missing shunt must all read the same way the board would read
  them, out of the same logic, and never out of a special case.

---

## 7. Benches

Every bench prints one headline, then only its failures, then a count:

```
  tb_ha -- two wires, 64 ports, M and BUSY together, 1 kHz
     256 bit-times over 4 passes, capture at tick 36 of the frame

  13 checks, 0 errors.  PASS
```

`ck(cond, "claim")` counts a check; `oops("claim")` records a failure from
inside a sampling loop and shows at most eight; the footer is `%0d checks,
%0d errors` and `$fatal(1)` if any; a watchdog `initial #N` prints `TIMEOUT`.

**A check message is the sentence that became false.** Not a label:

```
    ck(nd_nodig === 1'b1, "PARTIAL DIAL: it fires 800 ms after the LAST digit");
    ck(port_busy[6'o25] === 1'b0, "and the glitched write MISSED its port");
    ck(port_busy[6'o25] === 1'b1, "and it LANDED: the '164s have no stored phase");
```

**A check must be able to fail.** A disjunction with a constant-true term, an
assertion of `FITTED && x` on an exchange with `FITTED = 0`, a section banner
over checks that test something else — each of these has been in this tree,
and each counted toward a total that meant less than it said. The proof that
a check can fail is to inject the fault it is for: put the old bug back in a
scratch copy and watch the check go red. `tb_debug` is built on nothing else.

Sample **either side of a threshold**, not the end state: at 12.5 ms the
detector has *not* armed; at 18.8 ms it *has*.

**A bench drives boards, not internals.** It instantiates `exch` and a
serialiser and drives their ports; it never reaches into the hierarchy. A
fault is injected *between* boards — a mux on the wire where a real fault
would be — so what is tested is the connector, which is what breaks.

**A bench says what it does not cover.** In its header, and in README §4's
"what these do not cover": the nominal corner it drives against the measured
one it does not; the branch no case reaches; the hazard it cannot see. A
bench read as proving more than it asserts is worse than no bench.

Both simulators, always. A bench that passes under one and not the other is
not done, and one real bug has been found only that way.

---

## 8. Documents, and departing from them

The code may depart from a document section, deliberately, and only with a
row in README §5 — *Where the documents now disagree* — naming the section
and what changed. The code comment names the section it departs from:

> THE POLARITY IS AN INVERSION OF mainboard.md 2.2, which has HA "pulled to
> ground: on-hook" — an open-collector wire cannot be.

A document's **Status block** says what is measured, what is argued, and what
is unbuilt, and does not round up. A number is given with its derivation —
*"64 ports × 64 master ticks is 4096, so the pass boundary and TICK are one
edge"* — never bare. A constant lives in one document and is cited from the
others; `common/terms.md` owns the names.

A retired document is kept in git and cited by the commit it last existed at,
never left as a link to nothing.

---

## 9. Commits, and the shared tree

A commit message is one sentence: what is true now, a colon, what moved.

```
Settle fabric.md 3.1's total: the stated 15.25 is right, the list is not.
Six signals a slot, not seven: fix the line the secondary word left behind.
Drop the M probe: the marker can count frames itself.
```

It names the document section when there is one. `snapshot` and `interim
commit` exist in the log; they are what the rule is for.

Several sessions edit this tree at once. Stage only your own paths. Do not
reformat a file you are not changing.

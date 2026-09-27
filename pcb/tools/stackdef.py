#!/usr/bin/env python3
"""stackdef.py -- the block stack, card by card and pin by pin: the one
description that pcb/lib/block-stack.json, the tables of exchange/block-stack.md
and the first draft of both schematics (gen_cards.py) are made from.

    python3 stackdef.py [OUT_JSON [OUT_MD]]
        default pcb/lib/block-stack.json and pcb/out/block-stack-tables.md

Once the schematics are edited in KiCad they, not this file, are the design;
this stays the record of the first draft and of the stack's pin contract,
which gen_cards.py --check holds both schematics to.
"""
import json, math, re, sys, collections
from pathlib import Path

_PCB = Path(__file__).resolve().parent.parent
OUT_JSON = sys.argv[1] if len(sys.argv) > 1 else str(_PCB / "lib" / "block-stack.json")
OUT_MD = sys.argv[2] if len(sys.argv) > 2 else str(_PCB / "out" / "block-stack-tables.md")

# the three cards (Joel, 2026-09-26: the header boards are blkhdr_bus_RevA and blkhdr_logic_RevA)
# the port card is drawn by hand in pcb/portcard_RevC (Joel, 2026-09-26: pcb/portcard, the
# generated copy, is gone); P below is the first draft it grew from, not a copy of it
CA, CB, CP = "blkhdr_bus_RevA", "blkhdr_logic_RevA", "portcard_RevC"

# ----------------------------------------------------------------------------
# geometry helpers
def rot(x, y, a):
    r = math.radians(a)
    c, s = round(math.cos(r), 9), round(math.sin(r), 9)
    return (x * c + y * s, -x * s + y * c)

def place(local, pos, a, bottom=False):
    out = {}
    for n, (x, y) in local.items():
        if bottom:
            x = -x
        dx, dy = rot(x, y, a)
        out[n] = [round(pos[0] + dx, 3), round(pos[1] + dy, 3)]
    return out

def hdr2(n, even_dx=2.54):
    """2 x n pattern: pad 2i+1 at (0, 2.54 i), pad 2i+2 at (even_dx, 2.54 i)."""
    d = {}
    for i in range(n):
        d[2 * i + 1] = (0.0, 2.54 * i)
        d[2 * i + 2] = (even_dx, 2.54 * i)
    return d

def hdr1(n):
    return {i + 1: (0.0, 2.54 * i) for i in range(n)}

# ----------------------------------------------------------------------------
# nets
NETS = collections.OrderedDict()

def net(name, doc=None, **kw):
    assert name not in NETS, name
    d = dict(name=name, doc=doc or name)
    d.update(kw)
    NETS[name] = d

net("+5V", group="power", drive="rail", note="logic supply; bus pins 1,2,49,50 in, 6 stack pins up")
net("GND", group="power", drive="rail", note="18 stack pins; with the static lines, the shield of J1's checkerboard")

# --- stack commons -----------------------------------------------------------
for i in range(6):
    net(f"SCAN{i}", group="common", dir="hdr->port", drive="totem-pole",
        driver="blockhdr U%s" % ("2" if i < 4 else "3"),
        rtl=f"scan[{i}] (port.v:44, block.v:57)")
for i in range(8):
    net(f"HC{i}", group="common", dir="hdr->port", drive="totem-pole",
        driver="blockhdr U%s" % ("3" if i < 6 else "4"), rtl=f"hc[{i}] (port.v:48)")
for i in range(8):
    net(f"STB{i}_N", doc=f"/STB{i}", group="common", dir="hdr->port", drive="totem-pole",
        driver="blockhdr U14 via RN3 33R", fast=True,
        rtl=f"cap_stb && slotq=={i} (port.v:83, :105): falling edge = the capture instant")
for i in range(6):
    net(f"SRC{i}", group="common", dir="hdr->port", drive="totem-pole", driver="blockhdr U10",
        rtl=f"src[{i}] = cw[{i+2}] (block.v:147)")
net("BSY", group="common", dir="hdr->port", drive="totem-pole", driver="blockhdr U10", rtl="bsy_in = cw[1]")
net("CLM", group="common", dir="hdr->port", drive="totem-pole", driver="blockhdr U10", rtl="clm_in = cw[0]")
for i in range(3):
    net(f"H{i}", group="common", dir="hdr->port", drive="totem-pole (static)", driver="blockhdr U4",
        rtl=f"BLOCK[{i}] (port.v:27, :99)")
net("HA_RX", group="common", dir="hdr->port", drive="totem-pole", driver="blockhdr U6",
    rtl="~ha_n (port.v:173): /HA through a Schmitt, high = someone pulling")
net("RING_CAD_N", doc="/RING_CAD", group="common", dir="hdr->port", drive="totem-pole",
    driver="blockhdr U2", rtl="ring_cad_n (port.v:45)")
net("MUTE_BLK", group="common", dir="hdr->port", drive="totem-pole", driver="blockhdr U4",
    rtl="mute_blk (block.v:77, port.v:147)")
net("RST_N", doc="/RST", group="common", dir="hdr->port", drive="totem-pole", driver="blockhdr U6",
    rtl="rst_n (port.v:38): /RESET filtered once, at the header")
net("RBT", group="common", dir="hdr->port", drive="totem-pole", driver="blockhdr U2",
    rtl="rbt (block.v:59), now read on the port card")
net("TX_CLK", group="common", dir="hdr->port", drive="totem-pole", driver="blockhdr U7 via R4 33R",
    fast=True, rtl="frame_decode.v:47 tx_clk = ~slot2")
net("LOOP_HB", group="common", dir="hdr->port", drive="totem-pole", driver="blockhdr U7 via R5 33R",
    fast=True, rtl="~slot[1] (top_net.v:154); socket a2")
net("TX_OCT", group="common", dir="hdr->port", drive="totem-pole", driver="blockhdr U8",
    rtl="frame_decode.v:48")
net("RX_OCT", group="common", dir="hdr->port", drive="totem-pole", driver="blockhdr U9",
    rtl="frame_decode.v:49 (a '74 on TX_CLK, not the decode)")
net("FILL", group="common", dir="hdr->port", drive="totem-pole", driver="blockhdr U4",
    rtl="frame_decode.v:51 fill = scan[0]; socket a4")
# --- wired ---------------------------------------------------------------------
net("HA_L_N", doc="/HA_L", group="wired", dir="port->hdr", drive="open-drain",
    pull=dict(to="+5V", ohm=1000, at="blockhdr R1"), rtl="|ha_pd_k (block.v:237)")
net("HB_L_N", doc="/HB_L", group="wired", dir="port->hdr", drive="open-drain",
    pull=dict(to="+5V", ohm=1000, at="blockhdr R2"), rtl="|hb_pd_k (block.v:238)")
# --- lanes ---------------------------------------------------------------------
for k in range(8):
    net(f"WR{k}_N", doc=f"/WR{k}", group="lane", lane=k, dir="hdr->port", drive="totem-pole",
        driver="blockhdr U13 via RN4 33R", fast=True, rtl=f"wr_dec[{k}] (block.v:118) -> port wr")
for k in range(8):
    net(f"C_TX{k}", group="lane", lane=k, dir="port->hdr", drive="totem-pole",
        driver=f"the port card jumpered to lane {k}: U12 '157 (rb ? RBT : c_tx)",
        pull=dict(to="FILL_R", ohm=4700, at="blockhdr RN1"),
        rtl=f"c_mux[{k}] (block.v:124-131)")
for k in range(8):
    net(f"WORD{k}", group="lane", lane=k, dir="port->hdr", drive="open-drain",
        driver=f"the subscriber card behind the port card jumpered to lane {k} (a12)",
        pull=dict(to="+5V", ohm=10000, at="blockhdr RN2", also="680R on the port card (R2)"),
        rtl=f"word_n[{k}] (block.v:72, :136); low = a one")
for s in ("SP1", "SP2", "SP3", "SP4", "SP5", "SP6", "SP7"):
    net(s, group="spare", drive="none", note="through-pin on every card, connected to nothing")

# --- bus (block header only) ---------------------------------------------------
BUS = {1: "+5V", 2: "+5V", 3: "B_HCLK", 4: "GND", 5: "B_SLOT0", 6: "GND", 7: "B_SLOT1", 8: "GND",
       9: "B_SLOT2", 10: "GND", 11: "B_SLOTQ0", 12: "GND", 13: "B_SLOTQ1", 14: "GND",
       15: "B_SLOTQ2", 16: "GND", 17: "B_SCLK", 18: "GND", 19: "B_WR", 20: "GND",
       21: "B_SDATA", 22: "B_UREQ_N", 23: "B_RESET_N", 24: "GND", 25: "GND", 26: "GND",
       27: "B_SCAN0", 28: "B_SCAN1", 29: "B_SCAN2", 30: "B_SCAN3", 31: "B_SCAN4", 32: "B_SCAN5",
       33: "B_HC0", 34: "B_HC1", 35: "B_HC2", 36: "B_HC3", 37: "B_HC4", 38: "B_HC5",
       39: "B_HC6", 40: "B_HC7", 41: "GND", 42: "B_RBT", 43: "B_RING_CAD_N", 44: "B_HA_N",
       45: "B_HB_N", 46: "B_HW_N", 47: "B_WS_N", 48: "B_SPARE", 49: "+5V", 50: "+5V"}
BUSRTL = {"B_HCLK": "rebuilt from cap_stb (sim shim)", "B_SLOT0": "slot[0]", "B_SLOT1": "slot[1]",
          "B_SLOT2": "slot[2]", "B_SLOTQ0": "slotq[0]", "B_SLOTQ1": "slotq[1]", "B_SLOTQ2": "slotq[2]",
          "B_SCLK": "sclk", "B_WR": "wr", "B_SDATA": "sdata", "B_UREQ_N": "not used by a block",
          "B_RESET_N": "rst_n", "B_RBT": "rbt", "B_RING_CAD_N": "ring_cad_n",
          "B_HA_N": "ha_n (in); the header's Q1 drain is ha_pd", "B_HB_N": "the header's Q2 drain is hb_pd",
          "B_HW_N": "the header's Q3 drain is hw_pd", "B_WS_N": "ws_n", "B_SPARE": "not used"}
for i in range(6): BUSRTL[f"B_SCAN{i}"] = f"scan[{i}]"
for i in range(8): BUSRTL[f"B_HC{i}"] = f"hc[{i}]"
for p, n in BUS.items():
    if n in NETS: continue
    od = n in ("B_HA_N", "B_HB_N", "B_HW_N", "B_WS_N")
    doc = "/" + n[2:-2] if n.endswith("_N") else n[2:]
    net(n, doc=doc + " (bus)", group="bus", drive="open-drain" if od else "totem-pole",
        pin=p, rtl=BUSRTL[n],
        pull=(dict(to="+5V", ohm=4700, at="clock card (mainboard.v:25)") if od else
              dict(to="GND", ohm=100000, at="blockhdr RN5/RN6") if n in
              ("B_HCLK", "B_SLOT0", "B_SLOT1", "B_SLOT2", "B_SLOTQ0", "B_SLOTQ1", "B_SLOTQ2",
               "B_SCLK", "B_WR", "B_SDATA", "B_RESET_N") else None))

# --- adapter commons -------------------------------------------------------------
ADP = {1: "A_TX_CLK", 2: "GND", 3: "A_TX_OCT", 4: "GND", 5: "A_FILL", 6: "GND", 7: "A_MUTE_BLK",
       8: "GND", 9: "A_HCLK", 10: "GND"}
net("A_TX_CLK", doc="TX_CLK (adapter)", group="adapter", dir="out", drive="totem-pole",
    driver="blockhdr U5 via R6 33R")
net("A_TX_OCT", doc="TX_OCT (adapter)", group="adapter", dir="out", drive="totem-pole",
    driver="blockhdr U5 via R7 33R")
net("A_FILL", doc="FILL (adapter)", group="adapter", dir="out", drive="totem-pole",
    driver="blockhdr U5 via R8 33R")
net("A_MUTE_BLK", doc="MUTE_BLK (adapter)", group="adapter", dir="in", drive="totem-pole (adapter)",
    pull=dict(to="GND", ohm=10000, at="blockhdr R10"), rtl="mute_blk")
net("A_HCLK", doc="HCLK (adapter, the spare)", group="adapter", dir="out", drive="totem-pole",
    driver="blockhdr U5 via R9 33R")

# --- edge (port card only) ---------------------------------------------------------
# a_n -> pin 2n-1, c_n -> pin 2n; row 17 (pins 33, 34) = GND, GND
EDGE_A = {1: ("E_TX_CLK", "TX_CLK", "out: U13 via RN1 33R"),
          2: ("E_LOOP_HB", "LOOP_HB", "out: U13 via RN1 33R"),
          3: ("E_TX_OCT", "TX_OCT", "out: U13 via RN1 33R"),
          4: ("E_FILL", "FILL", "out: U13 via RN1 33R"),
          5: ("E_C_TX", "C_TX", "in: 4.7k to E_FILL (R5); -> U12 '157 A"),
          6: ("E_A_TX", "A_TX (M)", "in: 10k pull-down (R1); M"),
          7: ("E_RX_CLK", "RX_CLK = TX_CLK", "out: U13 via RN1 33R"),
          8: ("E_RX_OCT", "RX_OCT", "out: U13 via RN1 33R"),
          9: ("E_C_RX", "C_RX", "out: U6 1Q through U13, RN1 33R"),
          10: ("E_A_RX", "A_RX", "out: U11 through U13, RN1 33R"),
          11: ("GND", "MUTE, tied locked", "GND"),
          12: ("E_WORD", "card word", "in, open drain: 680R pull-up (R2); to lane via JP4"),
          13: ("E_ANS_N", "/ANS", "in, open drain: 680R pull-up (R3); -> U8 ON"),
          14: ("E_RAI_N", "RAI (spare)", "in, open drain: 680R pull-up (R4); unused"),
          15: (None, "key", "not connected"),
          16: ("GND", "GND", "GND")}
EDGE_C = {1: ("+5V", "+5 V"), 2: ("GND", "GND"), 3: ("+5V", "+5 V"), 4: ("GND", "GND"),
          5: (None, "+12 V: not on the port card"), 6: ("GND", "GND"),
          7: (None, "-12 V: not on the port card"), 8: ("GND", "GND"),
          9: (None, "-48 V: not on the port card"), 10: (None, "-48 RET: not on the port card"),
          11: ("GND", "GND"), 12: (None, "RING: never on this header"),
          13: (None, "RING RET: never on this header"), 14: ("GND", "GND"),
          15: (None, "key"), 16: ("GND", "GND")}
for a, (n, doc, how) in EDGE_A.items():
    if n and n not in NETS:
        od = n in ("E_WORD", "E_ANS_N", "E_RAI_N")
        net(n, doc=f"a{a} {doc}", group="edge", card=CP,
            drive="open-drain (subscriber card)" if od else
                  ("totem-pole (subscriber card)" if a in (5, 6) else "totem-pole"),
            note=how)

# --- jumper-side and header-local named nets --------------------------------------
net("HC_OUT", group="local", card="blockhdr", drive="tri-state ('244 gated by FIT_N) + 100R",
    rtl="hc_out (block.v:62, :230)", note="one side of the HC route jumper JP1")
net("FIT_N", doc="/FIT", group="local", card="blockhdr", drive="static, shunt to GND",
    pull=dict(to="+5V", ohm=10000, at="blockhdr RN7"), rtl="JUMPERED (block.v:43), active low")
for i in range(3):
    net(f"H{i}_J", group="local", card="blockhdr", drive="static, shunt to GND",
        pull=dict(to="+5V", ohm=10000, at="blockhdr RN7"), rtl=f"BLOCK[{i}] (block.v:42)")
net("HA_PD", group="local", card="blockhdr", drive="totem-pole (U19)", rtl="ha_pd (block.v:65)",
    note="gate of Q1, the /HA bus drain")
net("HB_PD", group="local", card="blockhdr", drive="totem-pole (U19)", rtl="hb_pd (block.v:66)",
    note="gate of Q2, the /HB bus drain")
net("HW_PD", group="local", card="blockhdr", drive="totem-pole (U19)", rtl="hw_pd (block.v:84)",
    note="gate of Q3, the /HW bus drain")
net("FILL_R", group="local", card="blockhdr", drive="totem-pole (U4)",
    note="FILL again, on its own '244 section: feeds only RN1, the eight C_TX lane pulls")
net("BLK_N", doc="/BLK", group="local", card="blockhdr", drive="totem-pole (U12)", rtl="blk_n (block.v:104)")
net("RBT_SRC", group="local", card="blockhdr", drive="C_TX lane k, through the RBT SOURCE shunt",
    note="through blockhdr R12 (100R) onto B_RBT: on the one block whose lane k is a ringback card "
         "(bus.md 7: nothing else brings a card's output to bus pin 42)")
net("LAMP_CK", group="local", card="blockhdr", driver="blockhdr U20", drive="totem-pole",
    note="NOR(/STB4, /SELM): rises mid-frame in each of this block's eight frames; shifts the lamp '595s")
for k in range(8):
    net(f"LAMP_M{k}", group="local", card="blockhdr", driver="blockhdr U21", drive="tri-state ('595, /OE = /FIT)",
        note=f"slot {k}'s M lamp: low (lit) when card {k} pulled /HA_L in its turn last pass")
    net(f"LAMP_B{k}", group="local", card="blockhdr", driver="blockhdr U22", drive="tri-state ('595, /OE = /FIT)",
        note=f"slot {k}'s BUSY lamp: low (lit) when card {k} pulled /HB_L in its turn last pass")
net("P_WR_N", doc="/WR (this card's)", group="local", card=CP, drive="lane via JP2",
    pull=dict(to="+5V", ohm=10000, at="port card RN2"), rtl="wr (port.v:65)")
net("P_C_TX", doc="C_TX (this card's, after ringback)", group="local", card=CP,
    drive="totem-pole (U12)", rtl="c_mux[POS] (block.v:124-131)")
for i in range(3):
    net(f"POS{i}", group="local", card=CP, drive="static, shunt to GND",
        pull=dict(to="+5V", ohm=10000, at="port card RN2"), rtl=f"POS[{i}] (port.v:28)")
net("BUSY_N", doc="/BUSY", group="local", card=CP, drive="totem-pole (U10)",
    rtl="busy (port.v:147); port_busy[k] = !BUSY_N", note="test point JP-TP pin 2")

# ----------------------------------------------------------------------------
# stack connectors: two 2x25, identical on every card (Joel, 2026-09-26).  Pin
# 2i-1 and 2i are one row across.  J1, on the left, is the CLOCK connector: the
# 19 lines whose edges are capture instants (/STB0-7, /WR0-7, TX_CLK, LOOP_HB,
# /RST) in a checkerboard, so that each has only GND, +5V or a static line
# (H0-2, MUTE_BLK, /RING_CAD) beside it and across from it.  J2, on the right,
# carries what is sampled mid-cell or held for a frame: SCAN, HC, the control
# word, the planes and the C_TX / WORD lanes.  (pcb/out/pinout/pinout2x25.py)
J1 = ["+5V", "+5V",
      "STB0_N", "GND",   "GND", "STB1_N",   "STB2_N", "GND",   "GND", "STB3_N",
      "STB4_N", "GND",   "GND", "STB5_N",   "STB6_N", "GND",   "GND", "STB7_N",
      "TX_CLK", "H0",    "H1", "LOOP_HB",   "RST_N", "H2",     "GND", "WR0_N",
      "WR1_N", "GND",    "GND", "WR2_N",    "WR3_N", "GND",    "GND", "WR4_N",
      "WR5_N", "GND",    "MUTE_BLK", "WR6_N", "WR7_N", "RING_CAD_N",
      "GND", "HA_RX",    "RBT", "FILL",     "TX_OCT", "RX_OCT", "SP1", "SP2",
      "+5V", "+5V"]
J2 = ["+5V", "GND",
      "SCAN0", "SCAN1", "SCAN2", "SCAN3", "SCAN4", "SCAN5", "SP3", "SP4",
      "HC0", "HC1", "HC2", "HC3", "HC4", "HC5", "HC6", "HC7", "GND", "SP5",
      "CLM", "BSY", "SRC0", "SRC1", "SRC2", "SRC3", "SRC4", "SRC5", "HA_L_N", "HB_L_N",
      "C_TX0", "C_TX1", "C_TX2", "C_TX3", "C_TX4", "C_TX5", "C_TX6", "C_TX7", "SP6", "SP7",
      "WORD0", "WORD1", "WORD2", "WORD3", "WORD4", "WORD5", "WORD6", "WORD7", "GND", "+5V"]
J1 = {i + 1: n for i, n in enumerate(J1)}
J2 = {i + 1: n for i, n in enumerate(J2)}
for J in (J1, J2):
    assert sorted(J) == list(range(1, 51)), J
CLOCKS = [f"STB{k}_N" for k in range(8)] + [f"WR{k}_N" for k in range(8)] + ["TX_CLK", "LOOP_HB", "RST_N"]
for name, J in (("J1", J1), ("J2", J2)):
    for p, n in J.items():
        if n in CLOCKS:
            for q in (p + 1 if p % 2 else p - 1, p - 2, p + 2):
                assert q not in J or J[q] in ("GND", "+5V", "H0", "H1", "H2", "MUTE_BLK", "RING_CAD_N"), \
                    (f"{name}.{p} {n} beside {J[q]} at {q}")

# Both front-aligned, pin 1 at the BACK end (Joel, 2026-09-26): a card turned
# round cannot seat, and the back edge is left for lamps and test strips.
# Pads y 27.0 - 87.96, 2 mm back from first drawn (Joel: "too close to the
# holes"): the socket body ends 7.3 mm from the front holes' centres.
SOCK = hdr2(25, even_dx=-2.54)   # PinSocket_2x25_P2.54mm_Vertical pattern
STACK_FP = {CP: "telco:Stack_2x25_P2.54mm_LongTail",
            CB: "telco:Stack_2x25_P2.54mm_LongTail",
            CA: "Connector_PinSocket_2.54mm:PinSocket_2x25_P2.54mm_Vertical"}
STACK = [
    dict(ref="J1", role="stack, clocks (checkerboard) and commons", edge="left", rotation=0, pos=(5.08, 27.0),
         pins=J1, pad1="back end, inner row", outer_row="even"),
    dict(ref="J2", role="stack, data, planes and lanes", edge="right", rotation=0, pos=(97.46, 27.0),
         pins=J2, pad1="back end, outer row", outer_row="odd"),
]
for c in STACK:
    c["pads"] = place(SOCK, c["pos"], c["rotation"])
# check geometry
assert STACK[0]["pads"][2] == [2.54, 27.0] and STACK[0]["pads"][49] == [5.08, 87.96]
assert STACK[1]["pads"][2] == [94.92, 27.0] and STACK[1]["pads"][50] == [94.92, 87.96]

# every stack net appears on exactly one stack pin (power many times)
allpins = collections.Counter()
for c in STACK:
    for n in c["pins"].values(): allpins[n] += 1
for n, cnt in allpins.items():
    if n not in ("+5V", "GND"):
        assert cnt == 1, n
        assert n in NETS, n
stack_signals = [n for n in allpins if n not in ("+5V", "GND") and not n.startswith("SP")]
assert len(stack_signals) == 69, len(stack_signals)
assert allpins["+5V"] == 6 and allpins["GND"] == 18, (allpins["+5V"], allpins["GND"])
assert sum(1 for n in allpins if n.startswith("SP")) == 7
for c in STACK:
    for pn, n in c["pins"].items():
        NETS[n].setdefault("stack_pins", []).append(f"{c['ref']}.{pn}")

# ----------------------------------------------------------------------------
# edge header (port card)
EDGE_PINS = {}
for a in range(1, 17):
    EDGE_PINS[2 * a - 1] = EDGE_A[a][0] or "NC"
    EDGE_PINS[2 * a] = EDGE_C[a][0] or "NC"
EDGE_PINS[33] = "GND"; EDGE_PINS[34] = "GND"
IDC17 = hdr2(17)
EDGE = dict(ref="J4", card=CP, role="edge header to the subscriber card",
            footprint="Connector_IDC:IDC-Header_2x17_P2.54mm_Horizontal", side="top",
            rotation=270, pos=(54.0, 87.2), pins=EDGE_PINS,
            pad1="right end, inner row (row a)", note="row a = odd pins (inner), row c = even pins (outer, nearer the edge)")
EDGE["pads"] = place(IDC17, EDGE["pos"], 270)
assert EDGE["pads"][2] == [54.0, 89.74] and EDGE["pads"][33] == [13.36, 87.2]

# test strips: PLACED parts (fixed=False), not contract.  pos / rotation are
# where the board has them, the pads a record; nothing mates with them.
TP_PC = ["GND", "BUSY_N", "E_A_TX", "FM_N", "FE", "E", "RB", "WC", "WA", "EQ_OWN_N", "WRCLK", "CLR_N"]
TP_HD = ["GND", "HA_L_N", "HB_L_N", "HC_OUT", "FIT_N", "WS_C_N", "HW_PD", "RST_N"]
TP_HL = ["GND", "BLK_N", "WSCLK", "SELV_N", "G", "OCT_MID", "RX_OCT", "TX_OCT"]
TPS = [
    dict(ref="J5", card=CP, role="test strip (probe hooks at the back edge, beside the lamps)",
         footprint="Connector_PinHeader_2.54mm:PinHeader_1x12_P2.54mm_Horizontal", side="top",
         rotation=90, pos=(20.0, 10.2), pins={i + 1: n for i, n in enumerate(TP_PC)}, fixed=False),
    dict(ref="J7", card=CA, role="test strip (probe hooks at the back edge)",
         footprint="Connector_PinHeader_2.54mm:PinHeader_1x08_P2.54mm_Horizontal", side="top",
         rotation=90, pos=(60.0, 10.2), pins={i + 1: n for i, n in enumerate(TP_HD)}, fixed=False),
    dict(ref="J9", card=CB, role="test strip (probe hooks at the front edge)",
         footprint="Connector_PinHeader_2.54mm:PinHeader_1x08_P2.54mm_Horizontal", side="top",
         rotation=270, pos=(58.9, 91.5), pins={i + 1: n for i, n in enumerate(TP_HL)}, fixed=False),
]
for t in TPS:
    t["pads"] = place(hdr1(len(t["pins"])), t["pos"], t["rotation"])

# the header link: the six nets between the two header boards that are not
# stack nets.  A carries a 2x6 socket on top; B a plain 2x6 pin header on its
# UNDERSIDE, pins down into it -- 8.5 mm of socket and 2.54 mm of pin-header
# body mate at exactly the stack's 11 mm gap.  Nothing of it reaches a port card.
LINK_PINS = {1: "SCLK_R", 2: "GND", 3: "SDATA_R", 4: "GND", 5: "WR_R", 6: "GND",
             7: "FIT_N", 8: "GND", 9: "WS_C_N", 10: "GND", 11: "HW_PD", 12: "GND"}
LINK_POS = (41.0, 60.0)
LINK_A = dict(ref="J8", card=CA, role="header link to B (socket)",
              footprint="Connector_PinSocket_2.54mm:PinSocket_2x06_P2.54mm_Vertical", side="top",
              rotation=90, pos=LINK_POS, pins=LINK_PINS, pad1="left end, back row",
              note="SCLK, SDATA, WR and /FIT up; /WS (cleaned) up; hw_pd down")
LINK_A["pads"] = place(hdr2(6, even_dx=-2.54), LINK_A["pos"], 90)
LINK_B = dict(ref="J8", card=CB, role="header link to A (pin header, underside)",
              footprint="Connector_PinHeader_2.54mm:PinHeader_2x06_P2.54mm_Vertical", side="bottom",
              rotation=90, pos=LINK_POS, pins=LINK_PINS, pad1="left end, back row",
              note="flipped to B.Cu, pins down into A's J8")
LINK_B["pads"] = place(hdr2(6), LINK_B["pos"], 90, bottom=True)
assert LINK_A["pads"] == LINK_B["pads"], "the link's two halves must meet pad for pad"

# the bus: ONE connector on header A (Joel, 2026-09-26), a shrouded, keyed
# right-angle IDC 2x25 at the FRONT edge for the daisy-chained ribbon; the
# underside pair and bus.md 2.3's mirrored edges are gone from the block header.
# Same row order as the port card's edge header: odd pins the inner row, pin 1
# at the right-hand end, the shroud's opening at the edge.
BUS_J = dict(ref="J4", card=CA, role="bus 2x25, front edge (the ribbon)",
             footprint="Connector_IDC:IDC-Header_2x25_P2.54mm_Horizontal", side="top",
             rotation=270, pos=(80.48, 87.2), pins=BUS,
             pad1="right end, inner row", outer_row="even",
             note="right-angle, shroud opening at the front edge; odd pins the inner row")
BUS_J["pads"] = place(hdr2(25), BUS_J["pos"], 270)
assert BUS_J["pads"][2] == [80.48, 89.74] and BUS_J["pads"][49] == [19.52, 87.2]

ADAPT = dict(ref="J6", card=CA, role="adapter commons 2x5 (block-stack.md 6), back edge",
             footprint="Connector_IDC:IDC-Header_2x05_P2.54mm_Horizontal", side="top",
             rotation=90, pos=(15.0, 12.8), pins=ADP, pad1="left end, inner row",
             note="odd signal, even ground, shrouded and keyed; opening at the back edge", fixed=False)
ADAPT["pads"] = place(hdr2(5), ADAPT["pos"], 90)

# ----------------------------------------------------------------------------
# jumpers: all vertical 2.54 mm headers IN THE INTERIOR, beside the logic each
# one sets, for low-profile shunts (~6 mm under the 9 mm limit) -- Joel,
# 2026-09-26: "move headers to the interior near where they are needed".  Each
# is set once, for the card's slot or the block's place in the exchange, with
# the boards above lifted off.  Placed parts: pos / rotation are the board's.
def lane_jumper(ref, lanes, own, pos):
    pins = {}
    for k in range(8):
        pins[2 * k + 1] = lanes[k]
        pins[2 * k + 2] = own
    j = dict(ref=ref, card=CP, footprint="Connector_PinHeader_2.54mm:PinHeader_2x08_P2.54mm_Vertical",
             side="top", rotation=90, pos=pos, pins=pins, fixed=False,
             shunts=[dict(pads=[2 * k + 1, 2 * k + 2], means=f"this card is slot {k}: {own} = {lanes[k]}")
                     for k in range(8)])
    j["pads"] = place(hdr2(8), j["pos"], 90)
    return j

JP_WR = lane_jumper("JP2", [f"WR{k}_N" for k in range(8)], "P_WR_N", (12.7, 52.0))
JP_WR.update(label="WR", near="J1's /WR pins and U10, the '4002 that turns /WR into the '273's clock",
             missing="the card is never written: P_WR_N pulled up by RN2, the '273 never clocks")
JP_CTX = lane_jumper("JP3", [f"C_TX{k}" for k in range(8)], "P_C_TX", (70.0, 70.0))
JP_CTX.update(label="C_TX", near="J2's C_TX pins and U12, the ringback '157",
              missing="lane k stays on FILL_R: heard as silence; the card's own C goes nowhere")
JP_WORD = lane_jumper("JP4", [f"WORD{k}" for k in range(8)], "E_WORD", (70.0, 80.0))
JP_WORD.update(label="WORD", near="J2's WORD pins and R2, the edge's card-word pull-up",
               missing="lane k stays pulled up: no word, class 000 unequipped")

JP_POS = dict(ref="JP1", card=CP, label="POS", near="U5, the eq_own '688",
              footprint="Connector_PinHeader_2.54mm:PinHeader_2x03_P2.54mm_Vertical", side="top",
              rotation=90, pos=(50.0, 40.0), fixed=False,
              pins={1: "POS0", 2: "GND", 3: "POS1", 4: "GND", 5: "POS2", 6: "GND"},
              shunts=[dict(pads=[1, 2], means="S0: POS0 = 0"), dict(pads=[3, 4], means="S1: POS1 = 0"),
                      dict(pads=[5, 6], means="S2: POS2 = 0")],
              missing="an open position reads 1 (RN2 10k): no shunts at all is slot 7")
JP_POS["pads"] = place(hdr2(3), JP_POS["pos"], 90)

JP_HC = dict(ref="JP1", card=CA, label="HC ROUTE", near="the bus's HC0-7 pins (J4 33-40) and R3",
             footprint="Connector_PinHeader_2.54mm:PinHeader_2x08_P2.54mm_Vertical", side="top",
             rotation=90, pos=(33.0, 83.0), fixed=False,
             pins={}, shunts=[], missing="HC_OUT reaches no highway: the block is silent on HC, and listens")
for j in range(8):
    h = 7 - j
    JP_HC["pins"][2 * j + 1] = f"B_HC{h}"
    JP_HC["pins"][2 * j + 2] = "HC_OUT"
    JP_HC["shunts"].append(dict(pads=[2 * j + 1, 2 * j + 2], means=f"HC_OUT drives highway HC{h}; must equal NUMBER h = {h}"))
JP_HC["pads"] = place(hdr2(8), JP_HC["pos"], 90)

JP_NUM = dict(ref="JP2", card=CA, label="NUMBER", near="RN7 and U4, the '244 that puts h up the stack",
              footprint="Connector_PinHeader_2.54mm:PinHeader_2x04_P2.54mm_Vertical", side="top",
              rotation=0, pos=(44.0, 30.0), fixed=False,
              pins={1: "FIT_N", 2: "GND", 3: "H0_J", 4: "GND", 5: "H1_J", 6: "GND", 7: "H2_J", 8: "GND"},
              shunts=[dict(pads=[1, 2], means="FIT: the block is fitted (JUMPERED)"),
                      dict(pads=[3, 4], means="h0 = 0"), dict(pads=[5, 6], means="h1 = 0"),
                      dict(pads=[7, 8], means="h2 = 0")],
              missing="h bits read 1 when open; FIT open = unjumpered: no HC drive, no /BLK, no /WS answer, no plane turn")
JP_NUM["pads"] = place(hdr2(4), JP_NUM["pos"], 0)

# RBT SOURCE (2026-09-26): bus.md 7 had no way for a ringback card's output to
# reach bus pin 42.  On the ONE block of an exchange whose port card k is the
# ringback card, a shunt in column k puts lane C_TX k, through R12 (100R, as
# every bus driver: bus.md 2.4), onto B_RBT.  Open everywhere else.
JP_RBT = dict(ref="JP3", card=CA, label="RBT SOURCE", near="J2's C_TX pins, U15 and RN1; R12 at bus pin 42",
              footprint="Connector_PinHeader_2.54mm:PinHeader_2x08_P2.54mm_Vertical", side="top",
              rotation=0, pos=(87.5, 55.5), fixed=False, pins={}, shunts=[],
              missing="no shunt (every block but one): this block's lanes stay off the bus RBT")
for k in range(8):
    JP_RBT["pins"][2 * k + 1] = f"C_TX{k}"
    JP_RBT["pins"][2 * k + 2] = "RBT_SRC"
    JP_RBT["shunts"].append(dict(pads=[2 * k + 1, 2 * k + 2],
                                 means=f"lane {k}'s card is the exchange's ringback source: C_TX{k} drives RBT"))
JP_RBT["pads"] = place(hdr2(8), JP_RBT["pos"], 0)

# ----------------------------------------------------------------------------
# parts
OUTS = {"74HC244": {18, 16, 14, 12, 3, 5, 7, 9}, "74HC138": {15, 14, 13, 12, 11, 10, 9, 7},
        "74HC151": {5, 6}, "74HC688": {19}, "74HC164": {3, 4, 5, 6, 10, 11, 12, 13},
        "74HC175": {2, 3, 7, 6, 10, 11, 15, 14}, "74HC273": {2, 5, 6, 9, 12, 15, 16, 19},
        "74HC74": {5, 6, 9, 8}, "74HC14": {2, 4, 6, 8, 10, 12}, "74HC11": {12, 6, 8},
        "74HC02": {1, 4, 10, 13}, "74HC4002": {1, 13}, "74HC00": {3, 6, 8, 11}, "74HC157": {4, 7, 9, 12},
        "74HC595": {15, 1, 2, 3, 4, 5, 6, 7, 9}}
LIB = {"74HC244": "74xx:74HC244", "74HC138": "74xx:74HC138", "74HC151": "74xx:74LS151",
       "74HC688": "74xx:74HC688", "74HC164": "74xx:74HC164", "74HC175": "74xx:74LS175",
       "74HC273": "74xx:74HC273", "74HC74": "74xx:74HC74", "74HC14": "74xx:74HC14",
       "74HC11": "74xx:74LS11", "74HC02": "74xx:74HC02", "74HC4002": "4xxx:4002",
       "74HC00": "74xx:74HC00", "74HC157": "74xx:74LS157",
       "74HC595": "74xx:74HC595"}
PWR = {14: (14, 7), 16: (16, 8), 20: (20, 10)}
DIPN = {"74HC244": 20, "74HC138": 16, "74HC151": 16, "74HC688": 20, "74HC164": 14, "74HC175": 16,
        "74HC273": 20, "74HC74": 14, "74HC14": 14, "74HC11": 14, "74HC02": 14, "74HC4002": 14,
        "74HC00": 14, "74HC157": 16, "74HC595": 16}

def ic(ref, value, rtl, function, pins):
    n = DIPN[value]
    vcc, gnd = PWR[n]
    full = dict(pins)
    full[vcc] = "+5V"; full[gnd] = "GND"
    if value == "74HC4002":
        full[6] = "NC"; full[8] = "NC"
    assert sorted(full) == list(range(1, n + 1)), (ref, sorted(full))
    return dict(ref=ref, value=value, lib_id=LIB[value], footprint=f"Package_DIP:DIP-{n}_W7.62mm",
                rtl=rtl, function=function, pins={str(k): v for k, v in sorted(full.items())},
                outputs=sorted(OUTS[value]))

def b244(ref, rtl, fn, a1, y1, oe1, a2, y2, oe2):
    pins = {1: oe1, 19: oe2}
    for (ai, yi), x, y in zip([(2, 18), (4, 16), (6, 14), (8, 12)], a1, y1):
        pins[ai] = x; pins[yi] = y
    for (ai, yi), x, y in zip([(17, 3), (15, 5), (13, 7), (11, 9)], a2, y2):
        pins[ai] = x; pins[yi] = y
    return ic(ref, "74HC244", rtl, fn, pins)

def b151(ref, rtl, fn, d, s, g, z, zn):
    pins = {4: d[0], 3: d[1], 2: d[2], 1: d[3], 15: d[4], 14: d[5], 13: d[6], 12: d[7],
            11: s[0], 10: s[1], 9: s[2], 7: g, 5: z, 6: zn}
    return ic(ref, "74HC151", rtl, fn, pins)

def b688(ref, rtl, fn, g, P, Q, out):
    pins = {1: g, 19: out}
    for i, (pp, qq) in enumerate([(2, 3), (4, 5), (6, 7), (8, 9), (11, 12), (13, 14), (15, 16), (17, 18)]):
        pins[pp] = P[i]; pins[qq] = Q[i]
    return ic(ref, "74HC688", rtl, fn, pins)

def b138(ref, rtl, fn, a, e0n, e1n, e2, y):
    pins = {1: a[0], 2: a[1], 3: a[2], 4: e0n, 5: e1n, 6: e2}
    for k, pn in enumerate([15, 14, 13, 12, 11, 10, 9, 7]):
        pins[pn] = y[k]
    return ic(ref, "74HC138", rtl, fn, pins)

def b164(ref, rtl, fn, a, b, cp, mr, q):
    pins = {1: a, 2: b, 8: cp, 9: mr}
    for i, pn in enumerate([3, 4, 5, 6, 10, 11, 12, 13]):
        pins[pn] = q[i]
    return ic(ref, "74HC164", rtl, fn, pins)

def b14(ref, rtl, fn, pairs):
    pins = {}
    for (ai, yi), (x, y) in zip([(1, 2), (3, 4), (5, 6), (9, 8), (11, 10), (13, 12)], pairs):
        pins[ai] = x; pins[yi] = y
    return ic(ref, "74HC14", rtl, fn, pins)

def gates(ref, value, rtl, fn, units, layout):
    pins = {}
    for pinset, sig in zip(layout, units):
        ins, out = pinset
        for pn, x in zip(ins, sig[0]): pins[pn] = x
        pins[out] = sig[1]
    return ic(ref, value, rtl, fn, pins)

L11 = [((1, 2, 13), 12), ((3, 4, 5), 6), ((9, 10, 11), 8)]
L02 = [((2, 3), 1), ((5, 6), 4), ((8, 9), 10), ((11, 12), 13)]
L00 = [((1, 2), 3), ((4, 5), 6), ((9, 10), 8), ((12, 13), 11)]
L4002 = [((2, 3, 4, 5), 1), ((9, 10, 11, 12), 13)]

def res(ref, value, a, b, rtl, fn, fp="Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P2.54mm_Vertical"):
    return dict(ref=ref, value=value, lib_id="Device:R", footprint=fp, rtl=rtl, function=fn,
                pins={"1": a, "2": b})

def cap(ref, value, a, b, fn, fp="Capacitor_THT:C_Disc_D5.0mm_W2.5mm_P2.50mm", lib="Device:C"):
    return dict(ref=ref, value=value, lib_id=lib, footprint=fp, rtl="-", function=fn, pins={"1": a, "2": b})

def rnet(ref, value, common, nets, rtl, fn):
    n = len(nets)
    lib = "Device:R_Network08" if n == 8 else "Device:R_Network04"
    fp = "Resistor_THT:R_Array_SIP9" if n == 8 else "Resistor_THT:R_Array_SIP5"
    pins = {"1": common}
    for i, x in enumerate(nets): pins[str(i + 2)] = x
    return dict(ref=ref, value=value, lib_id=lib, footprint=fp, rtl=rtl, function=fn, pins=pins)

def rpack(refs, value, a, b, rtl, fn):
    """Eight isolated resistors as two R_Pack04_SIP (SIP-8, pins side by side):
    a DIP-16 pack is 21 mm of board for what two SIPs do in 3 mm strips."""
    out = []
    for h, ref in enumerate(refs):
        pins = {}
        for i in range(4):
            pins[str(2 * i + 1)] = a[4 * h + i]; pins[str(2 * i + 2)] = b[4 * h + i]
        out.append(dict(ref=ref, value=value, lib_id="Device:R_Pack04_SIP", footprint="Resistor_THT:R_Array_SIP8",
                        rtl=rtl, function=fn + (" (1 of 2)" if h == 0 else " (2 of 2)"), pins=pins))
    return out

def fet(ref, g, d, rtl, fn):
    return dict(ref=ref, value="2N7000", lib_id="Transistor_FET:2N7000", footprint="Package_TO_SOT_THT:TO-92_Inline",
                rtl=rtl, function=fn, pins={"1": "GND", "2": g, "3": d}, key_by="pin name (S, G, D)")

def diode(ref, a, k, fn):
    return dict(ref=ref, value="1N4148", lib_id="Device:D", footprint="Diode_THT:D_DO-35_SOD27_P2.54mm_Vertical_AnodeUp",
                rtl="port.v:175-188 (in the rc_det cluster)", function=fn, pins={"1": k, "2": a})

def conn(c, lib):
    d = dict(c)
    d["lib_id"] = lib
    return d

# ---- block header ---------------------------------------------------------------
H = []
H.append(b244("U1", "none (bus receivers)", "cell timing and SCLK in from the bus",
              ["B_HCLK", "B_SLOT0", "B_SLOT1", "B_SLOT2"], ["HCLK_R", "SLOT0_R", "SLOT1_R", "SLOT2_R"], "GND",
              ["B_SLOTQ0", "B_SLOTQ1", "B_SLOTQ2", "B_SCLK"], ["SLOTQ0_R", "SLOTQ1_R", "SLOTQ2_R", "SCLK_R"], "GND"))
H.append(b244("U2", "none (bus receivers)", "WR, SDATA, RBT, /RING_CAD, SCAN0-3 in",
              ["B_WR", "B_SDATA", "B_RBT", "B_RING_CAD_N"], ["WR_R", "SDATA_R", "RBT", "RING_CAD_N"], "GND",
              ["B_SCAN0", "B_SCAN1", "B_SCAN2", "B_SCAN3"], ["SCAN0", "SCAN1", "SCAN2", "SCAN3"], "GND"))
H.append(b244("U3", "none (bus receivers)", "SCAN4-5, HC0-5 in",
              ["B_SCAN4", "B_SCAN5", "B_HC0", "B_HC1"], ["SCAN4", "SCAN5", "HC0", "HC1"], "GND",
              ["B_HC2", "B_HC3", "B_HC4", "B_HC5"], ["HC2", "HC3", "HC4", "HC5"], "GND"))
H.append(b244("U4", "frame_decode.v:51 (FILL); block.v:77 (MUTE_BLK); port.v:27 (BLOCK)",
              "HC6-7 in; FILL and FILL_R off SCAN0; MUTE_BLK and H0-2 up the stack",
              ["B_HC6", "B_HC7", "SCAN0", "SCAN0"], ["HC6", "HC7", "FILL", "FILL_R"], "GND",
              ["A_MUTE_BLK", "H0_J", "H1_J", "H2_J"], ["MUTE_BLK", "H0", "H1", "H2"], "GND"))
H.append(b244("U5", "block.v:229-230 (the '244 after the commutator); block-stack.md 6 (the adapter commons)",
              "adapter commons out (half 1); HC_OUT, gated by FIT_N (half 2)",
              ["TX_CLK_S", "TX_OCT", "SCAN0", "HCLK_R"], ["A_TX_CLK_S", "A_TX_OCT_S", "A_FILL_S", "A_HCLK_S"], "GND",
              ["COMM", "GND", "GND", "GND"], ["HC_OUT_S", "NC", "NC", "NC"], "FIT_N"))
H.append(b14("U6", "block.v:63-64 (/HA Schmitt); port.v:38 (/RESET filtered); block.v:83 (/WS)",
             "Schmitt inputs: /HA -> HA_RX, /WS -> WS, RESET_RC -> RST -> RST_N",
             [("B_HA_N", "HA_RX"), ("B_WS_N", "WS"), ("RESET_RC", "RST"), ("RST", "RST_N"),
              ("GND", "NC"), ("GND", "NC")]))
H.append(b14("U7", "frame_decode.v:47 (TX_CLK); top_net.v:154 (LOOP_HB); block.v:267 (/WS clock)",
             "clean inversions: /SLOT2, /SLOT1, WS back to low-true (WS_C_N crosses to B on J8)",
             [("SLOT2_R", "TX_CLK_S"), ("SLOT1_R", "LOOP_HB_S"), ("WS", "WS_C_N"),
              ("GND", "NC"), ("GND", "NC"), ("GND", "NC")]))
H.append(gates("U8", "74HC11", "frame_decode.v:48", "TX_OCT = SCAN[2:0] == 7",
               [(("SCAN0", "SCAN1", "SCAN2"), "TX_OCT"), (("GND", "GND", "GND"), "NC"), (("GND", "GND", "GND"), "NC")], L11))
H.append(ic("U9", "74HC74", "frame_decode.v:49 (physically TX_OCT a frame late, bus.md 3)",
            "RX_OCT in two halves: TX_OCT taken as /STB4 rises (the start of cell 5, mid-frame), then "
            "onto the frame edge (TX_CLK rises).  Each D changes well away from its clock, so RX_OCT no "
            "longer races the clock card's '4040 ripple; both clocks come off the stack",
            {1: "+5V", 2: "TX_OCT", 3: "STB4_N", 4: "+5V", 5: "OCT_MID", 6: "NC",
             13: "+5V", 12: "OCT_MID", 11: "TX_CLK", 10: "+5V", 9: "RX_OCT", 8: "NC"}))
H.append(b164("U10", "block.v:89-100 (cw[7:0])", "control word, low byte: CLM BSY SRC0-5 up the stack",
              "SDATA_R", "+5V", "SCLK_R", "RST_N", ["CLM", "BSY", "SRC0", "SRC1", "SRC2", "SRC3", "SRC4", "SRC5"]))
H.append(b164("U11", "block.v:89-100 (cw[15:8])", "control word, high byte: DST0-5, spare, G",
              "SRC5", "+5V", "SCLK_R", "RST_N", ["DST0", "DST1", "DST2", "DST3", "DST4", "DST5", "NC", "G"]))
H.append(b688("U12", "block.v:102-104 (/BLK) and :110-113 (the guard G, on the spare pair)",
              "/BLK = !(FIT && DST[5:3]==h && G)", "FIT_N",
              ["DST3", "DST4", "DST5", "G", "GND", "GND", "GND", "GND"],
              ["H0", "H1", "H2", "+5V", "GND", "GND", "GND", "GND"], "BLK_N"))
H.append(b138("U13", "block.v:115-118 (write decoder)", "/WRk = /BLK . WR . G decoded by DST[2:0]",
              ["DST0", "DST1", "DST2"], "BLK_N", "GND", "WR_R", [f"WR{k}_S" for k in range(8)]))
H.append(b138("U14", "none in block.v: port.v:80-83, :101-106 assume it ('the block's '138')",
              "strobe decoder: /STBk low for ticks 4-7 of cell k",
              ["SLOTQ0_R", "SLOTQ1_R", "SLOTQ2_R"], "HCLK_R", "GND", "+5V", [f"STB{k}_S" for k in range(8)]))
H.append(b151("U15", "block.v:226-230 (THE commutator)", "C_TX lane k in cell k",
              [f"C_TX{k}" for k in range(8)], ["SLOT0_R", "SLOT1_R", "SLOT2_R"], "GND", "COMM", "NC"))
H.append(b688("U16", "block.v:261-268 (the /WS '688: SCAN[5:3] vs h)", "SELM_N = !(FIT && SCAN[5:3]==h)",
              "FIT_N", ["SCAN3", "SCAN4", "SCAN5", "GND", "GND", "GND", "GND", "GND"],
              ["H0", "H1", "H2", "GND", "GND", "GND", "GND", "GND"], "SELM_N"))
H.append(ic("U17", "74HC175", "block.v:263-270 (sel_v, sel_slot)", "the /WS latch, clocked at /STB4's fall while /WS is low.  The match goes in "
            "ACTIVE HIGH (U7 inverts the '688) and /SELV comes off /Q3, so a cleared latch -- after "
            "/RST -- reads NOT selected, as block.v's sel_v resets to 0",
            {1: "RST_N", 4: "SCAN0", 2: "SEL0", 3: "NC", 5: "SCAN1", 7: "SEL1", 6: "NC",
             12: "SCAN2", 10: "SEL2", 11: "NC", 13: "SELM", 15: "NC", 14: "SELV_N", 9: "WSCLK"}))
H.append(b151("U18", "block.v:272-273 (the word '151)", "WORD lane sel_slot",
              [f"WORD{k}" for k in range(8)], ["SEL0", "SEL1", "SEL2"], "GND", "WORD_Y", "NC"))
H.append(gates("U19", "74HC02", "block.v:237-238 (the plane OR, gated by FIT)",
               "HA_PD, HB_PD: the block-local planes onto the bus drains",
               [(("HA_L_N", "FIT_N"), "HA_PD"), (("HB_L_N", "FIT_N"), "HB_PD"),
                (("GND", "GND"), "NC"), (("GND", "GND"), "NC")], L02))
H.append(gates("U20", "74HC02", "block.v:273 (hw_pd); :259/:267 (the latch clock); :264 (the match, inverted)",
               "HW_PD (crosses to A on J8), WSCLK, SELM; LAMP_CK, the lamp '595s' shift clock",
               [(("SELV_N", "WORD_Y"), "HW_PD"), (("STB4_N", "WS_C_N"), "WSCLK"),
                (("SELM_N", "SELM_N"), "SELM"), (("STB4_N", "SELM_N"), "LAMP_CK")], L02))
# The lamps (Joel, 2026-09-26: 16 hook / BUSY lamps on B, driven by HC latches).
# In each of this block's eight frames /STB4 falls mid-frame with /SELM low, so
# LAMP_CK rises once per slot, in slot order, and shifts that slot's /HA_L (U21)
# and /HB_L (U22) into a '595.  /SELM's rise, as the scan leaves the block,
# copies all eight to the outputs at once: slot 0 has moved to Q7, slot 7 is Q0.
# A lamp is lit (Q low) while its card pulled the plane in its last turn: a pass
# (8 ms) behind, no scanning, DC.  /OE = /FIT: an unfitted block's lamps are dark.
def lamp_595(ref, plane, what):
    pins = {14: plane, 11: "LAMP_CK", 12: "SELM_N", 13: "FIT_N", 10: "+5V", 9: "NC"}
    for k in range(8):
        q = 7 - k
        pins[15 if q == 0 else q] = f"LAMP_{what}{k}"
    return ic(ref, "74HC595", "none: a display of " + ("port.v:112-123 (M on /HA_L)" if what == "M" else
                                                     "port.v:112-124 (BUSY on /HB_L)"),
              f"the {'M (hook)' if what == 'M' else 'BUSY'} lamps: slot k's {plane} in its turn -> LAMP_{what}k", pins)
H.append(lamp_595("U21", "HA_L_N", "M"))
H.append(lamp_595("U22", "HB_L_N", "B"))
H.append(fet("Q1", "HA_PD", "B_HA_N", "block.v:65, :237", "the block's one drain on /HA"))
H.append(fet("Q2", "HB_PD", "B_HB_N", "block.v:66, :238", "the block's one drain on /HB"))
H.append(fet("Q3", "HW_PD", "B_HW_N", "block.v:84, :273", "the block's drain on /HW"))
H.append(rnet("RN1", "4.7k", "FILL_R", [f"C_TX{k}" for k in range(8)], "block.v:124-131 (the ': fill' arm)",
              "an unfitted lane idles on FILL"))
H.append(rnet("RN2", "10k", "+5V", [f"WORD{k}" for k in range(8)], "block.v:136 (PORT_FITTED & ~word_n)",
              "an unfitted lane reads no word"))
H.extend(rpack(["RN3", "RN8"], "33", [f"STB{k}_S" for k in range(8)], [f"STB{k}_N" for k in range(8)], "-",
               "series resistors, strobe lines up the stack"))
H.extend(rpack(["RN4", "RN9"], "33", [f"WR{k}_S" for k in range(8)], [f"WR{k}_N" for k in range(8)], "-",
               "series resistors, write lanes up the stack"))
H.append(rnet("RN5", "100k", "GND", ["B_HCLK", "B_SLOT0", "B_SLOT1", "B_SLOT2", "B_SLOTQ0", "B_SLOTQ1",
                                     "B_SLOTQ2", "B_SCLK"], "-", "bus.md 6.1: an unplugged header reads idle"))
H.append(rnet("RN6", "100k", "GND", ["B_WR", "B_SDATA", "B_RESET_N", "NC"], "-",
              "bus.md 6.1: an unplugged header holds itself in reset and takes no write"))
H.append(rnet("RN7", "10k", "+5V", ["H0_J", "H1_J", "H2_J", "FIT_N"], "block.v:42-43 (BLOCK, JUMPERED)",
              "number jumper pull-ups: open reads 1"))
H.append(res("R1", "1k", "+5V", "HA_L_N", "block.v:237", "/HA_L pull-up"))
H.append(res("R2", "1k", "+5V", "HB_L_N", "block.v:238", "/HB_L pull-up"))
H.append(res("R3", "100", "HC_OUT_S", "HC_OUT", "block.v:230", "highway driver series R (bus.md 2.4)"))
H.append(res("R4", "33", "TX_CLK_S", "TX_CLK", "-", "series R, TX_CLK up the stack"))
H.append(res("R5", "33", "LOOP_HB_S", "LOOP_HB", "-", "series R, LOOP_HB up the stack"))
H.append(res("R6", "33", "A_TX_CLK_S", "A_TX_CLK", "-", "adapter series R"))
H.append(res("R7", "33", "A_TX_OCT_S", "A_TX_OCT", "-", "adapter series R"))
H.append(res("R8", "33", "A_FILL_S", "A_FILL", "-", "adapter series R"))
H.append(res("R9", "33", "A_HCLK_S", "A_HCLK", "-", "adapter series R"))
H.append(res("R10", "10k", "A_MUTE_BLK", "GND", "block.v:77", "MUTE_BLK pulled inactive"))
H.append(res("R11", "10k", "B_RESET_N", "RESET_RC", "port.v:38 ('filtered at the block')", "/RESET filter"))
H.append(res("R12", "100", "RBT_SRC", "B_RBT", "-", "RBT SOURCE series R: a bus driver's 100R (bus.md 2.4)"))
H.append(cap("C1", "100n", "RESET_RC", "GND", "/RESET filter, 1 ms (bus.md 6.2)"))
LAMP_FP = "telco:LED_D3.0mm_Horizontal_Row"
def led(ref, a, k, fn, fp, value="LED"):
    return dict(ref=ref, value=value, lib_id="Device:LED", footprint=fp, rtl="-", function=fn,
                pins={"1": k, "2": a}, sim=False)
for what, rn, first in (("M", "RN10", 0), ("B", "RN11", 1)):
    d = rnet(rn, "1k", "+5V", [f"LAMP_{what}{k}_A" for k in range(8)], "-",
             f"the {'M' if what == 'M' else 'BUSY'} lamps' current, ~2.9 mA each")
    d["sim"] = False
    H.append(d)
# Two groups in the row, each beside its '595 (Joel, 2026-09-26): hook D1-D8 on the
# left, BUSY D9-D16 on the right, slot 0 first in each, all at an even 5.0 mm, told
# apart by colour (hook green, BUSY orange, as on the hookbusy lamp card)
for k in range(8):
    H.append(led(f"D{k + 1}", f"LAMP_M{k}_A", f"LAMP_M{k}", f"slot {k} M (hook): lit = off-hook", LAMP_FP,
                 value="LED green"))
for k in range(8):
    H.append(led(f"D{k + 9}", f"LAMP_B{k}_A", f"LAMP_B{k}", f"slot {k} BUSY: lit = busy", LAMP_FP,
                 value="LED orange"))
for ref, r, line, what in (("D17", "R13", "FIT_N", "FIT: the NUMBER jumper's FIT shunt is in"),
                           ("D18", "R14", "RST_N", "RESET: /RST low"),
                           ("D19", "R15", "RING_CAD_N", "RING_CAD: the ringing cadence, lit while ringing may sound")):
    a = f"STAT_{ref}_A"
    d = res(r, "1.5k", "+5V", a, "-", f"status lamp {ref}, ~2 mA into {line}")
    d["sim"] = False
    H.append(d)
    H.append(led(ref, a, line, "status: " + what, "LED_THT:LED_D3.0mm"))
for i in range(20):
    H.append(cap(f"C{i+2}", "100n", "+5V", "GND", f"decoupling, U{i+1}", fp="Capacitor_THT:C_Disc_D3.0mm_W1.6mm_P2.50mm"))
for i, u in ((24, 21), (25, 22)):
    H.append(cap(f"C{i}", "100n", "+5V", "GND", f"decoupling, U{u}", fp="Capacitor_THT:C_Disc_D3.0mm_W1.6mm_P2.50mm"))
H.append(cap("C22", "47u", "+5V", "GND", "bulk at the bus entry; 4 x 7 mm",
             fp="Capacitor_THT:CP_Radial_D4.0mm_P1.50mm", lib="Device:C_Polarized"))
H.append(cap("C23", "10u", "+5V", "GND", "bulk on the logic board; <= 7 mm tall",
             fp="Capacitor_THT:CP_Radial_D4.0mm_P1.50mm", lib="Device:C_Polarized"))

# ---- the header is TWO boards (Joel, 2026-09-25): A, the bus board, at the
# bottom of the stack with the bus underneath; B, the logic board, on top of A
# on the same three stacking headers as a port card.  Everything B needs from
# A is a stack net but six, which ride a header-only link, J8.  A part's board:
HDR_A = {"U1", "U2", "U3", "U4", "U5", "U6", "U7", "U14", "U15", "U19",
         "Q1", "Q2", "Q3", "RN1", "RN3", "RN8", "RN5", "RN6", "RN7",
         "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R9", "R10", "R11", "R12", "C1", "C22"}
for p in H:
    if p["ref"].startswith("C") and p["function"].startswith("decoupling, "):
        u = p["function"].split(", ")[1]
        p["card"] = CA if u in HDR_A else CB
    else:
        p["card"] = CA if p["ref"] in HDR_A else CB
HA = [p for p in H if p["card"] == CA]
HB = [p for p in H if p["card"] == CB]

# ---- port card ------------------------------------------------------------------
P = []
P.append(ic("U1", "74HC273", "port.v:70-73, :190-194 (the listen latch; CLR = release or reset)",
            "addr[5:0], bsy, clm; clocked on /WR's leading edge",
            {1: "CLR_N", 3: "SRC0", 2: "ADDR0", 4: "SRC1", 5: "ADDR1", 7: "SRC2", 6: "ADDR2",
             8: "SRC3", 9: "ADDR3", 13: "SRC4", 12: "ADDR4", 14: "SRC5", 15: "ADDR5",
             17: "BSY", 16: "BSYQ", 18: "CLM", 19: "CLMQ", 11: "WRCLK"}))
P.append(b151("U2", "port.v:75-78 (highway select)", "C_SEL = HC[addr[5:3]]",
              [f"HC{i}" for i in range(8)], ["ADDR3", "ADDR4", "ADDR5"], "GND", "C_SEL", "NC"))
P.append(b151("U3", "port.v:80-83 (slot select; W is the capture clock)", "WC = W, rising at /STB[addr[2:0]]'s fall",
              [f"STB{i}_N" for i in range(8)], ["ADDR0", "ADDR1", "ADDR2"], "GND", "NC", "WC"))
P.append(b688("U4", "port.v:85-88 (eq_src)", "EQ_SRC_N = !(SCAN == addr)", "GND",
              ["SCAN0", "SCAN1", "SCAN2", "SCAN3", "SCAN4", "SCAN5", "GND", "GND"],
              ["ADDR0", "ADDR1", "ADDR2", "ADDR3", "ADDR4", "ADDR5", "GND", "GND"], "EQ_SRC_N"))
P.append(b688("U5", "port.v:90-99 (eq_own: SCAN vs {BLOCK, POS})", "EQ_OWN_N = !(SCAN == {h, POS})", "GND",
              ["SCAN0", "SCAN1", "SCAN2", "SCAN3", "SCAN4", "SCAN5", "GND", "GND"],
              ["POS0", "POS1", "POS2", "H0", "H1", "H2", "GND", "GND"], "EQ_OWN_N"))
P.append(ic("U6", "74HC74", "port.v:108, :169-173 (the '74 pair)", "C capture on WC; E capture on WA",
            {1: "RST_N", 2: "C_SEL", 3: "WC", 4: "+5V", 5: "C_RX", 6: "NC",
             13: "RST_N", 12: "HA_RX", 11: "WA", 10: "+5V", 9: "E", 8: "NC"}))
P.append(b14("U7", "port.v:134-136, :175-188 (the detectors and their CR squarers); port.v:109 (M)",
             "RC_M -> /FM, RC_E -> /FE -> FE, CR_M -> /REL_M, CR_E -> /REL_E, A_TX -> /M",
             [("RC_M", "FM_N"), ("RC_E", "FE_N"), ("FE_N", "FE"), ("CR_M", "REL_M_N"),
              ("CR_E", "REL_E_N"), ("E_A_TX", "M_N")]))
P.append(gates("U8", "74HC11", "port.v:144, :146, :193 (ON, RB, the clear)",
               "ON = RINGS./M./FM; RB = ON.E; /CLR = /REL_M./REL_E./RST",
               [(("E_ANS_N", "M_N", "FM_N"), "ON"), (("ON", "E", "+5V"), "RB"),
                (("REL_M_N", "REL_E_N", "RST_N"), "CLR_N")], L11))
P.append(gates("U9", "74HC02", "port.v:123-124 (drains), :105-106 (WA), :147 (fM./M)",
               "FMNM = FM./M; HA_G = EQ_OWN.M; HB_G = EQ_OWN.BUSY; WA = STB4.EQ_SRC",
               [(("FM_N", "E_A_TX"), "FMNM"), (("EQ_OWN_N", "M_N"), "HA_G"),
                (("EQ_OWN_N", "BUSY_N"), "HB_G"), (("STB4_N", "EQ_SRC_N"), "WA")], L02))
P.append(gates("U10", "74HC4002", "port.v:147 (BUSY); :131-132 (the '273 on WR's leading edge)",
               "/BUSY = NOR(BSY, FE, FM./M, MUTE_BLK); WRCLK = NOT /WR",
               [(("BSYQ", "FE", "FMNM", "MUTE_BLK"), "BUSY_N"), (("P_WR_N", "GND", "GND", "GND"), "WRCLK")], L4002))
P.append(gates("U11", "74HC00", "port.v:153 (A_RX)", "A_RX = (E + CLM) . /(ON . ring_cad_n)",
               [(("ON", "RING_CAD_N"), "RCX"), (("RCX", "E"), "N1"), (("RCX", "CLMQ"), "N2"), (("N1", "N2"), "A_RX")], L00))
P.append(ic("U12", "74HC157", "block.v:120-131 (ringback substitution), moved here", "P_C_TX = RB ? RBT : C_TX",
            {1: "RB", 2: "E_C_TX", 3: "RBT", 4: "P_C_TX", 5: "GND", 6: "GND", 7: "NC",
             11: "GND", 10: "GND", 9: "NC", 14: "GND", 13: "GND", 12: "NC", 15: "GND"}))
P.append(b244("U13", "none (socket drivers; port.v:153-154 for a9, a10)",
              "a1-a4, a7-a10 out through RN1",
              ["TX_CLK", "LOOP_HB", "TX_OCT", "FILL"], ["E_TX_CLK_S", "E_LOOP_HB_S", "E_TX_OCT_S", "E_FILL_S"], "GND",
              ["TX_CLK", "RX_OCT", "C_RX", "A_RX"], ["E_RX_CLK_S", "E_RX_OCT_S", "E_C_RX_S", "E_A_RX_S"], "GND"))
P.append(fet("Q1", "HA_G", "HA_L_N", "port.v:112-123", "M onto /HA_L in this port's turn"))
P.append(fet("Q2", "HB_G", "HB_L_N", "port.v:112-124", "BUSY onto /HB_L in this port's turn"))
P.extend(rpack(["RN1", "RN3"], "33", ["E_TX_CLK_S", "E_LOOP_HB_S", "E_TX_OCT_S", "E_FILL_S", "E_RX_CLK_S", "E_RX_OCT_S",
                             "E_C_RX_S", "E_A_RX_S"],
               ["E_TX_CLK", "E_LOOP_HB", "E_TX_OCT", "E_FILL", "E_RX_CLK", "E_RX_OCT", "E_C_RX", "E_A_RX"],
               "-", "series resistors into the ribbon"))
P.append(rnet("RN2", "10k", "+5V", ["POS0", "POS1", "POS2", "P_WR_N"], "port.v:28 (POS)",
              "POS pull-ups (open = 1); /WR held idle with no lane shunt"))
P.append(res("R1", "10k", "E_A_TX", "GND", "common/common-cards.md 1.4", "A_TX pull-down: a pulled card reads on-hook"))
P.append(res("R2", "680", "+5V", "E_WORD", "card-word.md 2", "card word pull-up"))
P.append(res("R3", "680", "+5V", "E_ANS_N", "port.v:138-142", "/ANS pull-up: open = rings"))
P.append(res("R4", "680", "+5V", "E_RAI_N", "common/common-cards.md 1.1", "a14 pull-up, unused"))
P.append(res("R5", "4.7k", "E_C_TX", "E_FILL", "common/common-cards.md 1.4", "a pulled subscriber card leaves FILL"))
P.append(diode("D1", "E_A_TX", "DET_M", "fM: the fast (charging) path"))
P.append(res("R6", "18k", "DET_M", "RC_M", "port.v:175-188", "fM up in ~16 ms (with C1)"))
P.append(res("R7", "270k", "E_A_TX", "RC_M", "port.v:175-188", "fM down in ~256 ms (with C1)"))
P.append(cap("C1", "1u", "RC_M", "GND", "fM timing", fp="Capacitor_THT:C_Rect_L7.2mm_W3.5mm_P5.00mm_FKS2_FKP2_MKS2_MKP2"))
P.append(diode("D2", "E", "DET_E", "fE: the fast path"))
P.append(res("R8", "18k", "DET_E", "RC_E", "port.v:175-188", "fE up in ~16 ms (with C2)"))
P.append(res("R9", "270k", "E", "RC_E", "port.v:175-188", "fE down in ~256 ms (with C2)"))
P.append(cap("C2", "1u", "RC_E", "GND", "fE timing", fp="Capacitor_THT:C_Rect_L7.2mm_W3.5mm_P5.00mm_FKS2_FKP2_MKS2_MKP2"))
P.append(cap("C3", "1n", "FM_N", "CR_M", "CR: /FM's rise (fM's fall) -> /REL_M, ~10 us"))
P.append(res("R10", "10k", "CR_M", "GND", "port.v:180, :193", "CR squarer"))
P.append(diode("D3", "GND", "CR_M", "clamps the CR node's negative swing"))
P.append(cap("C4", "1n", "FE_N", "CR_E", "CR: /FE's rise (fE's fall) -> /REL_E, ~10 us"))
P.append(res("R11", "10k", "CR_E", "GND", "port.v:186, :193", "CR squarer"))
P.append(diode("D4", "GND", "CR_E", "clamps the CR node's negative swing"))
for d in P:
    if d["ref"] in ("D3", "D4"): d["rtl"] = "port.v:190-194 (in the cr_rel cluster)"
for i in range(13):
    P.append(cap(f"C{i+5}", "100n", "+5V", "GND", f"decoupling, U{i+1}", fp="Capacitor_THT:C_Disc_D3.0mm_W1.6mm_P2.50mm"))
P.append(cap("C18", "10u", "+5V", "GND", "bulk; <= 7 mm tall", fp="Capacitor_THT:CP_Radial_D4.0mm_P1.50mm",
             lib="Device:C_Polarized"))

# connectors as parts
for c in STACK:
    pass

def conn_part(c, card, fp, lib):
    return dict(ref=c["ref"], value=c.get("role"), lib_id=lib, footprint=fp, rtl="-",
                function=c.get("role"), pins={str(k): v for k, v in c["pins"].items()})

# ----------------------------------------------------------------------------
# fan-out: count logic inputs per net per card
def loads(parts):
    cnt = collections.Counter()
    drv = collections.defaultdict(list)
    for p in parts:
        if "outputs" in p:
            for pn, n in p["pins"].items():
                if n in ("+5V", "GND", "NC"): continue
                if int(pn) in p["outputs"]: drv[n].append(f"{p['ref']}.{pn}")
                else: cnt[n] += 1
        elif p["value"] == "2N7000":
            cnt[p["pins"]["2"]] += 1
            drv[p["pins"]["3"]].append(f"{p['ref']}.D")
    return cnt, drv

hl, hd = loads(H)
pl, pd = loads(P)
# checks: every logic output net driven once per card, and across the header pair
_, had = loads(HA)
_, hbd = loads(HB)
for card, drv in ((CA, had), (CB, hbd), ("header pair", hd), (CP, pd)):
    for n, ds in drv.items():
        if n in ("HA_L_N", "HB_L_N", "B_HA_N", "B_HB_N", "B_HW_N"): continue
        assert len(ds) == 1, (card, n, ds)

FAN = []
for n in stack_signals:
    d = NETS[n]
    if d["group"] == "lane":
        per = 0
        rd = 1
    else:
        per = pl.get(n, 0)
    hdr_in = hl.get(n, 0)
    if d["group"] == "lane":
        k = d["lane"]
        if n.startswith("WR"): per_card_note = "the card on lane k: 1 ('4002) + 10k"
        elif n.startswith("C_TX"): per_card_note = "driven by the card on lane k"
        else: per_card_note = "driven (open drain) behind the card on lane k"
        c_pf = 10 + 5 * hdr_in + 8 * 7 + (5 if n.startswith("WR") else 0) + (20 if n.startswith("WORD") else 0)
        FAN.append(dict(net=n, group="lane", per_card=None, header_inputs=hdr_in, est_pf=c_pf, note=per_card_note))
    elif d["group"] == "wired":
        c_pf = 10 + 5 * hdr_in + 8 * (7 + 20)
        FAN.append(dict(net=n, group="wired", per_card=0, drains=8, header_inputs=hdr_in, est_pf=c_pf))
    else:
        c_pf = 10 + 5 * hdr_in + 8 * (7 + 5 * per)
        FAN.append(dict(net=n, group="common", per_card=per, header_inputs=hdr_in,
                        total_inputs=hdr_in + 8 * per, est_pf=c_pf))
    d["fanout"] = FAN[-1]

# which header board a net's named driver / pull sits on
_ref_card = {p["ref"]: p["card"] for p in H}
def _board(m):
    return f"{_ref_card.get(m.group(1), 'header')} {m.group(1)}"
for d in NETS.values():
    for k in ("driver", "note"):
        if isinstance(d.get(k), str):
            d[k] = re.sub(r"blockhdr (\w+)", _board, d[k])
    if isinstance(d.get("pull"), dict) and isinstance(d["pull"].get("at"), str):
        d["pull"]["at"] = re.sub(r"blockhdr (\w+)", _board, d["pull"]["at"])
    if d.get("card") == "blockhdr":
        # a header-local net lives on the board that drives it (or pulls it)
        refs = re.findall(rf"(?:{CA}|{CB}) (\w+)", str(d.get("driver", "")) + str(d.get("pull", "")))
        d["card"] = _ref_card.get(refs[0], CA) if refs else CA
for n in ("HW_PD",):
    NETS[n]["card"] = CB

# ----------------------------------------------------------------------------
# netlist check contract
NC = dict(
    module="block",
    source="newimpl/rtl/block.v:41-88 (parameters and ports, exactly)",
    parameters={
        "BLOCK": f"{CA} JP2 (NUMBER): shunt = 0, open = 1, h = {{H2_J,H1_J,H0_J}}; JP1 (HC ROUTE) at column h (checked statically)",
        "JUMPERED": f"{CA} JP2 FIT shunt: fitted = 1",
        "PORT_FITTED": "bit k = a port card is present whose JP1 POS reads k and whose JP2, JP3, JP4 shunts are all in column k",
        "T_ARM": "rc_det macro parameter on every detector cluster (sim only)",
        "T_REL": "rc_det macro parameter on every detector cluster (sim only)"},
    ports=[
        ("clk", "in", "sim only: the HCLK shim and the rc_det / cr_rel macro cells; nothing on the boards"),
        ("rst_n", "in", "B_RESET_N (bus pin 23); the R11/C1 filter is a wire in simulation"),
        ("slot[2:0]", "in", "B_SLOT0..2 (bus 5, 7, 9)"),
        ("slotq[2:0]", "in", "B_SLOTQ0..2 (bus 11, 13, 15)"),
        ("cap_stb", "in", "sim only: rebuilds B_HCLK through the shim"),
        ("frame_stb", "in", "unused (block.v:275-278), as in the RTL"),
        ("tick_1k", "in", "sim only: the rc_det time base"),
        ("scan[5:0]", "in", "B_SCAN0..5 (bus 27-32)"),
        ("fill", "in", "unused: the header takes FILL off B_SCAN0; the bench asserts fill == scan[0]"),
        ("rbt", "in", "B_RBT (bus 42)"),
        ("ring_cad_n", "in", "B_RING_CAD_N (bus 43)"),
        ("hc[7:0]", "in", "B_HC0..7 (bus 33-40)"),
        ("hc_out", "out", "HC_OUT (after R3, before JP1); JP1 is not in the module: mainboard.v:66-70 does the routing"),
        ("ha_n", "in", "B_HA_N (bus 44), read by U6"),
        ("ha_pd", "out", "HA_PD: the gate of Q1"),
        ("hb_pd", "out", "HB_PD: the gate of Q2"),
        ("c_tx[7:0]", "in", "port card k's E_C_TX (edge a5, J4 pin 9); ignored where PORT_FITTED[k] = 0"),
        ("a_tx[7:0]", "in", "port card k's E_A_TX (a6, J4 pin 11)"),
        ("ans_n[7:0]", "in", "port card k's E_ANS_N (a13, J4 pin 25)"),
        ("word_n[7:0]", "in", "port card k's E_WORD (a12, J4 pin 23)"),
        ("c_rx[7:0]", "out", "port card k's E_C_RX (a9, J4 pin 17, after RN1); 0 where PORT_FITTED[k] = 0"),
        ("a_rx[7:0]", "out", "port card k's E_A_RX (a10, J4 pin 19, after RN1); 0 where PORT_FITTED[k] = 0"),
        ("mute_blk", "in", "A_MUTE_BLK (adapter J6 pin 7)"),
        ("sdata", "in", "B_SDATA (bus 21)"),
        ("sclk", "in", "B_SCLK (bus 17)"),
        ("wr", "in", "B_WR (bus 19)"),
        ("ws_n", "in", "B_WS_N (bus 47)"),
        ("hw_pd", "out", "HW_PD: the gate of Q3"),
        ("port_busy[7:0]", "out", "!BUSY_N of port card k (its J5 pin 2); 0 where PORT_FITTED[k] = 0")],
    hclk_shim="reg [1:0] n; always @(posedge clk or negedge rst_n) n <= !rst_n ? 0 : cap_stb ? 3 : (n != 0 ? n - 1 : 0); "
              "B_HCLK = !(cap_stb || n != 0)  -- low for ticks 4-7 exactly as clock_card.v:72",
    sim_only=["clk", "cap_stb -> B_HCLK shim", "tick_1k", "rc_det: D1/R6/R7/C1/U7.1 and D2/R8/R9/C2/U7.2 become a counter on tick_1k "
              "with T_ARM/T_REL (port.v:175-188); outputs FM_N / FE_N",
              "cr_rel: C3/R10/D3/U7.4 and C4/R11/D4/U7.5 become REL_*_N low for one clk, one clk after the detector falls (port.v:166, :180, :186)",
              "R11/C1 (/RESET RC) is a wire", "SCAN delayed ~50 ns against SLOT2 in the harness (the '4040 ripple RX_OCT relies on)",
              "model delays are procedural (<= #d), never 'assign #d' (pcb/out/synth_dly)"],
    compare=["hc_out at ticks 5-7 of every cell, where JUMPERED",
             "ha_pd, hb_pd, hw_pd and port_busy at CELL_A (exch.vh:315)",
             "c_rx, a_rx at frame_stb",
             "masked: the first pass after reset plus T_ARM; the frame after a write to that port (the '273 clocks at /WR's edge, one clk before port.v's wr_edge; and a slot select moved onto a low strobe gives one extra W edge)",
             "each card's a1-a4, a7, a8 against a reference frame_decode (the benches never read them)"],
    strap_rules=["every fitted card: POS == JP2 column == JP3 column == JP4 column",
                 "no two cards on one lane",
                 f"{CA}: JP1 column == NUMBER h, when FIT is fitted",
                 f"{CA}: JP3 (RBT SOURCE) open in simulation: the bench drives rbt, as block.v's input"],
    mutations=["two lane shunts of one card in different columns", "two cards on one lane",
               "RN1 removed", "U18 select pins swapped", "JP1 in a column other than h",
               "FIT open (the block must go silent and still listen)", "Q1 drain on HB_L_N"],
)

# ----------------------------------------------------------------------------
DOC = dict(
    schema="telco/block-stack 1",
    spec="exchange/block-stack.md",
    date="2026-09-26",
    status="proposed; nothing drawn, nothing on a bench",
    conventions=dict(
        units="mm",
        coords="board-local top view in KiCad's sense: +x right, +y toward the FRONT edge; origin = back-left corner; back edge y = 0, front edge y = 100, left x = 0, right x = 100",
        rotation="KiCad footprint orientation, degrees CCW as displayed; a pad's position = pos + (x cos a + y sin a, -x sin a + y cos a) from the footprint's own pad coordinates",
        bottom="B.Cu parts: pads are given in the same top-view coordinates; place, then assert every pad",
        pads="'pads' is the contract where fixed is true (the stack, the link, the bus and edge IDCs): a generator asserts every pad within 0.01 mm. Where fixed is false (test strips, the adapter header, every jumper) the part is placed with the board, and pos / rotation / pads record where",
        active_low="a doc name /X is the net label X_N",
        labels="every net in 'nets' is a global label of exactly this name, in both schematics",
        shunt="a shunt pulls its net to GND and reads 0; an open position reads 1 through 10k",
        nc="'NC' = no connection; the pin is left open (no-connect flag)"),
    mechanical=dict(
        outline=[100.0, 100.0], thickness=1.6, corner_radius=0.0,
        holes=[dict(ref="H1", xy=[3.5, 3.5]), dict(ref="H2", xy=[93.5, 3.5], note="the offset hole: 3 mm in from the corner position, the key"),
               dict(ref="H3", xy=[3.5, 96.5]), dict(ref="H4", xy=[96.5, 96.5])],
        hole_footprint="MountingHole:MountingHole_3.2mm_M3",
        standoffs="M3 x 11 mm between layers; M3 x 20 mm from the block header to the plate",
        gap=11.0, pitch=12.6,
        stack_part="single-piece long-tail 2x25 stacking header, 2.54 mm, 8.5 mm body, >= 10 mm tail (RPi-HAT class; Samtec SSQ-125-03-G-D as the gold upgrade)",
        header_stack_part="plain 2x25 female socket, 8.5 mm body, same holes",
        max_part_height_top=9.0, max_lead_protrusion_bottom=1.5,
        stack_columns="J1 at the left edge, J2 at the right, both pads y 27.0-87.96 (front-aligned, 7.3 mm clear of the front holes), pin 1 at the back end",
        front_edge="the port card's edge IDC, header A's bus IDC, header B's test strip; each right-angle IDC shroud is ~9 mm tall under the card above, whose leads over it are trimmed to 1 mm",
        back_edge="lamps (header B, the port card) and test strips (header A, the port card); header A's adapter commons",
        jumpers="vertical, in the interior beside the logic each sets, low-profile shunts; set with the boards above lifted off"),
    nets=list(NETS.values()),
    stack_connectors=[dict(ref=c["ref"], role=c["role"], edge=c["edge"], cards=[CA, CB, CP], fixed=True,
                           footprint=STACK_FP, side="top", rotation=c["rotation"], pos=list(c["pos"]),
                           pad1=c["pad1"], outer_row=c["outer_row"],
                           pins={str(k): v for k, v in sorted(c["pins"].items())},
                           pads={str(k): v for k, v in sorted(c["pads"].items())}) for c in STACK],
    connectors=[dict(ref=c["ref"], card=c["card"], role=c["role"], footprint=c["footprint"], side=c["side"],
                     rotation=c["rotation"], pos=list(c["pos"]), pad1=c.get("pad1"), note=c.get("note"),
                     pins={str(k): v for k, v in sorted(c["pins"].items())},
                     pads={str(k): v for k, v in sorted(c["pads"].items())},
                     fixed=c.get("fixed", True))
                for c in (EDGE, TPS[0], BUS_J, ADAPT, TPS[1], TPS[2], LINK_A, LINK_B)],
    jumpers=[dict(ref=j["ref"], card=j["card"], label=j["label"], footprint=j["footprint"], side=j["side"],
                  rotation=j["rotation"], pos=list(j["pos"]),
                  pins={str(k): v for k, v in sorted(j["pins"].items())},
                  pads={str(k): v for k, v in sorted(j["pads"].items())},
                  shunts=j["shunts"], missing=j["missing"])
             for j in (JP_POS, JP_WR, JP_CTX, JP_WORD, JP_HC, JP_NUM, JP_RBT)],
    cards={
        CA: dict(project=f"pcb/{CA}/{CA}.kicad_pro", layers=2,
                 note="block header A, the bus board: the bottom of the stack, the bus IDC at its front edge",
                 parts=HA),
        CB: dict(project=f"pcb/{CB}/{CB}.kicad_pro", layers=2,
                 note="block header B, the logic board: on A like a port card, J8 underneath into A; the lamps",
                 parts=HB),
        CP: dict(project=f"pcb/{CP}/{CP}.kicad_pro", layers=2,
                 note="the port card, drawn by hand from this first draft (parts: the draft's; the board adds port-state LEDs)",
                 parts=P)},
    fanout=FAN,
    netlist_check=NC,
)

# label/ref sanity: every net used by a part that is canonical is in NETS; list local nets
def used(parts):
    s = set()
    for p in parts:
        for v in p["pins"].values(): s.add(v)
    return s
hu, pu = used(H), used(P)
hau, hbu = used(HA), used(HB)
for c in (EDGE, TPS[0]): pu |= set(c["pins"].values())
for c in (BUS_J, ADAPT, TPS[1], LINK_A): hu |= set(c["pins"].values()); hau |= set(c["pins"].values())
for c in (TPS[2], LINK_B): hu |= set(c["pins"].values()); hbu |= set(c["pins"].values())
for j in (JP_POS, JP_WR, JP_CTX, JP_WORD): pu |= set(j["pins"].values())
for j in (JP_HC, JP_NUM, JP_RBT): hu |= set(j["pins"].values()); hau |= set(j["pins"].values())
for c in STACK:
    hu |= set(c["pins"].values()); pu |= set(c["pins"].values())
    hau |= set(c["pins"].values()); hbu |= set(c["pins"].values())
DOC["local_nets"] = {CA: sorted(n for n in hau if n not in NETS and n != "NC"),
                     CB: sorted(n for n in hbu if n not in NETS and n != "NC"),
                     CP: sorted(n for n in pu if n not in NETS and n != "NC")}
# a net used on both header boards must be a stack net or a link net
_link = set(LINK_PINS.values())
_stack = {n for c in STACK for n in c["pins"].values()}
for n in (used(HA) & used(HB)) - {"+5V", "GND", "NC"}:
    assert n in _stack or n in _link, ("crosses between the header boards off the stack and the link", n)
# each stack signal must be used on the header by a part and on the port card by a part (except spares)
hp = used(H); pp = used(P)
for n in stack_signals:
    assert n in hp, ("header does not touch", n)
    if NETS[n]["group"] == "lane":
        continue
    assert n in pp, ("port card does not touch", n)
# lanes reach the port card through the jumpers
for n in stack_signals:
    if NETS[n]["group"] == "lane":
        assert any(n in j["pins"].values() for j in (JP_WR, JP_CTX, JP_WORD)), n
# every canonical card-local net exists on its card
for n, d in NETS.items():
    if d.get("card") in (CA, CB): assert n in hu, n
    if d.get("card") == CP: assert n in pu, n

json.dump(DOC, open(OUT_JSON, "w"), indent=1)

# ----------------------------------------------------------------------------
# markdown fragments
md = []
def pin_table(c, title):
    md.append(f"#### {title}\n")
    md.append("| pins | odd | even | | pins | odd | even |")
    md.append("|---|---|---|---|---|---|---|")
    pins = c["pins"]
    n = len(pins) // 2
    half = (n + 1) // 2
    def lab(x):
        d = NETS.get(x)
        s = d["doc"] if d else x
        if d and d.get("fast"): s = f"**`{s}`**"
        elif x in ("+5V", "GND"): s = x.replace("+5V", "+5 V")
        elif x == "NC": s = "—"
        else: s = f"`{s}`"
        return s
    rows = []
    for i in range(n):
        rows.append((f"{2*i+1}–{2*i+2}", lab(pins[2 * i + 1]), lab(pins[2 * i + 2])))
    for i in range(half):
        a = rows[i]
        b = rows[i + half] if i + half < n else ("", "", "")
        md.append(f"| {a[0]} | {a[1]} | {a[2]} | | {b[0]} | {b[1]} | {b[2]} |")
    md.append("")

for c in STACK:
    pin_table(c, f"{c['ref']} — {c['edge']}")
pin_table(dict(pins=BUS), "bus")
pin_table(dict(pins=ADP), "adapter")

md.append("#### fanout\n")
md.append("| net | per port card | header | est. pF |")
md.append("|---|---|---|---|")
for f in FAN:
    if f["group"] == "common":
        md.append(f"| `{NETS[f['net']]['doc']}` | {f['per_card']} | {f['header_inputs']} | {f['est_pf']} |")
    else:
        md.append(f"| `{NETS[f['net']]['doc']}` | {f.get('note','8 drains')} | {f['header_inputs']} | {f['est_pf']} |")
md.append("")
md.append("#### pads\n")
for c in STACK + [EDGE, TPS[0], BUS_J, ADAPT, TPS[1], TPS[2], JP_POS, JP_WR, JP_CTX, JP_WORD, JP_HC, JP_NUM, JP_RBT]:
    pads = c["pads"]
    last = max(pads)
    md.append(f"{c.get('card','both')} {c['ref']} rot {c['rotation']} pad1 {pads[1]} pad2 {pads[2]} pad3 {pads[3]} last {last} {pads[last]}")
md.append("")
md.append("#### local nets\n")
md.append(json.dumps(DOC["local_nets"], indent=0))
open(OUT_MD, "w").write("\n".join(md))
print("ok", len(NETS), "nets;", len(H), "header parts;", len(P), "port parts")
print("header DIP", sum(1 for p in H if p['ref'].startswith('U')), "port DIP", sum(1 for p in P if p['ref'].startswith('U')))

#!/usr/bin/env python3
"""Build hook/busy lamp_card and interface_card KiCad PCBs (placement + outline).

Schematics are written as companion .kicad_sch files; nets on the PCB match
reference designators so Update from Schematic can associate later.
"""
from __future__ import annotations

import json
import uuid
from pathlib import Path

import pcbnew
from pcbnew import (
    BOARD,
    FOOTPRINT,
    PCB_SHAPE,
    PCB_TEXT,
    VECTOR2I,
    FromMM,
    ToMM,
    Edge_Cuts,
    F_SilkS,
    B_SilkS,
    F_Cu,
    B_Cu,
    SHAPE_T_SEGMENT,
    FP_THROUGH_HOLE,
)

ROOT = Path("/home/joel/telco/pcb/hookbusy")
FP_DIP = "/usr/share/kicad/footprints/Package_DIP.pretty"
FP_LED = "/usr/share/kicad/footprints/LED_THT.pretty"
FP_HDR = "/usr/share/kicad/footprints/Connector_PinHeader_2.54mm.pretty"
FP_RES = "/usr/share/kicad/footprints/Resistor_THT.pretty"
FP_C = "/usr/share/kicad/footprints/Capacitor_THT.pretty"


def mm(x, y=None):
    if y is None:
        return FromMM(x)
    return VECTOR2I(FromMM(x), FromMM(y))


def add_rect_edge(board, w_mm, h_mm):
    w, h = FromMM(w_mm), FromMM(h_mm)
    corners = [(0, 0), (w, 0), (w, h), (0, h), (0, 0)]
    for (x1, y1), (x2, y2) in zip(corners, corners[1:]):
        seg = PCB_SHAPE(board)
        seg.SetShape(SHAPE_T_SEGMENT)
        seg.SetLayer(Edge_Cuts)
        seg.SetStart(VECTOR2I(x1, y1))
        seg.SetEnd(VECTOR2I(x2, y2))
        seg.SetWidth(FromMM(0.1))
        board.Add(seg)


def silk(board, text, x, y, size=1.0, layer=F_SilkS):
    t = PCB_TEXT(board)
    t.SetText(text)
    t.SetPosition(mm(x, y))
    t.SetTextSize(VECTOR2I(FromMM(size), FromMM(size)))
    t.SetLayer(layer)
    board.Add(t)


def load_fp(board, lib_path, name, ref, x, y, rot=0, flip=False):
    fp = pcbnew.FootprintLoad(lib_path, name)
    if fp is None:
        raise RuntimeError(f"missing footprint {lib_path}/{name}")
    fp.SetParent(board)
    fp.SetReference(ref)
    fp.SetPosition(mm(x, y))
    fp.SetOrientationDegrees(rot)
    if flip:
        fp.Flip(fp.GetPosition(), False)
    board.Add(fp)
    return fp


def ensure_net(board, name):
    n = board.FindNet(name)
    if n is None:
        n = pcbnew.NETINFO_ITEM(board, name)
        board.Add(n)
        n = board.FindNet(name)
    return n


def set_pad_net(board, fp, pad_num, netname):
    net = ensure_net(board, netname)
    pad = None
    for p in fp.Pads():
        if p.GetNumber() == str(pad_num):
            pad = p
            break
    if pad is None:
        raise RuntimeError(f"{fp.GetReference()} missing pad {pad_num}")
    pad.SetNet(net)

def build_lamp_card():
    board = BOARD()
    settings = board.GetDesignSettings()
    settings.SetBoardThickness(FromMM(1.6))

    # 50 mm deep (X, front→back) × 100 mm tall (Y, s=0→s=7)
    W, H = 50.0, 100.0
    add_rect_edge(board, W, H)
    silk(board, "LAMP CARD", 25, 2, 1.2)
    silk(board, "hookbusy.md", 25, 4, 0.8)
    silk(board, "FRONT", 3, 2, 0.8)
    silk(board, "0.4in pitch", 38, 98, 0.7)

    pitch = 10.16  # 0.4"
    y0 = (H - 7 * pitch) / 2  # centre the 8-LED column on 100 mm

    # Single front-edge LED hole set (D1…D8)
    for s in range(8):
        y = y0 + s * pitch
        led = load_fp(board, FP_LED, "LED_D5.0mm", f"D{s+1}", 3.0, y, rot=90)
        led.SetValue(f"LED_s{s}")

        r = load_fp(
            board,
            FP_RES,
            "R_Axial_DIN0207_L6.3mm_D2.5mm_P7.62mm_Horizontal",
            f"R{s+1}",
            11.0,
            y,
            rot=90,
        )
        r.SetValue("1k5")

        ensure_net(board, f"Q{s}")
        ensure_net(board, "GND")
        ensure_net(board, f"LED{s}")
        set_pad_net(board, r, "1", f"Q{s}")
        set_pad_net(board, r, "2", f"LED{s}")
        # LED_D5.0mm: pad 1 = K, pad 2 = A
        set_pad_net(board, led, "2", f"LED{s}")
        set_pad_net(board, led, "1", "GND")

    # 74HC259
    u1 = load_fp(board, FP_DIP, "DIP-16_W7.62mm", "U1", 28.0, 50.0, rot=90)
    u1.SetValue("74HC259")
    ensure_net(board, "+5V")
    q_pins = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 9: 7}
    for pin, s in q_pins.items():
        set_pad_net(board, u1, pin, f"Q{s}")
    set_pad_net(board, u1, 8, "GND")
    set_pad_net(board, u1, 16, "+5V")
    set_pad_net(board, u1, 10, "LE_N")  # /G
    set_pad_net(board, u1, 11, "D")
    set_pad_net(board, u1, 12, "SLOTQ0")
    set_pad_net(board, u1, 13, "SLOTQ1")
    set_pad_net(board, u1, 14, "SLOTQ2")
    set_pad_net(board, u1, 15, "CLR_N")

    c1 = load_fp(
        board,
        FP_C,
        "C_Disc_D5.0mm_W2.5mm_P5.00mm",
        "C1",
        36.0,
        50.0,
    )
    c1.SetValue("100n")
    set_pad_net(board, c1, "1", "+5V")
    set_pad_net(board, c1, "2", "GND")

    # BLK shunt fields: 2x8 HA and 2x8 LEB
    blk_ha = load_fp(board, FP_HDR, "PinHeader_2x08_P2.54mm_Vertical", "JP1", 28.0, 14.0)
    blk_ha.SetValue("BLK_HA")
    blk_leb = load_fp(board, FP_HDR, "PinHeader_2x08_P2.54mm_Vertical", "JP2", 28.0, 86.0)
    blk_leb.SetValue("BLK_LEB")
    silk(board, "BLK 0-7", 28, 6, 0.8)
    ensure_net(board, "D_HOOK")
    ensure_net(board, "LE_BUSY_N")
    for i in range(8):
        top = 1 + i * 2
        bot = 2 + i * 2
        ensure_net(board, f"HA{i}")
        ensure_net(board, f"LEB{i}")
        set_pad_net(board, blk_ha, top, f"HA{i}")
        set_pad_net(board, blk_ha, bot, "D_HOOK")
        set_pad_net(board, blk_leb, top, f"LEB{i}")
        set_pad_net(board, blk_leb, bot, "LE_BUSY_N")

    # MODE: three 1x3 — HOOK | COMMON | BUSY for D, /LE, /CLR
    for name, ref, y, hook_net, mid_net, busy_net in [
        ("D", "JP3", 35.0, "D_HOOK", "D", "PB0"),
        ("LE", "JP4", 50.0, "HCLK", "LE_N", "LE_BUSY_N"),
        ("CLR", "JP5", 65.0, "+5V", "CLR_N", "RESET_N"),
    ]:
        jp = load_fp(board, FP_HDR, "PinHeader_1x03_P2.54mm_Vertical", ref, 18.0, y)
        jp.SetValue(f"MODE_{name}")
        silk(board, name, 14, y, 0.7)
        set_pad_net(board, jp, "1", hook_net)
        set_pad_net(board, jp, "2", mid_net)
        set_pad_net(board, jp, "3", busy_net)
    silk(board, "H  C  B", 18, 28, 0.7)

    # Stack headers at back edge
    j_ha = load_fp(board, FP_HDR, "PinHeader_1x08_P2.54mm_Vertical", "J1", 44.0, 22.0)
    j_ha.SetValue("HA")
    j_leb = load_fp(board, FP_HDR, "PinHeader_1x08_P2.54mm_Vertical", "J2", 44.0, 42.0)
    j_leb.SetValue("LEB")
    j_pwr = load_fp(board, FP_HDR, "PinHeader_1x04_P2.54mm_Vertical", "J3", 44.0, 60.0)
    j_pwr.SetValue("PWR")
    j_ctl = load_fp(board, FP_HDR, "PinHeader_1x06_P2.54mm_Vertical", "J4", 44.0, 78.0)
    j_ctl.SetValue("control")
    silk(board, "STACK", 44, 10, 0.8)

    for i in range(8):
        set_pad_net(board, j_ha, i + 1, f"HA{i}")
        set_pad_net(board, j_leb, i + 1, f"LEB{i}")
    set_pad_net(board, j_pwr, 1, "+5V")
    set_pad_net(board, j_pwr, 2, "GND")
    set_pad_net(board, j_pwr, 3, "+5V")
    set_pad_net(board, j_pwr, 4, "GND")
    for i, net in enumerate(["SLOTQ0", "SLOTQ1", "SLOTQ2", "HCLK", "PB0", "RESET_N"], 1):
        ensure_net(board, net)
        set_pad_net(board, j_ctl, i, net)

    out = ROOT / "lamp_card" / "lamp_card.kicad_pcb"
    board.Save(str(out))
    print("wrote", out)
    return board


def build_interface_card():
    board = BOARD()
    settings = board.GetDesignSettings()
    settings.SetBoardThickness(FromMM(1.6))
    # Same outline: 50 deep × 100 tall; front edge is legend (no LEDs)
    W, H = 50.0, 100.0
    add_rect_edge(board, W, H)
    silk(board, "INTERFACE", 25, 2, 1.2)
    silk(board, "hookbusy.md 3", 25, 4, 0.8)
    silk(board, "LEGEND", 3, 50, 1.0)
    silk(board, "s=0", 3, 12, 0.8)
    silk(board, "s=7", 3, 88, 0.8)

    ensure_net(board, "+5V")
    ensure_net(board, "GND")

    u_164a = load_fp(board, FP_DIP, "DIP-14_W7.62mm", "U1", 18.0, 20.0, rot=0)
    u_164a.SetValue("74HC164")
    u_164b = load_fp(board, FP_DIP, "DIP-14_W7.62mm", "U2", 18.0, 40.0, rot=0)
    u_164b.SetValue("74HC164")
    u_138 = load_fp(board, FP_DIP, "DIP-16_W7.62mm", "U3", 18.0, 62.0, rot=0)
    u_138.SetValue("74HC138")
    u_123 = load_fp(board, FP_DIP, "DIP-16_W7.62mm", "U4", 32.0, 28.0, rot=0)
    u_123.SetValue("74HC123")
    u_244 = load_fp(board, FP_DIP, "DIP-20_W7.62mm", "U5", 32.0, 55.0, rot=0)
    u_244.SetValue("74HC244")

    for u, gnd, vcc in [(u_164a, 7, 14), (u_164b, 7, 14), (u_138, 8, 16), (u_123, 8, 16), (u_244, 10, 20)]:
        set_pad_net(board, u, gnd, "GND")
        set_pad_net(board, u, vcc, "+5V")

    for i, (x, y) in enumerate([(26, 20), (26, 40), (26, 62), (40, 28), (40, 55)], 1):
        c = load_fp(board, FP_C, "C_Disc_D5.0mm_W2.5mm_P5.00mm", f"C{i}", x, y)
        c.SetValue("100n")
        set_pad_net(board, c, "1", "+5V")
        set_pad_net(board, c, "2", "GND")

    j_ca = load_fp(board, FP_HDR, "PinHeader_2x08_P2.54mm_Vertical", "J5", 8.0, 22.0)
    j_ca.SetValue("CABLE_A_TAP")
    j_cb = load_fp(board, FP_HDR, "PinHeader_2x05_P2.54mm_Vertical", "J6", 8.0, 48.0)
    j_cb.SetValue("CABLE_B_TAP")
    silk(board, "to exchange", 8, 10, 0.7)

    j_ha = load_fp(board, FP_HDR, "PinHeader_1x08_P2.54mm_Vertical", "J1", 44.0, 22.0)
    j_ha.SetValue("HA")
    j_leb = load_fp(board, FP_HDR, "PinHeader_1x08_P2.54mm_Vertical", "J2", 44.0, 42.0)
    j_leb.SetValue("LEB")
    j_pwr = load_fp(board, FP_HDR, "PinHeader_1x04_P2.54mm_Vertical", "J3", 44.0, 60.0)
    j_pwr.SetValue("PWR")
    j_ctl = load_fp(board, FP_HDR, "PinHeader_1x06_P2.54mm_Vertical", "J4", 44.0, 78.0)
    j_ctl.SetValue("control")
    silk(board, "STACK ->", 44, 10, 0.8)

    for i in range(8):
        ensure_net(board, f"HA{i}")
        ensure_net(board, f"LEB{i}")
        set_pad_net(board, j_ha, i + 1, f"HA{i}")
        set_pad_net(board, j_leb, i + 1, f"LEB{i}")
    set_pad_net(board, j_pwr, 1, "+5V")
    set_pad_net(board, j_pwr, 2, "GND")
    set_pad_net(board, j_pwr, 3, "+5V")
    set_pad_net(board, j_pwr, 4, "GND")
    for i, net in enumerate(["SLOTQ0", "SLOTQ1", "SLOTQ2", "HCLK", "PB0", "RESET_N"], 1):
        ensure_net(board, net)
        set_pad_net(board, j_ctl, i, net)

    j_pwr_in = load_fp(board, FP_HDR, "PinHeader_1x02_P2.54mm_Vertical", "J7", 8.0, 78.0)
    j_pwr_in.SetValue("PWR_IN")
    set_pad_net(board, j_pwr_in, "1", "+5V")
    set_pad_net(board, j_pwr_in, "2", "GND")
    silk(board, "+5V IN", 8, 72, 0.7)

    rinh = load_fp(
        board,
        FP_RES,
        "R_Axial_DIN0207_L6.3mm_D2.5mm_P7.62mm_Horizontal",
        "R1",
        32.0,
        14.0,
    )
    rinh.SetValue("TBD_INH")
    cinh = load_fp(board, FP_C, "C_Disc_D5.0mm_W2.5mm_P5.00mm", "C6", 40.0, 14.0)
    cinh.SetValue("TBD_INH")

    out = ROOT / "interface_card" / "interface_card.kicad_pcb"
    board.Save(str(out))
    print("wrote", out)


def write_pro(path: Path, name: str, pcb: str, sch: str):
    # Minimal KiCad 10 project
    pro = {
        "meta": {"filename": f"{name}.kicad_pro", "version": 3},
        "board": {
            "design_settings": {},
        },
        "sheets": [[name, sch]],
        "text_variables": {},
    }
    path.write_text(json.dumps(pro, indent=2))
    print("wrote", path)


def write_minimal_sch(path: Path, title: str):
    """Placeholder sheet pointing layout is authoritative for v1."""
    uid = str(uuid.uuid4())
    content = f'''(kicad_sch
	(version 20250114)
	(generator "eeschema")
	(generator_version "10.0")
	(uuid "{uid}")
	(paper "A3")
	(title_block
		(title "{title}")
		(comment 1 "hookbusy.md — nets live on the PCB for this pass")
		(comment 2 "Open the .kicad_pcb; draw the schematic next to match refs")
	)
	(lib_symbols)
	(sheet_instances
		(path "/"
			(page "1")
		)
	)
	(embedded_fonts no)
)
'''
    path.write_text(content)
    print("wrote", path)


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    (ROOT / "lamp_card").mkdir(exist_ok=True)
    (ROOT / "interface_card").mkdir(exist_ok=True)

    build_lamp_card()
    build_interface_card()

    write_pro(
        ROOT / "lamp_card" / "lamp_card.kicad_pro",
        "lamp_card",
        "lamp_card.kicad_pcb",
        "lamp_card.kicad_sch",
    )
    write_pro(
        ROOT / "interface_card" / "interface_card.kicad_pro",
        "interface_card",
        "interface_card.kicad_pcb",
        "interface_card.kicad_sch",
    )
    write_minimal_sch(ROOT / "lamp_card" / "lamp_card.kicad_sch", "Hook/busy lamp card")
    write_minimal_sch(
        ROOT / "interface_card" / "interface_card.kicad_sch", "Hook/busy interface card"
    )


if __name__ == "__main__":
    main()

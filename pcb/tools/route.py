#!/usr/bin/env python3
"""route.py -- headless autoroute: board -> DSN -> Freerouting -> SES -> board, GND pour.

    python3 route.py CARD/CARD.kicad_pcb CARD/CARD.kicad_pcb [passes] [--drop=GND]

The routed board must keep the schematic's basename (routed/toy.kicad_pcb next
to toy.kicad_sch/.kicad_pro), or DRC --schematic-parity cannot find the netlist.
--drop=GND leaves GND out of the DSN for a pour; on 2 layers that fragments the
pour (measured: 8 GND islands), so the default routes GND too and pours on top.

Freerouting is started with DISPLAY removed and java.awt.headless set, so it
cannot open a window on the desktop session.
"""
import os
import subprocess
import sys
import time

import pcbnew
from pcbnew import FromMM, VECTOR2I

HERE = os.path.dirname(os.path.abspath(__file__))
# The jar is not in git: download Freerouting 2.4.1 from its GitHub releases
# and point FREEROUTING_JAR at it, or leave it where the toolchain proof put it.
JAR = os.environ.get("FREEROUTING_JAR",
                     os.path.join(HERE, "..", "out", "toolcheck", "freerouting-2.4.1.jar"))


def gnd_pour(board, layer=pcbnew.B_Cu, margin=0.5, w=100.0, h=100.0):
    # a board routed again keeps the pour it already has: one pour, not two
    # overlapping (DRC zones_intersect)
    gnd = board.FindNet("GND").GetNetCode()
    for i in reversed(range(board.GetAreaCount())):
        old = board.GetArea(i)
        if old.GetNetCode() == gnd and old.GetLayer() == layer:
            board.Delete(old)
    z = pcbnew.ZONE(board)
    z.SetLayer(layer)
    z.SetNetCode(board.FindNet("GND").GetNetCode())
    z.SetLocalClearance(FromMM(0.3))
    z.SetMinThickness(FromMM(0.25))
    # THERMAL left a starved thermal (1 spoke to an island) on one of three runs;
    # FULL is always clean.  Hand soldering prefers thermals: fix per board.
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)
    ol = z.Outline()
    ol.NewOutline()
    for x, y in ((margin, margin), (w - margin, margin), (w - margin, h - margin), (margin, h - margin)):
        ol.Append(FromMM(x), FromMM(y))
    board.Add(z)
    return z


def drop_nets(dsn, names):
    """Freerouting 2.4.1 ignores --router.ignore_net_classes / ignoreNetClasses
    from the CLI (measured: GND still routed).  Removing the net from the DSN's
    network section works: its pads stay, it is simply not routed."""
    import re
    text = open(dsn).read()
    for n in names:
        q = re.escape(n if re.fullmatch(r'[\w+.-]+', n) else f'"{n}"')
        text, k = re.subn(r'\(net ' + q + r'\s*\(pins[^)]*\)\s*\)', '', text)
        if k != 1:
            raise SystemExit(f"drop_nets: {n} found {k} times")
        text = re.sub(r'(\(class [^()]*?)\s' + q + r'(?=[\s)])', r'\1', text)
    open(dsn, 'w').write(text)


def main(src, dst, passes=20, pour_only=()):
    t0 = time.time()
    base = os.path.splitext(dst)[0]
    dsn, ses = base + ".dsn", base + ".ses"
    board = pcbnew.LoadBoard(src)
    ds = board.GetDesignSettings()
    nc = ds.m_NetSettings.GetDefaultNetclass()
    nc.SetTrackWidth(FromMM(0.3))
    nc.SetClearance(FromMM(0.25))
    if not pcbnew.ExportSpecctraDSN(board, dsn):
        raise SystemExit("ExportSpecctraDSN failed")
    if pour_only:
        drop_nets(dsn, pour_only)
    t1 = time.time()
    env = {k: v for k, v in os.environ.items() if k not in ("DISPLAY", "WAYLAND_DISPLAY")}
    cmd = ["java", "-Djava.awt.headless=true", "-jar", JAR, "--gui.enabled=false",
           "-de", dsn, "-do", ses, "-mp", str(passes),
           # -mt is the OPTIMISER's thread pool; 0 routes and stops.  With the
           # optimiser on, a 13-DIP card ran past 30 minutes without writing
           # a session file at all.
           "-mt", os.environ.get("FREEROUTING_OPT_THREADS", "0")]
    print("$", " ".join(cmd))
    # the log is written as it runs: tail -f <base>.freerouting.log
    with open(base + ".freerouting.log", "w") as log:
        p = subprocess.Popen(cmd, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            rc = p.wait(timeout=int(os.environ.get('FREEROUTING_TIMEOUT', '3600')))
        except subprocess.TimeoutExpired:
            p.kill()
            raise SystemExit(f"freerouting ran past FREEROUTING_TIMEOUT; see {base}.freerouting.log")
    t2 = time.time()
    if rc != 0 or not os.path.exists(ses):
        raise SystemExit(f"freerouting failed, exit {rc}; see {base}.freerouting.log")
    if not pcbnew.ImportSpecctraSES(board, ses):
        raise SystemExit("ImportSpecctraSES failed")
    z = gnd_pour(board)
    pcbnew.ZONE_FILLER(board).Fill(board.Zones())
    board.Save(dst)
    t3 = time.time()
    # board.GetTracks() / iterating board.Tracks() raises under Python 3.14
    # ('SwigPyIterator' has no 'next'); indexing the TRACKS deque works.
    tr = board.Tracks()
    items = [tr[i] for i in range(len(tr))]
    tracks = [t for t in items if t.GetClass() == "PCB_TRACK"]
    vias = [t for t in items if t.GetClass() == "PCB_VIA"]
    print(f"dsn {t1 - t0:.1f}s  freerouting {t2 - t1:.1f}s  import+fill {t3 - t2:.1f}s  "
          f"tracks {len(tracks)} vias {len(vias)}")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--drop=")]
    drop = [a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--drop=")]
    main(args[0], args[1], int(args[2]) if len(args) > 2 else 20,
         tuple(drop[0].split(",")) if drop else ())

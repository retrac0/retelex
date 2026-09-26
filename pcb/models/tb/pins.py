#!/usr/bin/env python3
"""pins.py -- the pin tables in 74hc.v, as pinmap.json and as a check.

    pins.py write    rebuild ../pinmap.json from the '//|' tables in ../74hc.v
    pins.py check    fail unless, for every part and macro:
                       * the table's ports are exactly the module's ports, with
                         the same directions (a tri row is <port> and <port>_oe)
                       * every port is its datasheet name under 74hc.v's rules
                       * the table's pin numbers are the KiCad stock symbol's,
                         pin for pin, with compatible electrical types
                       * where the symbol names its pins, the names agree
                         (through a per-part alias table: KiCad mixes LS and
                         HC naming); where it does not, the pins fall into the
                         symbol's units the way the table's section numbers say
                       * pinmap.json is what 'write' would produce

pinmap.json:  { part: { "<pin>": {"port", "dir", "type", "ds"[, "oe"][, "rail"]} } }
for every package part, keyed by module name, plus three keys that are not
parts: "_doc", "_parts" (module -> value, symbol, parameters) and "_values"
(the schematic Value string -> module), and "_macros" (macro cell -> ports).
"""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIB = HERE.parent / "74hc.v"
PINMAP = HERE.parent / "pinmap.json"
SYMDIR = Path("/usr/share/kicad/symbols")

TYPES = ("in", "out", "tri", "od", "power", "nc")
DIR = {"in": "in", "out": "out", "tri": "out", "od": "out", "power": "power", "nc": "nc"}

# ---------------------------------------------------------------- the tables

ROW = re.compile(r"^//\|\s+(\d+|-)\s+(\S+)\s+(\S+)\s+(\S+)(?:\s+(\S+))?\s*$")
HEAD = re.compile(r"^//\|\s+(part|macro)\s+(\S+)(.*)$")


def read_tables(text):
    """-> {name: {'kind', 'value', 'symbol', 'rows': [(pin, port, ds, type, extra)]}}"""
    out, cur = {}, None
    for n, line in enumerate(text.splitlines(), 1):
        if not line.startswith("//|"):
            continue
        m = HEAD.match(line)
        if m:
            kind, name, rest = m.groups()
            kv = rest.split()
            meta = dict(zip(kv[0::2], kv[1::2]))
            if name in out:
                raise SystemExit(f"74hc.v:{n}: second table for {name}")
            cur = out[name] = {"kind": kind, "value": meta.get("value"),
                               "symbol": meta.get("symbol"), "rows": [], "line": n}
            continue
        if re.match(r"^//\|\s+pin\s+port", line):
            continue
        m = ROW.match(line)
        if not m or cur is None:
            raise SystemExit(f"74hc.v:{n}: not a table row: {line!r}")
        pin, port, ds, typ, extra = m.groups()
        if typ not in TYPES:
            raise SystemExit(f"74hc.v:{n}: type {typ!r} is not one of {TYPES}")
        cur["rows"].append((pin, port, ds, typ, extra, n))
    return out


# ---------------------------------------------------------------- the modules

def read_modules(text):
    """-> {module: {'ports': [(dir, name)], 'params': {name: default}}}"""
    src = re.sub(r"//[^\n]*", "", text)
    mods = {}
    for m in re.finditer(r"\bmodule\s+(\w+)\s*", src):
        name, i = m.group(1), m.end()
        params = {}
        if src[i] == "#":
            j = src.index("(", i)
            k = _close(src, j)
            for pm in re.finditer(r"parameter\s+(?:integer\s+|\[[^\]]*\]\s*)?(\w+)\s*=\s*([^,)]+)",
                                  src[j + 1:k]):
                params[pm.group(1)] = pm.group(2).strip()
            i = k + 1
        j = src.index("(", i)
        k = _close(src, j)
        ports = []
        vectors = []
        for pm in re.finditer(r"\b(input|output)\s+(?:wire|reg)?\s*(\[[^\]]*\])?\s*(\w+)", src[j + 1:k]):
            if pm.group(2):
                vectors.append(pm.group(3))
            ports.append(("in" if pm.group(1) == "input" else "out", pm.group(3)))
        mods[name] = {"ports": ports, "params": params, "vectors": vectors}
    return mods


def _close(s, j):
    depth = 0
    for k in range(j, len(s)):
        if s[k] == "(":
            depth += 1
        elif s[k] == ")":
            depth -= 1
            if depth == 0:
                return k
    raise SystemExit("unbalanced parentheses in 74hc.v")


# ---------------------------------------------------------------- naming rule

def translit(ds):
    """The datasheet name as a Verilog identifier (74hc.v, NAMES)."""
    neg = ds.startswith("/")
    s = ds[1:] if neg else ds
    s = s.replace("=", "_EQ_")
    m = re.match(r"^(\d)([A-Za-z]\w*)$", s)
    if m:
        unit, base = m.groups()
        s = base + ("_" if base[-1].isdigit() else "") + unit
    return s + ("_n" if neg else "")


def unit_of(ds):
    m = re.match(r"^/?(\d)[A-Za-z]", ds)
    return int(m.group(1)) if m else None


def strip_unit(ds):
    return re.sub(r"^(/?)\d(?=[A-Za-z])", r"\1", ds)


# ---------------------------------------------------------------- KiCad

_TOK = re.compile(r'\(|\)|"(?:\\.|[^"\\])*"|[^\s()]+')


def _parse(text):
    stack = [[]]
    for m in _TOK.finditer(text):
        t = m.group(0)
        if t == "(":
            stack.append([])
        elif t == ")":
            x = stack.pop()
            stack[-1].append(x)
        elif t[0] == '"':
            stack[-1].append(t[1:-1].replace('\\"', '"'))
        else:
            stack[-1].append(t)
    return stack[0][0]


def _kids(node, head):
    return [c for c in node if isinstance(c, list) and c and c[0] == head]


_libs = {}


def kicad_pins(libsym):
    """-> {pin number: (unit, name, type, rotation)}, the base symbol's if it extends one."""
    lib, sym = libsym.split(":")
    if lib not in _libs:
        tree = _parse((SYMDIR / f"{lib}.kicad_sym").read_text())
        _libs[lib] = {c[1]: c for c in _kids(tree, "symbol")}
    L = _libs[lib]
    if sym not in L:
        raise KeyError(libsym)
    s = L[sym]
    ext = _kids(s, "extends")
    if ext:
        s = L[ext[0][1]]
    pins = {}
    for u in _kids(s, "symbol"):
        m = re.search(r"_(\d+)_(\d+)$", u[1])
        unit = int(m.group(1)) if m else 0
        for p in _kids(u, "pin"):
            num = _kids(p, "number")[0][1]
            name = _kids(p, "name")[0][1]
            at = _kids(p, "at")[0]
            rot = float(at[3]) if len(at) > 3 else 0.0
            pins.setdefault(num, (unit, name, p[1], rot))   # De Morgan bodies repeat a pin
    return pins


def knorm(name):
    return re.sub(r"~\{([^}]*)\}", r"/\1", name)


# KiCad's name for a pin where it is not the datasheet's (after knorm, and
# after the section number is stripped for a multi-unit symbol).
ALIAS = {
    "hc74":   {"/RD": "/R", "/SD": "/S", "CP": "C"},
    "hc138":  {"/E1": "/E0", "/E2": "/E1", "E3": "E2"},
    "hc148":  dict([(f"/I{i}", f"I{i}") for i in range(1, 8)] + [("/I0", "IO")] +
                   [(f"/A{i}", f"S{i}") for i in range(3)] +
                   [("/EI", "EI"), ("/GS", "GS"), ("/EO", "EO")]),
    "hc151":  {"Y": "Z", "/Y": "/Z"},
    "hc157":  dict([(f"{u}I{i}", f"I{i}{'abcd'[u - 1]}") for u in range(1, 5) for i in (0, 1)] +
                   [(f"{u}Y", f"Z{'abcd'[u - 1]}") for u in range(1, 5)] + [("/E", "E")]),
    "hc175":  {"/MR": "/Mr", "CP": "Cp"},
    "hc273":  {"/MR": "/Mr", "CP": "Cp"},
    "hc244":  {"/1OE": "1OE", "/2OE": "2OE"},
    "hc595":  dict([(f"Q{i}", f"Q{'ABCDEFGH'[i]}") for i in range(8)] +
                   [("Q7S", "QH'"), ("/MR", "/SRCLR"), ("SHCP", "SRCLK"), ("STCP", "RCLK"),
                    ("DS", "SER")]),
    "hc688":  dict([(f"Q{i}", f"R{i}") for i in range(8)] + [("/E", "G"), ("/P=Q", "P=R")]),
    "hc4051": dict([(f"Y{i}", f"A{i}") for i in range(8)] + [("Z", "A")]),
    "hc4002": {"GND": "VSS", "VCC": "VDD"},
}

# which of our types each KiCad electrical type may be
KTYPE = {
    "input": {"in"},
    "output": {"out"},
    "tri_state": {"tri"},
    "open_collector": {"od"},
    "power_in": {"power"},
    "passive": {"power", "od", "in", "tri"},
    "no_connect": {"nc"},
}


# ---------------------------------------------------------------- pinmap

def build(tables, mods):
    parts, values, pmeta, macros = {}, {}, {}, {}
    for name, t in tables.items():
        if t["kind"] == "macro":
            macros[name] = {
                "ports": {port: {"dir": DIR[typ], **({"sim": True} if extra == "sim" else {})}
                          for pin, port, ds, typ, extra, _ in t["rows"]},
                "params": mods.get(name, {}).get("params", {}),
            }
            continue
        pins = {}
        for pin, port, ds, typ, extra, _ in sorted(t["rows"], key=lambda r: int(r[0])):
            e = {"port": None if port == "-" else port, "dir": DIR[typ], "type": typ, "ds": ds}
            if typ == "tri":
                e["oe"] = port + "_oe"
            if typ == "power":
                e["rail"] = extra
            pins[pin] = e
        parts[name] = pins
        for v in (t["value"] or "").split(","):
            if v:
                values[v] = name
        pmeta[name] = {"value": t["value"], "symbol": t["symbol"],
                       "params": mods.get(name, {}).get("params", {})}
    doc = ("Generated from the '//|' tables in 74hc.v by tb/pins.py write; do not edit. "
           "part -> pin number -> {port, dir, type, ds}: port is the model's port (null for a "
           "supply or nc pin); type in|out|tri|od|power|nc; a tri pin is two ports, port "
           "(value) and oe (enable); an od port is 1 when pulling low; a power pin names "
           "the rail it must be on. _values maps a schematic Value to a part.")
    return parts, values, pmeta, macros, doc


def render(parts, values, pmeta, macros, doc):
    L = ["{", f'  "_doc": {json.dumps(doc)},',
         '  "_values": ' + json.dumps(values, sort_keys=True) + ",",
         '  "_parts": {']
    names = list(parts)
    for i, n in enumerate(names):
        L.append(f"    {json.dumps(n)}: " + json.dumps(pmeta[n], sort_keys=True) +
                 ("," if i < len(names) - 1 else ""))
    L.append("  },")
    L.append('  "_macros": {')
    mn = list(macros)
    for i, n in enumerate(mn):
        L.append(f"    {json.dumps(n)}: " + json.dumps(macros[n], sort_keys=True) +
                 ("," if i < len(mn) - 1 else ""))
    L.append("  },")
    for i, n in enumerate(names):
        L.append(f"  {json.dumps(n)}: {{")
        pins = list(parts[n].items())
        for j, (pin, e) in enumerate(pins):
            L.append(f"    {json.dumps(pin)}: " + json.dumps(e) + ("," if j < len(pins) - 1 else ""))
        L.append("  }" + ("," if i < len(names) - 1 else ""))
    L.append("}")
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------- the check

def check(tables, mods, text_pinmap):
    errs, n = [], 0

    def ck(cond, msg):
        nonlocal n
        n += 1
        if not cond:
            errs.append(msg)

    for name, t in tables.items():
        ck(name in mods, f"{name}: a table with no module")
        if name not in mods:
            continue
        want = set()
        for pin, port, ds, typ, extra, line in t["rows"]:
            if typ in ("power", "nc"):
                ck(port == "-", f"74hc.v:{line}: {name} pin {pin} is {typ} but names port {port}")
                if typ == "power":
                    ck(extra in ("GND", "+5V"), f"74hc.v:{line}: {name} pin {pin}: rail {extra!r}")
                continue
            ck(port != "-", f"74hc.v:{line}: {name} pin {pin} ({typ}) has no port")
            want.add((DIR[typ], port))
            if typ == "tri":
                want.add(("out", port + "_oe"))
            if t["kind"] == "part":
                if typ == "od":
                    ck(port == "pd", f"74hc.v:{line}: {name}: an open drain's port is pd, not {port}")
                else:
                    ck(port == translit(ds),
                       f"74hc.v:{line}: {name} pin {pin}: {ds!r} makes {translit(ds)!r}, not {port!r}")
        ck(not mods[name]["vectors"], f"{name}: vector ports {mods[name]['vectors']}; a pin is one bit")
        have = set(mods[name]["ports"])
        ck(have == want, f"{name}: module ports and table differ: "
                         f"module only {sorted(have - want)}, table only {sorted(want - have)}")
        ck(len(mods[name]["ports"]) == len(have), f"{name}: a port declared twice")
        if t["kind"] != "part":
            continue
        pins = [r[0] for r in t["rows"]]
        ck(len(pins) == len(set(pins)), f"{name}: a pin number twice")

        # ---- against KiCad
        try:
            kp = kicad_pins(t["symbol"])
        except (KeyError, FileNotFoundError):
            ck(False, f"{name}: no KiCad symbol {t['symbol']}")
            continue
        rows = {r[0]: r for r in t["rows"]}
        for num in kp:
            ck(num in rows, f"{name}: KiCad {t['symbol']} pin {num} ({kp[num][1]}) is not in the table")
        for num, (pin, port, ds, typ, extra, line) in rows.items():
            if num not in kp:
                ck(typ == "nc", f"74hc.v:{line}: {name} pin {num} is not on {t['symbol']}")
                continue
            unit, kname, ktype, rot = kp[num]
            ck(typ in KTYPE.get(ktype, set()),
               f"74hc.v:{line}: {name} pin {num}: KiCad says {ktype}, table says {typ}")
            if kname:
                multi = len({u for u, *_ in kp.values() if u}) > 2
                mine = strip_unit(ds) if (multi and typ not in ("power",)) else ds
                expect = ALIAS.get(name, {}).get(mine, mine)
                ck(knorm(kname) == expect,
                   f"74hc.v:{line}: {name} pin {num}: datasheet {ds!r} should be KiCad {expect!r}, "
                   f"symbol says {knorm(kname)!r}")
                if multi and typ != "power" and unit_of(ds):
                    ck(unit_of(ds) == unit, f"74hc.v:{line}: {name} pin {num}: section {unit_of(ds)}, "
                                            f"KiCad unit {unit}")
        # unnamed pins: the table's sections must be KiCad's units
        unnamed = {num for num, v in kp.items() if not v[1]}
        if unnamed:
            for num in unnamed:
                if num not in rows:
                    continue
                ds = rows[num][2]
                ck(unit_of(ds) == kp[num][0],
                   f"{name} pin {num}: {ds!r} is section {unit_of(ds)}, KiCad unit {kp[num][0]}")
                # an enable is the pin drawn vertically on a buffer's body
                if name == "hc125":
                    vertical = kp[num][3] in (90.0, 270.0)
                    ck(vertical == ("OE" in ds),
                       f"{name} pin {num}: {ds!r} {'is' if vertical else 'is not'} KiCad's enable pin")

    for name in mods:
        if not name.startswith(("hc_",)) and name not in tables:
            ck(False, f"{name}: a module with no pin table")

    parts, values, pmeta, macros, doc = build(tables, mods)
    ck(text_pinmap == render(parts, values, pmeta, macros, doc),
       "pinmap.json is stale: run 'make pinmap'")
    return n, errs


def main():
    text = LIB.read_text()
    tables, mods = read_tables(text), read_modules(text)
    if len(sys.argv) > 1 and sys.argv[1] == "write":
        PINMAP.write_text(render(*build(tables, mods)))
        print(f"  wrote {PINMAP} ({sum(1 for t in tables.values() if t['kind'] == 'part')} parts)")
        return
    print("  pins -- the '//|' tables against the modules, the naming rule, KiCad's symbols, pinmap.json")
    n, errs = check(tables, mods, PINMAP.read_text() if PINMAP.exists() else "")
    for e in errs[:40]:
        print(f"    FAIL  {e}")
    nparts = sum(1 for t in tables.values() if t["kind"] == "part")
    nmac = sum(1 for t in tables.values() if t["kind"] == "macro")
    print(f"\n  {nparts} parts, {nmac} macros; {n} checks, {len(errs)} errors.  "
          f"{'PASS' if not errs else 'FAIL'}")
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()

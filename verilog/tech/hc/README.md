# tech/hc — 74HC target for Yosys

Maps the exchange RTL onto a handful of common 74HC packages and reports a
DIP package BOM.

| Cell / module | Package | Role |
|---|---|---|
| `HC00_NAND2` … `HC32_OR2` | HC00 / 02 / 04 / 08 / 32 | SSI via `abc -g` + [`hc_map.v`](hc_map.v) |
| `HC74_DFF*` | HC74 | flip-flops via `dfflibmap` + [`hc_ssi.lib`](hc_ssi.lib) |
| `mux8` | HC151 | kept as blackbox |
| `hc259` | HC259 | kept as blackbox |
| `ctl_write` | 2 × HC165 | kept as blackbox (serialiser) |

**Why not `abc -liberty`?** On the Yosys 0.66 build in use here, ABC segfaults
when reading this liberty/genlib for combinational mapping. Flip-flops still
come from the liberty file; gates are mapped with `abc -g AND,NAND,OR,NOR`
and renamed onto HC cells by `hc_map.v`.

`make synth-hc` in `verilog/` runs all four tops.  `pack.py` turns the
Yosys JSON into package counts.

# tech/hc — 74HC target for Yosys

Maps the exchange RTL onto common 74HC packages and reports a DIP package BOM.

| Cell / module | Package | Role |
|---|---|---|
| `HC00_NAND2` … `HC32_OR2` | HC00 / 02 / 04 / 08 / 32 | SSI via `abc -g` + [`hc_map.v`](hc_map.v) |
| `HC74_DFF*` | HC74 | flip-flops via `dfflibmap` + [`hc_ssi.lib`](hc_ssi.lib) |
| `mux8` / `hc151` | HC151 | 8:1 mux |
| `hc259` | HC259 | addressable latch |
| `ctl_write` | 2 × HC165 | cable-B serialiser |
| `hc393` `hc4040` `hc163` `hc175` `hc670` `hc174` … | named MSI | [`register.md`](../../../exchange/register.md) §4 parts |
| `pulse_reg` | ≈ 12 (hand BOM) | whole register, blackboxed for `synth-hc-mini` |
| `mini_core` | ≈ 12 (hand BOM) | scanner / probe / sequencer |

**Why not `abc -liberty`?** On the Yosys 0.66 build in use here, ABC segfaults
when reading this liberty/genlib for combinational mapping. Flip-flops still
come from the liberty file; gates are mapped with `abc -g AND,NAND,OR,NOR`
and renamed onto HC cells by `hc_map.v`.

`make synth-hc` in `verilog/` runs the tops.  For `mini_marker`,
[`hc_bb.v`](hc_bb.v) supplies blackbox shells so `pulse_reg` and `mini_core`
bill at the hand BOM (~26 packages total).  `pack.py` turns the Yosys JSON
into package counts.

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
| `pulse_reg` | ≈ 11 (hand BOM) | whole register, blackboxed for `synth-hc-mini` |
| `mini_core` | ≈ 12 (hand BOM) | scanner / probe / sequencer |

**Why not `abc -liberty`?** On the Yosys 0.66 build in use here, ABC segfaults
when reading this liberty/genlib for combinational mapping. Flip-flops still
come from the liberty file; gates are mapped with `abc -g AND,NAND,OR,NOR`
and renamed onto HC cells by `hc_map.v`.

`make synth-hc` in `verilog/` runs the tops.  For `mini_marker` and
`nano_marker`, [`hc_bb.v`](hc_bb.v) supplies blackbox shells so `pulse_reg`,
`mini_core`, `nano_reg` and `nano_core` bill at the hand BOM — 33 packages and
25 respectively (`nano-marker.md` §6).  `pack.py` turns the Yosys JSON into
package counts.

The hand BOMs count what a board would actually carry.  Two of them used to
be optimistic: `mini_core` billed its four-deep 15-bit write queue as one
'670 when it is four, and `pulse_reg` did not bill the parallel mirror its
'670 needs (one addressed read port cannot present four digits at once).
Both are corrected, which is why `mini_marker` reads 33 and not 25.

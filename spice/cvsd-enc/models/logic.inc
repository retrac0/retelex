* 74HC glue for the breadboard encoder — XSPICE with HC-class delays.
* Real packages on the board: 74HC74 (×2 for three flops), 74HC86, 74HC32.

.model hc_dff d_dff(clk_delay=8n set_delay=8n reset_delay=8n
+  rise_delay=6n fall_delay=6n ic=0)
.model hc_adc adc_bridge(in_low=1.5 in_high=3.5)
.model hc_dac dac_bridge(out_low=0 out_high=5)
.model hc_xor d_xor(rise_delay=8n fall_delay=8n)
.model hc_or  d_or(rise_delay=8n fall_delay=8n)

* Rising-edge DFF, set/reset held inactive (74HC74 half).
.subckt HC74_DFF d clk q qn
Vzero _z 0 DC 0
Aadc [d clk _z _z] [dd clkd setd restd] hc_adc
Adff dd clkd setd restd qd qnd hc_dff
Adac [qd qnd] [q qn] hc_dac
.ends HC74_DFF

* 74HC glue — XSPICE digital only; ADC/DAC at analog boundary.
* Real packages: 74HC74 (×2), 74HC86, 74HC32.

.model hc_dff d_dff(clk_delay=8n set_delay=8n reset_delay=8n
+  rise_delay=6n fall_delay=6n ic=0)
.model hc_adc adc_bridge(in_low=1.5 in_high=3.5)
.model hc_dac dac_bridge(out_low=0 out_high=5)
.model hc_xor d_xor(rise_delay=8n fall_delay=8n)
.model hc_or  d_or(rise_delay=8n fall_delay=8n)

* Run register + coincidence entirely in the digital domain.
* Analog: DIN, CLK in; Q, NQ, NCOIN out (OTA steer + syllabic).
* /COIN = (Q⊕Q1)∨(Q1⊕Q2) — low on run-of-three.
.subckt CVSD_LOGIC DIN CLK Q NQ NCOIN
Vzero _z 0 DC 0
Aadc [DIN CLK _z _z] [dind clkd setd restd] hc_adc
Ad0 dind clkd setd restd qd  nqd  hc_dff
Ad1 qd   clkd setd restd q1d nq1d hc_dff
Ad2 q1d  clkd setd restd q2d nq2d hc_dff
Ax01 [qd q1d] x01d hc_xor
Ax12 [q1d q2d] x12d hc_xor
Aor  [x01d x12d] ncd hc_or
Adac [qd nqd ncd] [Q NQ NCOIN] hc_dac
.ends CVSD_LOGIC

* 74HC AMI glue — XSPICE digital
.model hc_dff d_dff(clk_delay=8n set_delay=8n reset_delay=8n
+  rise_delay=6n fall_delay=6n ic=0)
.model hc_adc adc_bridge(in_low=1.5 in_high=3.5)
.model hc_dac dac_bridge(out_low=0 out_high=5)
.model hc_xor d_xor(rise_delay=8n fall_delay=8n)
.model hc_and d_and(rise_delay=8n fall_delay=8n)

* Encoder: polarity FF D=Q⊕B on H; EP=B·Q EM=B·/Q
.subckt AMI_ENC B H EP EM
Vzz _z 0 DC 0
Aadc [B H _z _z] [bd hd sd rd] hc_adc
Axor [qd bd] dd hc_xor
Adff dd hd sd rd qd nqd hc_dff
Aandp [bd qd] epd hc_and
Aandm [bd nqd] emd hc_and
Adac [epd emd] [EP EM] hc_dac
.ends AMI_ENC

* Decoder bit latch: sample MARK on rising HS (half-cell-delayed symbol clock).
* In the field HS comes from the DPLL mid-cell tap (ami.md §4); in loopback
* tests HS is H delayed ½ cell (locked crystals / open-loop mid sample).
.subckt AMI_DEC_LATCH MARK HS BIT STROBE
Vzz _z 0 DC 0
Aadc [MARK HS _z _z] [md hsd sd rd] hc_adc
Adff md hsd sd rd bitd nbitd hc_dff
Adac [bitd hsd] [BIT STROBE] hc_dac
.ends AMI_DEC_LATCH

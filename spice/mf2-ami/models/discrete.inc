* Discrete + switch models for MF2 AMI line PHY

.include ../../cvsd-enc/models/discrete.mod

* Ideal bidirectional switch for three-level AMI bridge (on when Vctl > 2.5)
.model AMI_SW SW(vt=2.5 vh=0.2 ron=2 roff=100Meg)

* 56 V bidirectional TVS (two zeners) — clamps above −48 V phantom / 50 V abuse
.model TVS56 D(Is=1e-12 Rs=0.5 Bv=56 Ibv=1m Cjo=50p)

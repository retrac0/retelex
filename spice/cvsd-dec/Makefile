# CVSD decoder A — ngspice
# Loopback: enc_a → dec_a → recon

NGSPICE ?= ngspice
OUT := out

.PHONY: all loop check talkers talkers-fast clean

all: loop check

$(OUT):
	mkdir -p $(OUT)

loop: $(OUT)
	$(NGSPICE) -b test_loop.cir 2>&1 | tee $(OUT)/loop.log

check:
	python3 check.py

# Full talker campaign: 1 s × talkers 1–7, 3-way parallel (~15–20 min).
talkers:
	python3 talker_snr.py --seconds 1 -j 3

# Quicker smoke: 0.25 s × three talkers (speech-onset aligned).
talkers-fast:
	python3 talker_snr.py --talkers 1,4,6 --seconds 0.25 -j 3

clean:
	rm -rf $(OUT)

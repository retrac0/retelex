"""
Arithmetic for the jumper-configured analog receiver: component values, parasitic
ratios, and the classifier-timer tolerance stack.  NOT a simulation.  Every
constant is either a datasheet figure (source named) or an ASSUMPTION (marked).

Datasheet figures used (retrieved 2026-09-16):
  TI CD74HC123 (SCHS142):  tW = 0.45 Rx Cx at 5 V; output pulse width at Rx 10k,
      Cx 10 nF, 5 V: 40-50 us at 25 C, 38.7-51.3 us at -40..85 C; minimum Rx
      typically 5 k; pulse width match within a package +-2 %.
  Nexperia 74HC123 (rev 13, 2024):  K = 0.45 at 5.0 V, 0.55 at 2.0 V, formula valid for
      Cext > 10 nF; Rext 2 k .. 1 M; ~7 pF jig + pin capacitance at REXT/CEXT;
      tpd(trigger->Q) 30 ns typ / 51 ns max at 4.5 V 25 C, 64 ns max -40..85 C;
      tW = 75 ns typ at Cext = 0, Rext = 5 k;
      retrigger time trtrig = 30 + 0.19 R C^0.9 + 13 R^1.05  ns (R kohm, C pF, 5 V).
  TI CD74HC221:  tW = 0.7 Rx Cx at 4.5 V; 140 ns typ at Cx 28 pF, Rx 2 k; min Rx typ 500 ohm.
  TI CD74HC4538: tau = 0.7 Rx Cx; 0.63-0.77 ms at 10k/0.1 uF 25 C, 0.602-0.798 ms -40..85 C.
  TI CD74HC4066: Ron at Vcc 4.5 V: 35 typ / 95 max ohm (25 C), 118 max (-40..85 C); switch C 5 pF.
  TI CD74HC4051: Ron at 4.5 V: 90 typ / 180 max (25 C), 225 max (-40..85 C); switch C 5 pF,
      common C 25 pF.

Usage:  python3 feas_analog_budget.py
"""
import numpy as np

RATES = (64000, 128000, 256000, 512000, 1024000)
PI2 = 2 * np.pi


def hdr(t):
    print('\n' + '=' * 84 + '\n' + t + '\n' + '=' * 84)


# ------------------------------------------------------------------ values
hdr('1. COMPONENT VALUES (R = 1.00 k per RC section; timers by the datasheet K formula)')
R_F = 1000.0
print('  filter C per section, R = 1 k:')
for name, corners in (('5 positions (own symbol rate)', [2 * r for r in RATES]),
                      ('3 positions', [128e3, 362.04e3, 1448.15e3]),
                      ('2 positions', [256e3, 1448.15e3])):
    print(f'    {name:32s} ' + ', '.join(f'{f/1e3:7.1f} kHz: {1e12/(PI2*R_F*f):7.1f} pF' for f in corners))

K123, C123 = 0.45, 270.0          # classifier: fixed Cext (C0G), switched Rext
print(f'\n  classifier 0.75 cell, 74HC123, K = {K123} (formula; outside its Cext > 10 nF validity),'
      f' Cext = {C123:.0f} pF + 7 pF pin:')
for r in RATES:
    t = 0.75e9 / r
    R = t / (K123 * (C123 + 7.0)) * 1e3
    trt = 30 + 0.19 * (R / 1e3) * (C123 + 7.0) ** 0.9 + 13 * (R / 1e3) ** 1.05
    print(f'    {r//1000:5d}k  {t:8.1f} ns  Rext {R/1e3:6.2f} k   retrigger time (Nexperia formula) '
          f'{trt:5.0f} ns = {trt/(1e9/r):.2f} cell  (dead time 0.2 cell = {0.2e9/r:.0f} ns)')

print('\n  dead time, 74HC221, K = 0.7 formula, 2 positions:')
for t in (977.0, 195.0):
    print(f'    {t:6.0f} ns  Rx 2.00 k -> Cx {t/(0.7*2.0):6.1f} pF (formula); the datasheet typical 140 ns at '
          f'28 pF/2 k is K = {140/(2.0*28):.1f}: select on test')
print('  carrier detect, second half of the 74HC123: ONE fixed 31.25 us (2 cells at 64 kbps; measured never to trip on signal at any rate)')


# ------------------------------------------------------------------ parasitics
hdr('2. PARASITIC CAPACITANCE AGAINST THE SMALLEST VALUES (analysis)')
STUB = (1.0, 3.0)      # ASSUMPTION: header pin pair + pad + ~1 cm trace, pF (range)
print(f'  ASSUMED stub per jumper position: {STUB[0]}-{STUB[1]} pF (2.54 mm header pin + pad + ~1 cm trace).')
cases = [
    ('filter C, 5-pos at 2.048 MHz', 77.7, 5, 'jumper'),
    ('filter C, 2/3-pos at 1.448 MHz', 109.9, 2, 'jumper'),
    ('filter C, 2-pos via 74HC4066 (off switch 5 pF on the added C)', 109.9, 1, '4066'),
    ('classifier Cext node, jumpers at the Rext node end', C123 + 7, 5, 'jumper'),
    ('classifier Cext node, 74HC4051 COM on the node', C123 + 7, 1, '4051com'),
    ('classifier, switch at the Vcc end of Rext (C on node ~0)', C123 + 7, 0, 'vcc'),
    ('dead time Cx at 195 ns (2 k)', 139.3, 2, 'jumper'),
]
for name, C, npos, kind in cases:
    if kind == 'jumper':
        lo, hi = npos * STUB[0], npos * STUB[1]
    elif kind == '4066':
        lo, hi = 5.0, 5.0 + STUB[1]
    elif kind == '4051com':
        lo, hi = 25.0, 25.0 + STUB[1]
    else:
        lo, hi = 0.0, 0.5
    print(f'    {name:62s} C {C:6.1f} pF: +{lo:4.1f}..+{hi:4.1f} pF = +{100*lo/C:4.1f}..+{100*hi/C:4.1f} %')
print('  filter corners move by the same fraction; section (a) of feas_analog_rx.py shows the RC-RC')
print('  corner is flat to within ~1 dB from 0.71x to 1.41x, so a 10-20 % shift is not visible.')
print('  timer parasitics are systematic: fold the expected value into Cext, count the uncertainty.')

print('\n  switch on-resistance in series with the timing R (74HC4066 at the Vcc end of Rext):')
for r in (1024000, 64000):
    R = 0.75e9 / r / (K123 * (C123 + 7.0)) * 1e3
    for lab, ron in (('typ 25 C', 35.0), ('max 25 C', 95.0), ('max -40..85 C', 118.0)):
        print(f'    {r//1000:5d}k Rext {R/1e3:6.2f} k  Ron {lab:14s} {ron:5.0f} ohm = +{100*ron/R:4.2f} %')


# ------------------------------------------------------------------ tolerance stack
g25, g85 = 100 * (50 - 40) / 2 / 45, 100 * (51.3 - 38.7) / 2 / 45
# measured classifier windows at the design point, absolute method (feas_analog_rx.py b / e):
#   1024 kbps 0.675-0.850 (-10 %/+13 % about 0.75; +-11.5 % about a re-centred 0.7625)
#     64 kbps 0.625-0.875 (+-17 % about 0.75)
for lr, windows in ((1024000, ((10.0, 'about 0.75'), (11.5, 'about 0.7625, re-centred'))),
                    (64000, ((17.0, 'about 0.75'),))):
    t = 0.75e9 / lr
    Rk = t / (K123 * (C123 + 7.0))                 # kohm
    hdr(f'3. CLASSIFIER TIMER TOLERANCE STACK, {lr//1000} kbps position ({t:.0f} ns, Rext {Rk:.1f} k), 0-70 C')
    items = [
        ('Rext 1 % metal film', 1.0, 'part'),
        ('Rext TCR 100 ppm/K x 45 K', 0.45, 'part'),
        ('Cext 270 pF C0G 2 %', 2.0, 'part'),
        ('Cext C0G 30 ppm/K x 45 K', 0.14, 'part'),
        ('stray C uncertainty +-3 pF (ASSUMPTION) on 277 pF', 100 * 3 / 277, 'layout'),
        (f'4066 Ron 35..118 ohm at Vcc end, about the mean, on {Rk:.1f} k', 100 * (118 - 35) / 2 / (Rk * 1e3), 'switch'),
        (f'trigger->Q delay 30 typ..64 max ns, about the mean, on {t:.0f} ns', 100 * (64 - 30) / 2 / t, 'IC'),
        ('K vs Vcc +-5 % (typ, 0.45 @ 5 V .. 0.55 @ 2 V, linear)', 100 * (0.10 / 3.0 * 0.25) / 0.45, 'IC typ'),
    ]
    lin = sum(v for _, v, _ in items)
    rss = np.sqrt(sum(v * v for _, v, _ in items))
    for n, v, k in items:
        print(f'    {n:62s} +-{v:5.2f} %  [{k}]')
    print(f'    {"sum, everything except the IC pulse-width constant":62s} +-{lin:5.2f} % linear, +-{rss:5.2f} % RSS')
    for W, lab in windows:
        print(f'  measured window +-{W:.1f} % {lab}: left for the IC constant  {W-lin:5.1f} % worst-case linear,  '
              f'{np.sqrt(max(W*W-rss*rss,0)):5.1f} % RSS')
print(f'\n  IC constant, GUARANTEED (TI CD74HC123, 10k/10nF): +-{g25:.1f} % at 25 C, +-{g85:.1f} % at -40..85 C')
print(f'  IC constant, GUARANTEED (TI CD74HC4538, 10k/0.1uF): +-{100*0.07/0.70:.1f} % at 25 C, '
      f'+-{100*0.098/0.70:.1f} % at -40..85 C')
print('  Neither guarantee applies at Cext = 270 pF, where K is not the formula value (Nexperia:')
print('  formula valid above 10 nF; TI 4538 Fig. 10 shows K rising at small Cx).  So the 1024 and')
print('  512 kbps positions need a measured (select-on-test or trimmed) Rext in any case.')
print('\n  With ONE trim per board at one position (common Cext, common IC):')
post = [('Rext 1 % (per position, untrimmed)', 1.0), ('Rext TCR', 0.45), ('Cext TC', 0.14),
        ('4066 Ron drift about the mean', 100 * (118 - 35) / 2 / 5900), ('trigger->Q delay drift', 100 * (64 - 30) / 2 / 732),
        ('K vs Vcc (typ)', 100 * (0.10 / 3.0 * 0.25) / 0.45),
        ('K vs temperature: NOT PUBLISHED -- ASSUMED +-3 %', 3.0),
        ('K ratio between positions (different Rext at fixed Cext): NOT PUBLISHED -- ASSUMED +-3 %', 3.0)]
lin2 = sum(v for _, v in post); rss2 = np.sqrt(sum(v * v for _, v in post))
for n, v in post:
    print(f'    {n:84s} +-{v:4.2f} %')
print(f'    total +-{lin2:.1f} % linear, +-{rss2:.1f} % RSS')

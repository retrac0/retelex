#include <stdint.h>
#include <stdlib.h>
#include <math.h>

void c_slice_hyst(const double *x, long n, double h, uint8_t *out) {
    int s = 0;
    for (long i = 0; i < n; i++) {
        if (x[i] > h) s = 1; else if (x[i] < -h) s = 0;
        out[i] = (uint8_t)s;
    }
}

long c_dpll_decode(const uint8_t *w, long n, int OS, int win, int lock_after,
                   uint8_t *bits, long *st, long maxout) {
    int half = OS/2, qtr = OS/4;
    int phase = 0, prev = w[0], s1 = 0, have_s1 = 0, good = 0, locked = 0;
    long last_edge = 0, nb = 0, resyncs = 0, nudges = 0, lock_sample = -1;
    double gate = 0.75 * OS;
    for (long i = 1; i < n; i++) {
        int cur = w[i], edge = (cur != prev);
        prev = cur;
        if (edge) {
            long gap = i - last_edge; last_edge = i;
            if (gap > gate) {
                int err = (phase < half) ? phase : phase - OS;
                if (abs(err) <= win) { good++; if (!locked && good >= lock_after) { locked = 1; lock_sample = i; } }
                else { good = 0; locked = 0; }
                if (!locked) { resyncs++; phase = 0; }
                else { if (err > 0) phase--; else if (err < 0) phase++; nudges++; }
            } else {
                if (phase < win) { phase--; nudges++; }
                else if (phase > OS - win) { phase++; nudges++; }
            }
        }
        phase++;
        if (phase >= OS) phase -= OS; else if (phase < 0) phase += OS;
        if (phase == qtr) { s1 = cur; have_s1 = 1; }
        else if (phase == OS - qtr && have_s1) { if (nb >= maxout) break; bits[nb++] = (s1 == cur); have_s1 = 0; }
    }
    st[0] = resyncs; st[1] = nudges; st[2] = lock_sample;
    return nb;
}

long c_ami_decode(const double *x, long n, int OS, double t, uint8_t *bits, long maxout) {
    int phase = 0, win = OS/4, half = OS/2;
    int prev = (fabs(x[0]) > t);
    long nb = 0;
    for (long i = 1; i < n; i++) {
        int cur = (fabs(x[i]) > t);
        if (cur && !prev) {
            if (phase < win) phase--;
            else if (phase > OS - win) phase++;
            else if (phase < half) phase--;
            else phase++;
        }
        prev = cur;
        phase++;
        if (phase >= OS) phase -= OS; else if (phase < 0) phase += OS;
        if (phase == half) { if (nb >= maxout) break; bits[nb++] = (fabs(x[i]) > t); }
    }
    return nb;
}

/* Continuous-phase (analog) PLL decoder: models a 4046-type loop whose VCO runs
   at the symbol rate.  Phase is a double, NOT quantised to master-clock ticks,
   so there is no oversampling requirement at all. */
long c_apll_decode(const uint8_t *w, long n, double spb, double kp, double ki,
                   uint8_t *bits, long maxout) {
    double phase = 0.0, dstep = 1.0 / spb;     /* phase advance per sample */
    int prev = w[0], s1 = 0, have_s1 = 0;
    long last_edge = 0, nb = 0;
    double gate = 0.75 * spb;
    for (long i = 1; i < n; i++) {
        int cur = w[i], edge = (cur != prev);
        prev = cur;
        if (edge) {
            long gap = i - last_edge; last_edge = i;
            if (gap > gate) {                   /* full-bit gap => cell boundary */
                double err = phase;             /* want phase == 0 here */
                if (err > 0.5) err -= 1.0;
                phase -= kp * err;              /* proportional */
                dstep -= ki * err * dstep;      /* integral: pull VCO frequency */
                if (dstep < 0.2 / spb) dstep = 0.2 / spb;   /* clamp VCO range */
                if (dstep > 5.0 / spb) dstep = 5.0 / spb;
                if (phase < 0) phase += 1.0;
            }
        }
        double before = phase;
        phase += dstep;
        if (before < 0.25 && phase >= 0.25) { s1 = cur; have_s1 = 1; }
        if (before < 0.75 && phase >= 0.75 && have_s1) { if (nb >= maxout) break; bits[nb++] = (s1 == cur); have_s1 = 0; }
        if (phase >= 1.0) phase -= 1.0;
    }
    return nb;
}

/* Monostable / interval-classifier differential-Manchester decoder.
   No clock and no oversampling: each inter-transition interval is classified
   against ONE RC threshold (~0.75 cell).  A long interval is a whole cell
   (bit 1); two short intervals make a cell with a mid-cell transition (bit 0).
   `dead` models the monostable's own minimum retrigger width = glitch rejection. */
long c_mono_decode(const uint8_t *w, long n, double spb, double thr_frac,
                   double dead_frac, uint8_t *bits, long maxout) {
    double thr = thr_frac * spb, dead = dead_frac * spb;
    int prev = w[0], at_mid = 0;
    long last_edge = 0, nb = 0;
    for (long i = 1; i < n; i++) {
        if (w[i] != prev) {
            prev = w[i];
            double gap = (double)(i - last_edge);
            if (gap < dead) continue;          /* glitch: monostable still held */
            last_edge = i;
            if (nb >= maxout) break;
            if (gap > thr) { bits[nb++] = 1; at_mid = 0; }
            else if (at_mid) { bits[nb++] = 0; at_mid = 0; }
            else at_mid = 1;
        }
    }
    return nb;
}

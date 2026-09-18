/* Kernels for feas_digital_rx.py (digital, crystal-clocked line receiver study).
   Build:  gcc -O2 -shared -fPIC -o feas_digital_core.so feas_digital_core.c      */
#include <stdint.h>
#include <math.h>

/* Hysteretic comparator on a sampled analog waveform, reporting each output
   transition at its interpolated crossing time (units: simulation samples,
   sample i at time base+i).  State and the previous sample carry across chunks.
   Returns the number of transitions, or -1 if `times` would overflow. */
long fd_slice_times(const double *x, long n, double h, int *state, double *prev,
                    double base, double *times, long maxt) {
    int s = *state; double p = *prev; long nt = 0;
    for (long i = 0; i < n; i++) {
        double xi = x[i];
        if (!s && xi > h) {
            s = 1; if (nt >= maxt) return -1;
            double f = (h - p) / (xi - p); if (!(f >= 0.0 && f <= 1.0)) f = 1.0;
            times[nt++] = base + (double)i - 1.0 + f;
        } else if (s && xi < -h) {
            s = 0; if (nt >= maxt) return -1;
            double f = (-h - p) / (xi - p); if (!(f >= 0.0 && f <= 1.0)) f = 1.0;
            times[nt++] = base + (double)i - 1.0 + f;
        }
        p = xi;
    }
    *state = s; *prev = p;
    return nt;
}

/* The analog (monostable) interval classifier of fast.c_mono_decode, run on
   continuous transition times instead of integer samples. */
long fd_mono_times(const double *t, long n, double spb, double thr_frac,
                   double dead_frac, uint8_t *bits, long maxout) {
    double thr = thr_frac * spb, dead = dead_frac * spb, last = 0.0;
    int at_mid = 0; long nb = 0;
    for (long i = 0; i < n; i++) {
        double gap = t[i] - last;
        if (gap < dead) continue;
        last = t[i];
        if (nb >= maxout) break;
        if (gap > thr) { bits[nb++] = 1; at_mid = 0; }
        else if (at_mid) { bits[nb++] = 0; at_mid = 0; }
        else at_mid = 1;
    }
    return nb;
}

/* Saturating up/down integrator (a random-walk filter) clocked at the fast
   sample rate.  Count c in [0, K]: +1 on a 1 sample, -1 on a 0 sample.
   mode 0: out = 1 above K/2, 0 below, hold at exactly K/2.
   mode 1: out = 1 at c == K, 0 at c == 0, hold between (full-rail hysteresis). */
void fd_sat(const uint8_t *q, long n, int K, int mode, uint8_t *out) {
    int c = 0, o = 0;
    for (long i = 0; i < n; i++) {
        if (q[i]) { if (c < K) c++; } else { if (c > 0) c--; }
        if (mode == 0) { if (2 * c > K) o = 1; else if (2 * c < K) o = 0; }
        else { if (c == K) o = 1; else if (c == 0) o = 0; }
        out[i] = (uint8_t)o;
    }
}

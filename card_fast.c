/*
 * Circuit-level CVSD engine for the channel card: cvsd.py's loop with the
 * imperfections a discrete build has.  With every imperfection at zero it is
 * bit-identical to cvsd.encode / cvsd.decode (checked by card.py selftest).
 *
 *   gcc -O3 -march=native -ffp-contract=off -shared -fPIC -o libcardfast.so card_fast.c -lm
 *
 * prm[] layout (see card.py CardParams.vector):
 *   0 rate          bit rate, Hz
 *   1 run_length    coincidence window, bits
 *   2 tau_syl       syllabic filter, s
 *   3 tau_int       integrator leak, s
 *   4 step_max      step at full syllabic, FS per nominal bit   (I_max T / C_int)
 *   5 step_min      step at zero syllabic, FS per nominal bit   (I_min T / C_int)
 *   6 ks            syllabic path gain                     (nominal 1)
 *   7 off           syllabic path offset, syllabic units   (nominal 0; <0 is a dead zone)
 *   8 asym          up/down current mismatch: up x(1+asym), down x(1-asym)
 *   9 cmp_off       comparator offset, FS
 *  10 cmp_hyst      comparator hysteresis, FS, full width
 *  11 cmp_delay     comparator decision delay, fraction of a bit
 *
 * Step law:  step = step_min + (step_max - step_min) * max(0, ks*syl + off)
 * The arithmetic follows cvsd.py term for term, so the nominal case is exact.
 */
#include <stdint.h>
#include <math.h>

static double step_of(const double *p, double syl) {
    double g = p[6] * syl + p[7];
    if (g < 0) g = 0;
    double s = p[5] + g * (p[4] - p[5]);
    return s < 0 ? 0 : s;
}

void c_card_encode(const double *x, long n, const double *p,
                   uint8_t *bits, double *yout, double *sylout) {
    double dt = 1.0 / p[0];
    int run = (int)p[1];
    unsigned mask = (1u << run) - 1u;
    double a_syl = 1.0 - exp(-dt / p[2]);
    double a_int = exp(-dt / p[3]);
    double k = dt * p[0];
    double up = k * (1.0 + p[8]), dn = k * (1.0 - p[8]);
    double h2 = 0.5 * p[10], d = p[11];
    double y = 0.0, yprev = 0.0, syl = 0.0, xprev = 0.0;
    unsigned hist = 0;
    int b = 0;
    for (long i = 0; i < n; i++) {
        double xe = x[i] - d * (x[i] - xprev);
        double ye = y - d * (y - yprev);
        double diff = xe - ye - p[9];
        if (h2 <= 0) b = diff >= 0;
        else if (diff >= h2) b = 1;
        else if (diff < -h2) b = 0;
        bits[i] = (uint8_t)b;
        hist = ((hist << 1) | (unsigned)b) & mask;
        double coin = (hist == 0 || hist == mask) ? 1.0 : 0.0;
        syl += (coin - syl) * a_syl;
        double s = step_of(p, syl);
        yprev = y;
        y = (y + (b ? s * up : -s * dn)) * a_int;
        xprev = x[i];
        if (yout) yout[i] = y;
        if (sylout) sylout[i] = syl;
    }
}

void c_card_decode(const uint8_t *bits, long n, const double *p,
                   double *yout, double *sylout) {
    double dt = 1.0 / p[0];
    int run = (int)p[1];
    unsigned mask = (1u << run) - 1u;
    double a_syl = 1.0 - exp(-dt / p[2]);
    double a_int = exp(-dt / p[3]);
    double k = dt * p[0];
    double up = k * (1.0 + p[8]), dn = k * (1.0 - p[8]);
    double y = 0.0, syl = 0.0;
    unsigned hist = 0;
    for (long i = 0; i < n; i++) {
        int b = bits[i] ? 1 : 0;
        hist = ((hist << 1) | (unsigned)b) & mask;
        double coin = (hist == 0 || hist == mask) ? 1.0 : 0.0;
        syl += (coin - syl) * a_syl;
        double s = step_of(p, syl);
        y = (y + (b ? s * up : -s * dn)) * a_int;
        yout[i] = y;
        if (sylout) sylout[i] = syl;
    }
}

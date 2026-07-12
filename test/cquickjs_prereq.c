/* feature-c-corpus-quickjs prerequisites: gcc bit-scan builtins (renamed by
   cfront to crtl helpers), the C99 math additions, and pthread_once +
   condition variables (palsync bridge). Exit 42 = all good. */
#include <math.h>
#include <pthread.h>
#include <stdio.h>

static int once_hits;
static pthread_once_t once_guard = PTHREAD_ONCE_INIT;
static void once_cb(void) { once_hits++; }

int main(void) {
    pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
    pthread_cond_t c = PTHREAD_COND_INITIALIZER;
    struct timespec ts;
    double r;

    /* bit-scan builtins */
    if (__builtin_clz(1u) != 31) { printf("clz32\n"); return 1; }
    if (__builtin_clz(0x80000000u) != 0) { printf("clz32b\n"); return 1; }
    if (__builtin_clzll(1ull) != 63) { printf("clz64\n"); return 1; }
    if (__builtin_ctz(8u) != 3) { printf("ctz32\n"); return 1; }
    if (__builtin_ctzll(0x100000000ull) != 32) { printf("ctz64\n"); return 1; }
    if (__builtin_popcount(0xF0F0u) != 8) { printf("pop32\n"); return 1; }
    if (__builtin_popcountll(0xFF00000000ull) != 8) { printf("pop64\n"); return 1; }

    /* C99 math additions */
    if (scalbn(3.0, 4) != 48.0) { printf("scalbn\n"); return 1; }
    if (!isfinite(1.5) || isfinite(1.0 / 0.0) || isfinite(nan(""))) { printf("isfinite\n"); return 1; }
    if (signbit(-2.0) == 0 || signbit(2.0) != 0) { printf("signbit\n"); return 1; }
    if (!isnan(nan(""))) { printf("nan\n"); return 1; }
    r = remainder(5.0, 3.0);           /* 5 = 2*3 - 1 -> -1 */
    if (r != -1.0) { printf("remainder %f\n", r); return 1; }
    if (fabs(expm1(1e-9) - 1e-9) > 1e-18) { printf("expm1\n"); return 1; }
    if (fabs(log1p(1e-9) - 1e-9) > 1e-18) { printf("log1p\n"); return 1; }
    if (fabs(acosh(1.0)) > 1e-12) { printf("acosh\n"); return 1; }
    if (fabs(asinh(-0.5) + asinh(0.5)) > 1e-12) { printf("asinh\n"); return 1; }
    if (fabs(atanh(0.5) - 0.5493061443340549) > 1e-12) { printf("atanh\n"); return 1; }

    /* pthread_once: exactly one hit across two calls */
    pthread_once(&once_guard, once_cb);
    pthread_once(&once_guard, once_cb);
    if (once_hits != 1) { printf("once\n"); return 1; }

    /* condvar single-thread: signalled-before-timedwait must not deadlock; an
       unsignalled timedwait must time out (relative ~1ms budget). */
    pthread_mutex_lock(&m);
    clock_gettime(CLOCK_MONOTONIC, &ts);
    ts.tv_nsec += 1000000;   /* +1ms */
    if (ts.tv_nsec >= 1000000000) { ts.tv_sec++; ts.tv_nsec -= 1000000000; }
    if (pthread_cond_timedwait(&c, &m, &ts) != 110 /* ETIMEDOUT */) {
        printf("timedwait\n"); return 1;
    }
    pthread_mutex_unlock(&m);

    return 42;
}

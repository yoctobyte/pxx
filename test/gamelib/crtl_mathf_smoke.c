/* crtl single-precision <math.h> smoke (game-library ladder). Exercises the
   f-suffix family that returns float — the cdecl float-return ABI fix
   (bug-c-float-single-return-zero) makes these correct. Exit 42. */
#include <math.h>
int printf(const char *, ...);
static int near(float a, float b) { float d = a - b; if (d < 0.0f) d = -d; return d < 0.001f; }
int main(void) {
    if (!near(fabsf(-3.5f), 3.5f)) return 1;
    if (!near(sqrtf(16.0f), 4.0f)) return 2;
    if (!near(floorf(3.9f), 3.0f) || !near(ceilf(3.1f), 4.0f)) return 3;
    if (!near(fminf(2.0f, 5.0f), 2.0f) || !near(fmaxf(2.0f, 5.0f), 5.0f)) return 4;
    if (fmin(1.0, 2.0) != 1.0 || fmax(2.0, 1.0) != 2.0) return 5;
    { float ip; float fr = modff(2.75f, &ip); if (!near(ip, 2.0f) || !near(fr, 0.75f)) return 6; }
    if (!near(powf(2.0f, 10.0f), 1024.0f)) return 7;
    if (!near(truncf(-3.9f), -3.0f) || !near(roundf(2.6f), 3.0f)) return 8;
    return 42;
}

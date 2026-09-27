/* fesetround EITHER ROUNDS IN THE MODE IT ACCEPTED OR REFUSES IT.
 *
 * On every target but x86-64 fesetround was `return 0`: it reported success
 * and nothing changed, so fegetround still answered FE_TONEAREST and 1/3
 * still rounded to nearest (crtl_setjmp_oracle's after-set row). Now i386
 * sets MXCSR and the x87 word, aarch64 FPCR, arm32 FPSCR; riscv32 does its
 * doubles in softfloat, which honours no mode, so it refuses (nonzero) any
 * mode but FE_TONEAREST.
 * bug-c-fesetround-reports-success-on-a-target-that-ignores-it
 *
 * The row for each mode is "accepted and in effect, or refused and nearest
 * kept", the same line on every target: one .expected serves all five.
 */
#include <stdio.h>
#include <fenv.h>

static volatile double one = 1.0, three = 3.0, big = 1e16;

int main(void) {
  int m[4] = {FE_TONEAREST, FE_DOWNWARD, FE_UPWARD, FE_TOWARDZERO};
  double qn, nn, qd, qu, nd, nu;
  int i, r, ok;
  qn = one / three; nn = -one / three;
  /* the directed results, spelled from the nearest one: to nearest, 1/3
     rounds DOWN (0x3FD5555555555555), so upward is one ulp (2^-54) above it
     and -1/3 downward one ulp below -qn */
  qd = qn; nu = -qn;
  qu = qn + 5.5511151231257827e-17;
  nd = nn - 5.5511151231257827e-17;
  for (i = 0; i < 4; i++) {
    double q, n, s;
    r = fesetround(m[i]);
    q = one / three; n = -one / three; s = big + 1.0;
    fesetround(FE_TONEAREST);
    if (r != 0)
      ok = fegetround() == FE_TONEAREST && q == qn && n == nn && s == 1e16;
    else if (m[i] == FE_TONEAREST)
      ok = q == qn && n == nn && s == 1e16;
    else if (m[i] == FE_DOWNWARD)
      ok = q == qd && n == nd && s == 1e16;
    else if (m[i] == FE_UPWARD)
      ok = q == qu && n == nu && s == 1e16 + 2;
    else
      ok = q == qd && n == nu && s == 1e16;
    printf("mode %d: %s\n", i, ok ? "rounds-or-refuses" : "WRONG");
  }
  r = fesetround(FE_TOWARDZERO);
  printf("get-agrees-with-set: %d\n", r != 0 ? fegetround() == FE_TONEAREST : fegetround() == FE_TOWARDZERO);
  fesetround(FE_TONEAREST);
  printf("restored: %d\n", fegetround() == FE_TONEAREST);
  return 0;
}

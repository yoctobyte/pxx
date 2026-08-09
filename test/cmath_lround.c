/* SPDX-License-Identifier: Zlib */
/*
 * lround/llround, and the C side of the rounding contract.
 *
 * C's round() is specified half-away-from-zero, which DISAGREES with Pascal's
 * ties-to-even Round and with CPython's round(). All three are correct for
 * their own language — see test/lib_rounding_contract.pas before "harmonising"
 * anything. The 2.5 and -2.5 rows are where they visibly differ: C says 3 and
 * -3 where Pascal says 2 and -2.
 *
 * lround/llround were DECLARED but unimplemented while their lrint/llrint twins
 * existed — an odd pair to split, since they differ only in the rounding rule
 * (lrint follows the current mode, lround is always half-away-from-zero).
 * lrint is printed alongside so the two stay visibly distinct: look at the 0.5,
 * 2.5 and -2.5 rows, where lround and lrint give different answers.
 *
 * Expectations are gcc's own output.
 */
#include <stdio.h>
#include <math.h>
int main(void) {
  double v[] = {0.5, 1.5, 2.5, 3.5, -0.5, -1.5, -2.5, 2.7, -2.7, 0.0};
  for (int i = 0; i < 10; i++)
    printf("%.1f lround=%ld llround=%lld lrint=%ld\n", v[i], lround(v[i]), llround(v[i]), lrint(v[i]));
  return 0;
}

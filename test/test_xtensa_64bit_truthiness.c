/* A 64-bit value used as a CONDITION on xtensa: the branch tested only the
 * low word, so `if (x)` and `while (x)` were false for 0xabcd00000000, and
 * crtl's %llx -- a `while (x)` shift loop -- printed an empty string or only
 * the low digits (c-testsuite 00204 on esp32s3). `x != 0` was right all along,
 * which is why the probe carries both spellings.
 * bug-32bit-truthiness-high-half: the other 32-bit backends had the fix. */
#include <stdio.h>

static int nz(unsigned long long x) { return x != 0; }
static int tr(unsigned long long x) { if (x) return 1; return 0; }
static int wl(unsigned long long x) { int n = 0; while (x) { x >>= 4; n++; } return n; }
static int tn(long long x) { return x ? 1 : 0; }

int main(void) {
  unsigned long long v = 0xabcd00000000ull;
  printf("%d %d %d %d %d\n", nz(v), tr(v), wl(v), !v, tn((long long)v));
  printf("%llx|%llx|%llx\n", v, 0xabcd000000001234ull, 0xabcd123400000000ull);
  return 0;
}

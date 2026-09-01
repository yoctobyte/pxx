/* sizeof yields size_t, which is UNSIGNED (C 6.5.3.4). The SIZES were always
 * right; what was wrong was every operator that consumed one.
 *
 * THIS TEST EXISTS BECAUSE AN ISOLATED PROBE CANNOT FIND THIS. Printing a
 * sizeof, subtracting two of them and printing the difference, `sizeof(a) - 1`
 * and `(int)(sizeof(a) - sizeof(b))` were ALL already correct -- the result
 * node was tagged tyInteger and none of those rows can tell. It takes a SECOND
 * operator consuming the result: a comparison, a division, a shift. Measured
 * against gcc before the fix:
 *
 *     -1 < sizeof(int)               gcc 0   pxx 1
 *     (sizeof(a) - sizeof(b)) > 0    gcc 1   pxx 0
 *     (sizeof(a) - sizeof(b)) / 2    gcc unsigned division, pxx signed
 *     (sizeof(a) - sizeof(b)) >> 1   gcc shr, pxx sar
 *
 * frankD hit the identical shape on `ptr - ptr` the same day (52ad546b9): the
 * subtraction was right and only `q - p + 1` exposed it. Same lesson twice in
 * one file's worth of C: a type error hides until a second operator reads the
 * type. That is why the rows below are all two-operator, and why the
 * everyday-idiom rows are kept beneath them as the controls -- a "fix" that
 * made sizeof unsigned and broke `sizeof(a)/sizeof(a[0])` must fail here. */
#include <stdio.h>
#include <string.h>
struct T { int a; char b[7]; };
int a[1]; long b[4]; int arr[13]; struct T ts[5];
char dst[64];

int main(void)
{
  int i, n = 0, bad = 0;
#define CHK(label, e, want) do { \
    long long got = (long long)(e); \
    printf("%-11s %lld\n", label, got); \
    if (got != (long long)(want)) bad++; \
  } while (0)

  /* two-operator rows: the ones that can fail */
  CHK("neg<sizeof", -1 < sizeof(int), 0);          /* -1 converts to huge unsigned */
  CHK("diff>0",     (sizeof(a) - sizeof(b)) > 0, 1);
  CHK("diff/2",     (sizeof(a) - sizeof(b)) / 2, 9223372036854775794ULL);
  CHK("diff>>1",    (sizeof(a) - sizeof(b)) >> 1, 9223372036854775794ULL);

  /* one-operator rows: correct before AND after, kept to show what a probe
     that only looked here would have concluded */
  CHK("diff",       sizeof(a) - sizeof(b), (long long)(sizeof(a) - sizeof(b)));
  CHK("sizeof-1",   sizeof(a) - 1, 3);
  CHK("castint",    (int)(sizeof(a) - sizeof(b)), -28);

  /* controls: the everyday idioms must not move */
  CHK("count",      sizeof(arr)/sizeof(arr[0]), 13);
  CHK("count2",     sizeof(ts)/sizeof(ts[0]), 5);
  CHK("halfway",    sizeof(arr) / 2, 26);
  CHK("minus",      sizeof(arr) - sizeof(int), 48);
  memcpy(dst, "hello", sizeof("hello"));
  CHK("memcpy",     sizeof("hello"), 6);
  { char buf[sizeof(struct T) * 2]; CHK("extent", sizeof(buf), 24); }
  for (i = 0; i < (int)(sizeof(arr)/sizeof(arr[0])); i++) n += i;
  CHK("loop",       n, 78);
  printf("varargs-zu %zu\n", sizeof(struct T));
  if (sizeof(struct T) != 12) bad++;

  printf(bad == 0 ? "SIZEOF SIGN OK\n" : "SIZEOF SIGN FAIL\n");
  return bad == 0 ? 0 : 1;
}

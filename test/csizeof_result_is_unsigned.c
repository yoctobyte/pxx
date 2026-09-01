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
 * made sizeof unsigned and broke `sizeof(a)/sizeof(a[0])` must fail here.
 *
 * NO 64-BIT CONSTANTS, AND THAT IS THE SECOND LESSON. The first version of
 * this file asserted (sizeof(a)-sizeof(b))/2 == 9223372036854775794, which is
 * 2^63-14 -- true only where size_t is 64 bits. size_t is POINTER-WIDTH
 * unsigned, so the same expression is 2147483642 on i386/arm32/riscv32, and a
 * test that hard-codes the x86-64 answer cannot be run on the targets where
 * the interesting bugs live. It also meant this file could not have caught the
 * width bug my own signedness fix introduced: I tagged the node tyUInt64 when
 * size_t is tyNativeUInt, which is right on x86-64 and wrong on every 32-bit
 * target (frankD, c-testsuite 00184.c, NEW-RED on three conformance shards).
 * The assertions below therefore discriminate on a PROPERTY that holds at any
 * width -- an unsigned division of a wrapped difference is huge, a signed one
 * is a small negative -- rather than on a value that holds at one width.
 *
 * WHAT THIS FILE STILL CANNOT SEE, stated so nobody reads it as coverage: the
 * variadic width class. `printf("%d %d", sizeof(char), sizeof(a))` pushes the
 * wrong slot width on a 32-bit target and reads the high half of the previous
 * argument, and on x86-64 the arguments go in registers and it works by
 * construction. That row needs a CROSS run; it is not observable here. */
#include <stdio.h>
#include <string.h>
#include <stddef.h>
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
  /* `> 0`, NOT `> 1000000u`. The magnitude test I wrote first CANNOT FAIL:
     comparing against an unsigned constant re-promotes a signed left operand,
     so the buggy signed -14 becomes huge and passes the very row aimed at it.
     Against plain `0` the usual conversions keep a signed expression signed,
     so -14 > 0 is false and a wrapped unsigned value is true -- at any width.
     ctl-signed below is the positive control for exactly this row. */
  CHK("diff/2",     ((sizeof(a) - sizeof(b)) / 2) > 0, 1);
  CHK("diff>>1",    ((sizeof(a) - sizeof(b)) >> 1) > 0, 1);
  /* POSITIVE CONTROL, same shape with the operands forced SIGNED: this one
     must come out 0. It proves the `> 0` rows above can produce 0 at all --
     without it they are two assertions nothing has ever seen fail. */
  CHK("ctl-signed", (((ptrdiff_t)sizeof(a) - (ptrdiff_t)sizeof(b)) / 2) > 0, 0);
  /* and size_t really is pointer-width, which is the thing tyUInt64 got wrong */
  CHK("szt=ptr",    sizeof(size_t) == sizeof(void *), 1);

  /* one-operator rows: correct before AND after, kept to show what a probe
     that only looked here would have concluded */
  CHK("sizeof-1",   sizeof(a) - 1, 3);
  CHK("castint",    (int)(sizeof(a) - sizeof(b)),
                    (int)(sizeof(a)) - (int)(sizeof(b)));

  /* controls: the everyday idioms must not move */
  CHK("count",      sizeof(arr)/sizeof(arr[0]), 13);
  CHK("count2",     sizeof(ts)/sizeof(ts[0]), 5);
  CHK("halfway",    sizeof(arr) / 2, (13 * sizeof(int)) / 2);
  CHK("minus",      sizeof(arr) - sizeof(int), 12 * sizeof(int));
  memcpy(dst, "hello", sizeof("hello"));
  CHK("memcpy",     sizeof("hello"), 6);
  { char buf[sizeof(struct T) * 2];
    CHK("extent", sizeof(buf), 2 * sizeof(struct T)); }
  for (i = 0; i < (int)(sizeof(arr)/sizeof(arr[0])); i++) n += i;
  CHK("loop",       n, 78);
  printf("varargs-zu %zu\n", sizeof(struct T));
  if (sizeof(struct T) != sizeof(int) + 8) bad++;

  printf(bad == 0 ? "SIZEOF SIGN OK\n" : "SIZEOF SIGN FAIL\n");
  return bad == 0 ? 0 : 1;
}

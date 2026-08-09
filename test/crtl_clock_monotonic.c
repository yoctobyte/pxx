/* clock() returns plausible CPU microseconds with a non-negative delta.
 *
 * This is the behaviour a Track B workaround protected until 2026-08-09.
 * __pxx_clock is `Int64(ts.Sec) * 1000000 + Int64(ts.Nsec) div 1000`, and the
 * EXPLICIT Int64() cast of a 4-byte NativeInt used to REINTERPRET eight bytes
 * on i386/arm32 rather than sign-extend four
 * (bug-a-explicit-int64-cast-of-nativeint-does-not-extend-on-32bit), so clock()
 * came back as a huge random number whose successive readings went BACKWARDS.
 * The workaround spelled the widening implicitly; with the compiler fixed the
 * idiomatic one-liner is back, and this is what says so.
 *
 * The delta is the assertion that matters: a garbage high half shows up as a
 * negative or absurd difference between two readings long before it shows up as
 * an implausible single value. lib-test runs this on x86-64 only — the failure
 * was 32-bit-specific, so the cross check is the point rather than a bonus, and
 * it lives in the commit that reverted the workaround (verified on i386 and
 * arm32 under qemu).
 *
 * printf-free: exit code only, so a varargs bug cannot masquerade as a clock bug.
 */
#include <time.h>

int main(void) {
  clock_t a, b;
  long d, i;
  volatile long sink = 0;

  a = clock();
  if ((long)a < 0) return 1;

  for (i = 0; i < 3000000; i++) sink += i;

  b = clock();
  if ((long)b < 0) return 2;

  d = (long)(b - a);
  if (d < 0) return 3;              /* time ran backwards: the 32-bit failure */
  if (d > 100000000L) return 4;     /* > 100 s of CPU for that loop: garbage   */

  return 42;
}

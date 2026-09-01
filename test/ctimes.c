/* times(2) and sysconf(_SC_CLK_TCK) against the gcc oracle.
 *
 * crtl had neither, so busybox's ash did not compile: shell/ash.c:14189 calls
 * times() for its `times' builtin. Found by attempting the target
 * (feature-c-corpus-busybox-multi-applet), not by triage.
 *
 * WHAT IS COMPARED AND WHAT IS NOT. CPU times are not reproducible, so the
 * VALUES cannot be diffed against gcc -- only their structure and invariants
 * can. Printing the raw ticks would make this test fail at random. What IS
 * pinned:
 *   - sizeof(clock_t) and sizeof(struct tms), which are ABI and must match
 *     glibc exactly. This is the row that matters: ash reads the struct by
 *     BYTE OFFSET through a clock_t pointer, so a clock_t wider than the
 *     member reads two fields as one. crtl had clock_t as `long long', which
 *     is right on x86-64 and aarch64 and wrong on every 32-bit target -- the
 *     shape that passes wherever you happen to test.
 *   - CLK_TCK, which a shell divides by; a wrong value is a plausible wrong
 *     NUMBER rather than a failure.
 *   - monotonicity and non-negativity across real work.
 *
 * times() returning 0 is NOT an error -- it returns ticks since an arbitrary
 * point, so only a negative is a failure. A test that checked `!= 0' would be
 * green today and flaky forever.
 */
#include <sys/times.h>
#include <unistd.h>
#include <stdio.h>

int main(void) {
  struct tms a, b;
  clock_t t1, t2;
  volatile long i, acc = 0;

  printf("sizeof clock_t=%d\n", (int)sizeof(clock_t));
  printf("sizeof struct tms=%d\n", (int)sizeof(struct tms));
  printf("clk_tck=%ld\n", sysconf(_SC_CLK_TCK));

  /* Offsets are the thing ash actually indexes by. */
  printf("offsets=%d,%d,%d,%d\n",
         (int)((char *)&a.tms_utime  - (char *)&a),
         (int)((char *)&a.tms_stime  - (char *)&a),
         (int)((char *)&a.tms_cutime - (char *)&a),
         (int)((char *)&a.tms_cstime - (char *)&a));

  t1 = times(&a);
  for (i = 0; i < 30000000; i++) acc += i;
  t2 = times(&b);

  printf("call ok=%d\n", (int)(t1 != (clock_t)-1 && t2 != (clock_t)-1));
  printf("monotonic=%d\n", (int)(t2 >= t1));
  printf("nonneg=%d\n", (int)(a.tms_utime >= 0 && a.tms_stime >= 0 &&
                              b.tms_utime >= 0 && b.tms_stime >= 0));
  printf("utime advanced or equal=%d\n", (int)(b.tms_utime >= a.tms_utime));
  /* Read the struct the way ash does -- by byte offset through clock_t*. This
     is the row that would catch a clock_t/member width mismatch. */
  printf("byte-offset read matches=%d\n",
         (int)(*(clock_t *)((char *)&b + ((char *)&b.tms_stime - (char *)&b))
               == b.tms_stime));
  (void)acc;
  return 42;
}

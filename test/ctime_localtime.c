/* localtime() honouring the timezone (feature-crtl-localtime-honours-the-
 * timezone). It used to be gmtime(), so every local timestamp a C program
 * printed was UTC — silently, since 22:13 is as plausible as 23:13.
 *
 * The offset comes from the TZif file that $TZ or /etc/localtime names, NOT
 * from a POSIX TZ rule string: a TZif carries precomputed transitions, so DST
 * is a lookup rather than rule evaluation and there is no
 * right-for-half-the-year failure mode.
 *
 * The zone comes from the ENVIRONMENT and the harness runs this once per zone.
 * It deliberately does not setenv("TZ") mid-process: glibc caches the zone
 * until tzset(), so a self-contained loop silently compares UTC against UTC —
 * which is exactly what the first version of this test did, and it "passed"
 * against gcc for every zone.
 *
 * Written with parenthesised sizeof: the unparenthesised array-length idiom
 * `sizeof times / sizeof times[0]` does not parse
 * (bug-cfront-sizeof-unparenthesised-subscript).
 *
 * Diffed whole against the same file built by gcc, over instants chosen to
 * cover what a single-zone test misses: a NEGATIVE offset (the case that caught
 * a sign-extension bug — +3600 read back fine while -18000 did not), a
 * non-whole-hour offset, southern-hemisphere DST, and both sides of a
 * transition in each direction.
 */
#include <stdio.h>
#include <string.h>
#include <time.h>

int main(void) {
  time_t times[] = {
    1700000000,   /* northern winter */
    1688000000,   /* northern summer */
    1679792400,   /* EU spring-forward, just after */
    1679788800,   /*                    just before */
    1698541200,   /* EU fall-back, just after */
    1698537600    /*               just before */
  };
  unsigned i;
  for (i = 0; i < sizeof(times) / sizeof(times[0]); i++) {
    struct tm g, l; char gb[40], lb[40];
    time_t t = times[i];
    memset(&g, 0, sizeof g); memset(&l, 0, sizeof l);
    gmtime_r(&t, &g);
    localtime_r(&t, &l);
    strftime(gb, sizeof gb, "%Y-%m-%d %H:%M:%S", &g);
    strftime(lb, sizeof lb, "%Y-%m-%d %H:%M:%S", &l);
    printf("%ld utc=%s local=%s\n", (long)t, gb, lb);
  }
  return 0;
}

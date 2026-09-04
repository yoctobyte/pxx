/* time(), clock(), clock_gettime() and exit() for C, ALL FOUR THROUGH THE PAL,
   on every target we can run.

   WHY THIS EXISTS. lib/rtl/pxxcio.pas used to carry its own per-target syscall
   number tables for exit_group/exit and for clock_gettime, duplicating
   platform.pas's. The exit one was wrong: hardcoded to x86-64's 231, which on
   i386 is fgetxattr, so C's `exit(3)` quietly failed an xattr call, returned,
   and the process exited 0 -- every i386 program that reported failure through
   exit() reported SUCCESS. Nothing caught it because `return n` from main is a
   different path (the entry stub's own exit) and that path was fine. The clock
   table then omitted riscv32 deliberately, which hid a real -ENOSYS in the PAL
   behind a local 0-stub. Two tables, two silences.

   So the row that matters here is not "does time() work" -- it is EXIT CODE 7
   OBSERVED ON A CROSS TARGET, which is the one assertion the i386 bug could not
   have survived, and which no wired test made before this one.

   THE ARGUMENT IS THE POINT. argv[1] says whether this target is expected to
   have a working clock. It is 1 everywhere except riscv32, where the PAL issues
   asm-generic 113 and rv32 is time64-only, so the kernel answers -ENOSYS
   (bug-b-palnanosleep-answers-enosys-on-riscv32-because-rv32-has-no-nanosleep-syscall).
   Passing the expectation in rather than letting the program shrug means the
   riscv32 hole is ASSERTED, not tolerated: when that bug is fixed the Makefile
   row flips to 1 and this test says so. It also gives the harness a must-FAIL
   case -- run riscv32 with a 1 and this program must exit 1 -- so the check is
   one that can come out false. */

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static int fails = 0;

static void check(const char *what, int got, int want)
{
  if (got != want) { printf("FAIL %s: got %d want %d\n", what, got, want); fails++; }
}

int main(int argc, char **argv)
{
  int expect_clock = (argc > 1 && argv[1][0] == '1') ? 1 : 0;
  struct timespec ts;
  time_t t;
  clock_t c0, c1;
  volatile long acc = 0;
  long i;
  int cg_rc, plausible, contract_ok;

  ts.tv_sec = 123; ts.tv_nsec = 456;        /* NOT zero: see contract_ok below */
  cg_rc = clock_gettime(CLOCK_REALTIME, &ts);
  t = time(NULL);
  c0 = clock();
  for (i = 0; i < 3000000; i++) acc += i;
  c1 = clock();

  /* The success arm, and the pre-seeded 123/456 is what gives it teeth: a body
     that returned 0 without ever writing the struct would pass a plausibility
     check on a zero-initialised one only by luck, and 123 is not a plausible
     wall clock. There is deliberately NO failure-arm assertion. POSIX leaves
     *tp unspecified when clock_gettime fails, and lib/crtl/src/time.c's wrapper
     takes that literally -- on r < 0 it sets errno and returns without touching
     tp. An earlier draft of this test asserted "on failure both fields are
     zero", which riscv32 failed; the wrapper was right and the assertion was
     inventing a contract nobody makes. Measured on riscv32 both before and
     after the pxxcio->PAL move, identically, which is also how it was shown not
     to be a regression. */
  plausible = (ts.tv_sec > 1700000000 && ts.tv_sec < 2200000000
               && ts.tv_nsec >= 0 && ts.tv_nsec < 1000000000);
  contract_ok = (cg_rc != 0) || plausible;
  check("clock_gettime-succeeds-plausibly", contract_ok, 1);

  check("clock_gettime-rc", cg_rc == 0, expect_clock);
  check("time-plausible", (t > 1700000000 && t < 2200000000), expect_clock);
  check("clock-advanced", (c1 > c0), expect_clock);

  /* A relation, so it carries no per-target constant. Only asked where the
     clock works -- comparing two zeroes would be a row that cannot fail. */
  if (expect_clock)
  {
    long d = (long)(t - (time_t)ts.tv_sec);
    if (d < 0) d = -d;
    check("time-agrees-with-clock_gettime", d <= 2, 1);
  }

  if (fails) { printf("pal time+exit: %d row(s) FAILED\n", fails); fflush(stdout); return 1; }
  printf("pal time+exit ok (clock expected: %d)\n", expect_clock);
  fflush(stdout);

  /* THE ROW THE i386 BUG COULD NOT HAVE SURVIVED. exit(), not `return`. */
  exit(7);
  return 9;                                  /* unreachable; 9 would be visible */
}

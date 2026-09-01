/* time_t must have ONE definition in crtl, and it must be the native long.

   It had two. <time.h> said `typedef long long time_t` with a comment claiming
   "64-bit on every pxx target so the 2038 problem never appears"; <sys/types.h>
   said `typedef __time_t time_t` with __time_t == long. Including <time.h>
   auto-pulls crtl/src/time.c, which reaches <sys/types.h>, and the frontend
   takes the LAST of two conflicting typedefs with no diagnostic (gcc errors) --
   so the header's promise was silently false, MEASURED at 4 bytes on i386 with
   <time.h> as the only include.

   Two definitions is the defect whichever width wins, because the width then
   depends on what else the translation unit happened to pull in: two objects
   in one program could disagree about the layout of a struct with a time in
   it, and nothing would say so.

   The rows below are the ones that would have caught it. `sizeof(time_t) ==
   sizeof(long)` is the claim; the round trip through a large negative value is
   there so a change to an UNSIGNED time_t fails here too, since sizeof alone
   cannot see signedness -- the gap frankD's ctimes test has by their own
   account. bug-c-the-frontend-takes-the-last-of-two-conflicting-typedefs-silently */
#include <stdio.h>
#include <time.h>
#include <sys/types.h>

/* Reached through BOTH headers on purpose, and this global is the row that
   actually catches it. MEASURED, with the conflicting `typedef long long
   time_t` put back into <time.h>: i386 prints `sizeof(time_t)=4
   sizeof(long)=4` -- the two width rows AGREE and pass -- and still fails,
   because `g` was laid out at 8. One translation unit, two answers for one
   type, which is the whole hazard. x86-64 stays green throughout, since long
   and long long are the same width there: the shape that passes where you
   test. */
static time_t g;

int main(void)
{
  int bad = 0;
  time_t v;

  printf("sizeof(time_t)=%d sizeof(long)=%d\n", (int)sizeof(time_t), (int)sizeof(long));
  if (sizeof(time_t) != sizeof(long)) bad++;
  if (sizeof(g) != sizeof(long)) bad++;

  /* Signed, and wide enough to hold a pre-epoch time. An unsigned time_t has
     the same sizeof and would pass every width row. */
  v = -1;
  printf("negative=%d\n", v < 0 ? 1 : 0);
  if (!(v < 0)) bad++;

  /* The largest value a 32-bit signed time_t holds: 2038-01-19T03:14:07Z. It
     must survive a round trip through the type on every target, including the
     64-bit ones where the type is wider. */
  v = 2147483647;
  printf("y2038=%ld\n", (long)v);
  if ((long)v != 2147483647L) bad++;

  printf(bad == 0 ? "TIME_T OK\n" : "TIME_T FAIL\n");
  return bad == 0 ? 0 : 1;
}

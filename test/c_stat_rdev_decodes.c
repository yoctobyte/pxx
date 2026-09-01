/* A dev_t that came from the KERNEL decodes with the same macros that build one.

   c_sysmacros_dev.c already checks major()/minor()/makedev() against glibc's
   numbers, row for row, and it stayed green through the whole life of this bug.
   It could not see it: every dev_t it examines is one makedev() just built, so
   it proves the three macros agree WITH EACH OTHER. The population the question
   is actually about — a dev_t filled in by stat(2) — was not in it.

   And the failure is silent by construction. The PAL packed st_dev and st_rdev
   with the kernel-INTERNAL spelling, (major << 20) | minor, instead of the
   userspace one glibc's macros implement. MKDEV(1,3) is 0x100003, which is a
   perfectly good number: crtl's major() returned 0 and minor() returned 259 for
   /dev/null, nothing errored, and `ls -l /dev` would have printed 0, 259.
   Measured against glibc on the same box and the same file: st_rdev is 0x103.

   /dev/null is 1:3 and /dev/zero is 1:5 on every Linux, which is what makes
   this checkable without root. The makedev round-trip rows stay too, so a fix
   that "corrects" the macros to match a broken encoder fails here rather than
   passing both ways. bug-a-stat-returns-st-dev-and-st-rdev-in-the-kernel-internal-encoding */
#include <stdio.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>

int main(void)
{
  struct stat st;
  dev_t d;
  int bad = 0;

  if (stat("/dev/null", &st) != 0) { printf("FAIL: cannot stat /dev/null\n"); return 1; }
  printf("null %u:%u want 1:3\n", major(st.st_rdev), minor(st.st_rdev));
  if (major(st.st_rdev) != 1 || minor(st.st_rdev) != 3) bad++;

  if (stat("/dev/zero", &st) != 0) { printf("FAIL: cannot stat /dev/zero\n"); return 1; }
  printf("zero %u:%u want 1:5\n", major(st.st_rdev), minor(st.st_rdev));
  if (major(st.st_rdev) != 1 || minor(st.st_rdev) != 5) bad++;

  /* st_dev is the same encoder and had the same bug, but it is NOT checkable
     here: its value is whatever filesystem /dev sits on, and a devtmpfs st_dev
     of 0:6 decodes to 0:6 under both encodings -- a zero major hides the
     defect. There is no assertion to write, so there is no row; a
     `dev_decodes=1` line that is 1 either way would be a guard that cannot
     fail. The rows below and the two above are what carry st_dev too, since
     one encoder fills both fields. */

  /* Kept from the sibling test on purpose: a "fix" that changes the MACROS to
     match a wrongly-encoded stat would pass the two rows above and fail here. */
  d = makedev(7, 300);
  printf("makedev(7,300) %u:%u\n", major(d), minor(d));
  if (major(d) != 7 || minor(d) != 300) bad++;
  d = makedev(4096, 1);
  printf("makedev(4096,1) %u:%u\n", major(d), minor(d));
  if (major(d) != 4096 || minor(d) != 1) bad++;

  printf(bad == 0 ? "RDEV OK\n" : "RDEV FAIL\n");
  return bad == 0 ? 0 : 1;
}

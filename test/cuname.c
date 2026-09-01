/* uname(2) against the gcc oracle.
 *
 * crtl had no sys/utsname.h, a hard error when cross-compiling, so busybox's
 * libbb/kernel_version.c did not compile. Found by attempting the target
 * (feature-c-corpus-busybox-multi-applet).
 *
 * WHAT IS COMPARED. The CONTENTS are host facts -- nodename and release differ
 * between machines and across a reboot -- so diffing them against gcc would
 * make this test fail on someone else's box. What is pinned is the ABI, which
 * is the part that can be wrong in a way that matters: the struct is filled by
 * the KERNEL, so field size and offsets are not a choice. 65 bytes per field
 * and 390 total, six fields back to back with no padding.
 *
 * The sysname row is the one content check that IS stable: on Linux it is the
 * string "Linux", and busybox's kernel_version.c parses `release' assuming it.
 */
/* glibc spells the sixth field __domainname unless _GNU_SOURCE is defined;
   busybox defines it, so this test does too and uses the GNU spelling. crtl's
   header carries `#define __domainname domainname' so BOTH spellings work
   there, which is why the row below compiles under either compiler. */
#define _GNU_SOURCE 1
#include <sys/utsname.h>
#include <stdio.h>
#include <string.h>

int main(void) {
  struct utsname u;
  int rc;

  printf("sizeof=%d field=%d\n", (int)sizeof(struct utsname), (int)sizeof(u.sysname));
  printf("offsets=%d,%d,%d,%d,%d,%d\n",
         (int)((char *)&u.sysname    - (char *)&u),
         (int)((char *)&u.nodename   - (char *)&u),
         (int)((char *)&u.release    - (char *)&u),
         (int)((char *)&u.version    - (char *)&u),
         (int)((char *)&u.machine    - (char *)&u),
         (int)((char *)&u.domainname - (char *)&u));

  memset(&u, 0, sizeof u);
  rc = uname(&u);
  printf("rc=%d\n", rc);
  printf("sysname=%s\n", u.sysname);
  /* Non-empty, NUL-terminated within the field: the two properties a caller
     relies on before doing any strtol on them. Values themselves are the
     host's and are deliberately not compared. */
  printf("release nonempty=%d terminated=%d\n",
         (int)(u.release[0] != '\0'),
         (int)(memchr(u.release, '\0', sizeof u.release) != 0));
  printf("machine nonempty=%d terminated=%d\n",
         (int)(u.machine[0] != '\0'),
         (int)(memchr(u.machine, '\0', sizeof u.machine) != 0));
  return 42;
}

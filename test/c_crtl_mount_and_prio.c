/* SPDX-License-Identifier: Zlib */
/*
 * crtl: getsid, get/setpriority, and the addmntent/getmntent_r ROUND TRIP.
 *
 * The three gaps between the busybox userland and `kill -HUP', `nice',
 * `renice', `mount' and `umount'. Asserted against glibc by compiling this
 * same file with gcc.
 *
 * ROW 3 IS THE ONE WITH A WRONG ANSWER AVAILABLE. The kernel does not return
 * the nice value from getpriority(2) -- it returns 20-nice, so that a nice of
 * -1 cannot be read as -EPERM -- and a wrapper that forwards the raw number
 * reports 15 where the process is running at 5. Every value is in range, the
 * call succeeds, and `nice' prints a plausible lie. The row therefore SETS a
 * priority and reads it back rather than trusting whatever the box was at.
 *
 * ROWS 5-7 ARE THE ESCAPE ROUND TRIP. A mount point with a space in it is
 * written `\040' and read back decoded; a writer that skips the escaping
 * produces a table its own reader re-splits into the wrong number of fields,
 * and the failure surfaces as a mount point that does not exist rather than as
 * an error. Row 7 checks the same for a backslash, which is the character that
 * makes a naive writer emit an escape it never meant.
 *
 * Row 2 is a negative control on getsid: an ESRCH, not a silent 0.
 * Row 8 is one on hasmntopt, matching whole elements only.
 *
 * feature-c-crtl-getsid-priority-and-mtab-writing
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <mntent.h>
#include <sys/resource.h>

int main(void) {
  char path[64];
  int sid, sid2, base, got;
  FILE *f;
  struct mntent me, out;
  char buf[512];

  sprintf(path, "/tmp/pxx_mntprio_%d.txt", (int)getpid());

  /* 1: getsid(0) and getsid(getpid()) name the same session. */
  sid  = getsid(0);
  sid2 = getsid(getpid());
  printf("1 %d %d\n", sid > 0, sid == sid2);

  /* 2: a pid that cannot exist -- ESRCH, not a silent answer. */
  errno = 0;
  sid = getsid(0x7ffffffe);
  printf("2 %d %d\n", sid, errno == ESRCH);

  /* 3: set a priority and read it back. See the header -- this is the row the
     kernel's 20-nice encoding would fail. Raising niceness needs no privilege,
     so the test only ever goes up from wherever it started. */
  errno = 0;
  base = getpriority(PRIO_PROCESS, 0);
  if (errno != 0) { printf("3 getpriority-failed\n"); return 1; }
  if (setpriority(PRIO_PROCESS, 0, base + 3) != 0) { printf("3 setpriority-failed\n"); return 1; }
  errno = 0;
  got = getpriority(PRIO_PROCESS, 0);
  printf("3 %d %d\n", got - base, errno);

  /* 4: a `who' nobody owns -- ESRCH, and -1 is the RETURN as well as a legal
     nice value, which is exactly why errno carries the answer. */
  errno = 0;
  got = getpriority(PRIO_PROCESS, 0x7ffffffe);
  printf("4 %d %d\n", got, errno == ESRCH);

  /* 5/6/7: write a table with addmntent, read it back with getmntent_r. */
  f = setmntent(path, "w");
  if (!f) { printf("5 setmntent-failed\n"); return 1; }
  me.mnt_fsname = (char *)"/dev/sda1";
  me.mnt_dir    = (char *)"/mnt/my disk";       /* a SPACE -- must be escaped */
  me.mnt_type   = (char *)"ext4";
  me.mnt_opts   = (char *)"rw,errors=remount-ro";
  me.mnt_freq   = 0;
  me.mnt_passno = 2;
  printf("5 %d\n", addmntent(f, &me));          /* 0 on success, glibc's way round */
  me.mnt_fsname = (char *)"/dev/sdb1";
  me.mnt_dir    = (char *)"/mnt/back\\slash";
  me.mnt_type   = (char *)"vfat";
  me.mnt_opts   = (char *)"ro";
  me.mnt_freq   = 1;
  me.mnt_passno = 0;
  printf("6 %d\n", addmntent(f, &me));
  endmntent(f);

  f = fopen(path, "r");                          /* any FILE*, not a slot */
  if (!getmntent_r(f, &out, buf, (int)sizeof buf)) { printf("7 no-entry\n"); return 1; }
  printf("7 [%s] [%s] [%s] %d %d\n", out.mnt_fsname, out.mnt_dir, out.mnt_type,
         out.mnt_freq, out.mnt_passno);
  /* 8: hasmntopt matches whole comma-separated elements. `ro' is NOT in
     "rw,errors=remount-ro". */
  printf("8 %d %d\n", hasmntopt(&out, "ro") != 0, hasmntopt(&out, "rw") != 0);
  if (!getmntent_r(f, &out, buf, (int)sizeof buf)) { printf("9 no-entry\n"); return 1; }
  printf("9 [%s] [%s] %d %d\n", out.mnt_dir, out.mnt_opts, out.mnt_freq, out.mnt_passno);
  printf("10 %d\n", getmntent_r(f, &out, buf, (int)sizeof buf) == 0);
  fclose(f);

  remove(path);
  return 0;
}

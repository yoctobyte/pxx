/* crtl: <sys/file.h>, <sys/klog.h>, <sys/swap.h>, <sys/personality.h> --
 * four one-syscall headers, all found by attempting busybox for i386.
 *
 * ROW 2 IS THE ONE THAT MATTERS. flock is not fcntl record locking: the lock
 * belongs to the OPEN FILE DESCRIPTION, so two separate open()s of one file
 * conflict and two dup()s of one open do not. An implementation that mapped
 * flock onto fcntl would pass "lock succeeds" and fail exactly here, because
 * fcntl locks are per-PROCESS and the second lock in the same process would
 * silently succeed. -1/EWOULDBLOCK is the assertion.
 *
 * ROW 4 is PER_* -- the personality proper is the low byte and several names
 * carry FLAGS folded in on top (PER_SVR4 is not 0x0001). Writing the low byte
 * alone compiles and gives a different personality. Row 5 issues the call:
 * 0xffffffff is not a valid personality, so the kernel rejects the set and
 * returns the PREVIOUS value unchanged -- that is what makes it a query, and
 * an implementation that returned the NEW value would answer -1 here.
 *
 * ROW 3 IS NOT AN ORACLE ROW: glibc's <sys/klog.h> declares klogctl and no
 * constants at all, leaving every caller writing bare integers (busybox's
 * dmesg.c and klogd.c both do). The #else arm carries those same literals, so
 * the row checks crtl's names against the numbers busybox actually passes,
 * which is the thing that can be wrong. Rows 6 and 7 ARE behaviour: both calls
 * are refused for lack of privilege on an ordinary box, and both print 0 if
 * the syscall was never wired up at all -- ENOSYS is the failure they exist to
 * catch, and it is not spelled EPERM.
 *
 * Rows 1, 2, 4, 5, 6, 7 diffed against gcc/glibc.
 */
/* _GNU_SOURCE is for the ORACLE, not for us: crtl has no feature-test-macro
   machinery and shows every name unconditionally, but glibc hides LOCK_MAND
   and friends behind __USE_GNU, so without this the gcc side of row 1 does not
   compile and there is nothing to diff against. pxx ignores the define. */
#define _GNU_SOURCE

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/klog.h>
#include <sys/swap.h>
#include <sys/personality.h>

int main(void)
{
  char path[512];
  const char *dir;
  int fd, fd2, rc, blocked;
  int p0, p1, p2;

  /* The scratch file goes in the RUN'S directory, not the shared /tmp.
   * mkstemp already makes the NAME unique, so this is not about two runs
   * colliding on a filename -- it is about the DIRECTORY: a file written
   * outside $TESTMGR_TMP is one testmgr did not create and does not clean up,
   * and on a box where /tmp is small, read-only or not the tmpdir, this test
   * fails for a reason that has nothing to do with flock.
   * TESTMGR_TMP first: testmgr launches jobs through an environment allowlist
   * (PXX_/TESTMGR_/LC_/QEMU_), so $TESTTMP alone does not reach the job and
   * would silently fall back to the shared path. TESTTMP second, for
   * `make test TESTTMP=$(mktemp -d)`. The bare-run default keeps the old
   * behaviour byte-identical. */
  dir = getenv("TESTMGR_TMP");
  if (!dir) dir = getenv("TESTTMP");
  if (!dir) dir = "/tmp";
  snprintf(path, sizeof path, "%s/%s", dir, "pxx_flock_XXXXXX");

  /* LOCK_* reach us through <fcntl.h>, which is where glibc keeps them. */
  printf("1 %d %d %d %d %d %d\n", LOCK_SH, LOCK_EX, LOCK_NB, LOCK_UN,
         LOCK_MAND, LOCK_RW);

  fd = mkstemp(path);
  if (fd < 0) { printf("mkstemp failed\n"); return 1; }
  fd2 = open(path, O_RDWR);

  rc = flock(fd, LOCK_EX | LOCK_NB);
  errno = 0;
  blocked = (flock(fd2, LOCK_EX | LOCK_NB) == -1 && errno == EWOULDBLOCK);
  flock(fd, LOCK_UN);
  printf("2 %d %d %d\n", rc, blocked, flock(fd2, LOCK_EX | LOCK_NB));
  flock(fd2, LOCK_UN);
  close(fd2);
  close(fd);
  unlink(path);

#ifdef SYSLOG_ACTION_SIZE_BUFFER
  printf("3 %d %d %d %d\n", SYSLOG_ACTION_OPEN, SYSLOG_ACTION_READ,
         SYSLOG_ACTION_READ_ALL, SYSLOG_ACTION_SIZE_BUFFER);
#else
  printf("3 %d %d %d %d\n", 1, 2, 3, 10);
#endif

  printf("4 %d %d %d %d %d %d\n", PER_LINUX, PER_LINUX32, PER_MASK,
         PER_SVR4, PER_LINUX_32BIT, PER_LINUX32_3GB);

  /* Query, set, query, restore. 0xffffffff is the query because it is not a
     valid personality: the set fails and the OLD value comes back. */
  p0 = personality(0xffffffffUL);
  personality((unsigned long)(p0 | ADDR_NO_RANDOMIZE));
  p1 = personality(0xffffffffUL);
  personality((unsigned long)p0);
  p2 = personality(0xffffffffUL);
  printf("5 %d %d %d\n", p0 >= 0, (p1 & ADDR_NO_RANDOMIZE) != 0, p2 == p0);

  errno = 0;
  rc = klogctl(10, NULL, 0);   /* SYSLOG_ACTION_SIZE_BUFFER */
  printf("6 %d\n", rc >= 0 || (errno != ENOSYS && errno != 0));

  errno = 0;
  rc = swapoff("/pxx-no-such-swap-file");
  printf("7 %d\n", rc == -1 && errno != ENOSYS && errno != 0);

  printf("8 %d %d %d %d\n", SWAP_FLAG_PREFER, SWAP_FLAG_PRIO_MASK,
         SWAP_FLAG_PRIO_SHIFT, SWAP_FLAG_DISCARD);
  return 0;
}

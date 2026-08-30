/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: sys/time — libc-free gettimeofday/utimes for sqlite's unix VFS.
 * gettimeofday reads the PAL wall clock (clock_gettime CLOCK_REALTIME) into two
 * int64 slots and narrows them into struct timeval. utimes forwards the two
 * timestamps (sub-second precision dropped) to utimensat via the PAL.
 */

#include <sys/time.h>
#include <errno.h>

extern int __pxx_realtime(long long *sec, long long *usec);
extern int __pxx_utimes(const char *path, long long atimeSec, long long mtimeSec);

int gettimeofday(struct timeval *tv, void *tz) {
  long long sec, usec;
  int r = __pxx_realtime(&sec, &usec);
  if (tv) {
    tv->tv_sec = (long)sec;
    tv->tv_usec = (long)usec;
  }
  (void)tz;
  return r < 0 ? -1 : 0;
}

int utimes(const char *filename, const struct timeval times[2]) {
  long long atime = times ? (long long)times[0].tv_sec : 0;
  long long mtime = times ? (long long)times[1].tv_sec : 0;
  /* raw PAL convention -> C's -1 + errno, like every other veneer here */
  int rc = __pxx_utimes(filename, atime, mtime);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

/* No PAL syscall sets the clock, so this fails cleanly rather than pretending.
   Same contract as the ENOSYS stubs in unistd.c: -1 and ENOSYS, never a silent
   success. Replace with a real implementation the day the PAL grows the call —
   the signature is already the right one. */
int settimeofday(const struct timeval *tv, const struct timezone *tz)
{
  (void)tv; (void)tz;
  errno = ENOSYS;
  return -1;
}

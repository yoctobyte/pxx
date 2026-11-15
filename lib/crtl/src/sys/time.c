/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: sys/time — libc-free gettimeofday/utimes for sqlite's unix VFS.
 * gettimeofday reads the PAL wall clock (clock_gettime CLOCK_REALTIME) into two
 * int64 slots and narrows them into struct timeval. utimes forwards the two
 * timestamps (sub-second precision dropped) to utimensat via the PAL.
 */

#include <sys/time.h>
#include <sys/syscall.h>
#include <unistd.h>
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

/* setitimer/getitimer: the kernel's own call, where the target has its number
   (the OS translators take the Linux number as they take the PAL's). A target
   without it (the ESP builds) says ENOSYS rather than pretending to arm. */
int setitimer(int which, const struct itimerval *nv, struct itimerval *ov) {
#ifdef SYS_setitimer
  return (int)syscall(SYS_setitimer, (long)which, (long)nv, (long)ov);
#else
  (void)which; (void)nv; (void)ov;
  errno = ENOSYS;
  return -1;
#endif
}

int getitimer(int which, struct itimerval *cur) {
#ifdef SYS_getitimer
  return (int)syscall(SYS_getitimer, (long)which, (long)cur);
#else
  (void)which; (void)cur;
  errno = ENOSYS;
  return -1;
#endif
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

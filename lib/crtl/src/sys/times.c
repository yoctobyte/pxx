/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: times(2).
 *
 * Needed by busybox's ash for its `times' builtin (shell/ash.c:14189).
 *
 * Unlike almost everything else in crtl, the success value here is DATA, not a
 * status: times() returns ticks since an arbitrary point in the past, so 0 is a
 * perfectly ordinary result and only a negative is an error. Testing it for
 * `== 0' would report failure at whatever moment the kernel's counter happened
 * to be zero.
 */
#include <sys/times.h>
#include <errno.h>

long long __pxx_times(void *buf);

clock_t times(struct tms *buf) {
  long long r = __pxx_times((void *)buf);
  if (r < 0) { errno = (int)-r; return (clock_t)-1; }
  return (clock_t)r;
}

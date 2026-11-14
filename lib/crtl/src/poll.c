/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: poll. Was DECLARED in poll.h with no body, so every caller bound
 * to libc.so.6 through the unresolved-extern fallback and the binary silently
 * stopped being self-contained (tools/crtl_decl_probe.sh). A missing body is
 * worse than a missing declaration precisely because the program still WORKS on
 * a glibc host — the values are right and only the linkage is wrong.
 *
 * Unlike ioctl, this one genuinely needed a new PAL entry. PalPoll existed but
 * is PER-HANDLE, and a set poll cannot be built by looping it: the whole point
 * is to block on the entire set at once, and a loop either blocks on the first
 * descriptor or busy-spins the rest. PalPollSet takes the array.
 *
 * Nothing is repacked on the way down. C's `struct pollfd` is int fd then two
 * shorts, which is exactly the 8-byte record the PAL hands the kernel, so the
 * caller's own array is what ppoll writes revents into.
 *
 * ON ESP: the IDF backend routes to lwip_poll (sockets work) and the bare
 * profile answers PAL_ERR_UNSUPPORTED, surfacing here as -1/errno — the
 * deliberate Track S failure mode, a refusal rather than a wrong answer.
 */

#include <poll.h>
#include <errno.h>
#include <time.h>
#include <unistd.h>
#include <sys/syscall.h>

extern int __pxx_poll(void *fds, int nfds, int timeout);

int poll(struct pollfd *fds, nfds_t nfds, int timeout) {
  int r = __pxx_poll((void *)fds, (int)nfds, timeout);
  if (r < 0) { errno = -r; return -1; }
  return r;
}

/* ppoll(2): a timespec timeout and a signal mask held for the wait. The
   kernel's own call where there is one (it writes back the time left, so it
   gets a copy); elsewhere poll's millisecond timeout, without a mask. */
int ppoll(struct pollfd *fds, nfds_t nfds, const struct timespec *timeout, const void *sigmask) {
#if defined(SYS_ppoll)
  struct timespec ts, *tp = 0;
  if (timeout) {
    ts = *timeout;
    tp = &ts;
  }
  return (int)syscall(SYS_ppoll, (long)fds, (long)nfds, (long)tp, (long)sigmask, 8L /* the kernel's sigset: _NSIG/8 */);
#else
  long ms = -1;
  if (sigmask) { errno = ENOSYS; return -1; }
  if (timeout) ms = (long)timeout->tv_sec * 1000 + timeout->tv_nsec / 1000000;
  return poll(fds, nfds, (int)ms);
#endif
}

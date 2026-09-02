/* crtl: select(2) and the FD_* macros.
 *
 * busybox's telnetd stopped a 400-translation-unit build with `call to
 * undeclared function: FD_ZERO'; httpd, nc, microcom and the udhcp daemons sit
 * in the same loop.
 *
 * Nothing here asserts on the TIMEOUT after the call. Linux's select writes
 * the remaining time back into it and pselect6 does not, so the targets split
 * on that -- see lib/crtl/src/sys/select.c. A row pinning the updated value
 * would pass on x86-64 and i386 and fail on aarch64 for a reason that is not a
 * bug, which is the row that gets deleted rather than believed.
 */
#include <stdio.h>
#include <sys/select.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>

int main(void)
{
  int fds[2];
  fd_set r;
  fd_set w;
  struct timeval tv;
  int n;
  int i;
  int bits;

  /* The macros first, on their own, with no kernel involved. A wrong shift
     width here watches the wrong descriptor and every select row below still
     passes, because fd 3 and fd 67 both land in the set when the shift wraps. */
  FD_ZERO(&r);
  bits = 0;
  for (i = 0; i < FD_SETSIZE; i++) if (FD_ISSET(i, &r)) bits++;
  printf("1 %d %d\n", bits, FD_SETSIZE);

  FD_SET(3, &r);
  FD_SET(67, &r);
  FD_SET(1023, &r);
  bits = 0;
  for (i = 0; i < FD_SETSIZE; i++) if (FD_ISSET(i, &r)) bits++;
  printf("2 %d %d %d %d %d\n", bits, FD_ISSET(3, &r) != 0, FD_ISSET(67, &r) != 0,
         FD_ISSET(1023, &r) != 0, FD_ISSET(0, &r) != 0);

  FD_CLR(67, &r);
  bits = 0;
  for (i = 0; i < FD_SETSIZE; i++) if (FD_ISSET(i, &r)) bits++;
  printf("3 %d %d\n", bits, FD_ISSET(67, &r) != 0);

  if (pipe(fds) != 0) { printf("pipe failed\n"); return 1; }

  /* Nothing written yet: an immediate timeout must report nothing ready, and
     must NOT report the read end ready. Zero returned with the set left dirty
     is the failure this row is aimed at. */
  FD_ZERO(&r); FD_SET(fds[0], &r);
  tv.tv_sec = 0; tv.tv_usec = 0;
  n = select(fds[0] + 1, &r, 0, 0, &tv);
  printf("4 %d %d\n", n, FD_ISSET(fds[0], &r) != 0);

  /* The write end of a fresh pipe is always writable. */
  FD_ZERO(&w); FD_SET(fds[1], &w);
  tv.tv_sec = 0; tv.tv_usec = 0;
  n = select(fds[1] + 1, 0, &w, 0, &tv);
  printf("5 %d %d\n", n, FD_ISSET(fds[1], &w) != 0);

  if (write(fds[1], "x", 1) != 1) { printf("write failed\n"); return 1; }

  /* Now readable. A 1-second timeout rather than NULL so a broken
     implementation fails as a wrong answer instead of as a hung test. */
  FD_ZERO(&r); FD_SET(fds[0], &r);
  tv.tv_sec = 1; tv.tv_usec = 0;
  n = select(fds[0] + 1, &r, 0, 0, &tv);
  printf("6 %d %d\n", n, FD_ISSET(fds[0], &r) != 0);

  /* Both directions in one call, with the read end still holding its byte:
     nfds must cover the HIGHER fd, and a select that only ever looks at word 0
     of the bitmap passes every row above and fails here once fds go past 63. */
  FD_ZERO(&r); FD_SET(fds[0], &r);
  FD_ZERO(&w); FD_SET(fds[1], &w);
  tv.tv_sec = 1; tv.tv_usec = 0;
  n = select((fds[0] > fds[1] ? fds[0] : fds[1]) + 1, &r, &w, 0, &tv);
  printf("7 %d %d %d\n", n, FD_ISSET(fds[0], &r) != 0, FD_ISSET(fds[1], &w) != 0);

  /* nfds = 0 with a zero timeout is the portable sleep-for-nothing, and the
     one call in this file that must return 0 rather than -1. */
  tv.tv_sec = 0; tv.tv_usec = 0;
  n = select(0, 0, 0, 0, &tv);
  printf("8 %d\n", n);

  /* A bad descriptor in the set is EBADF, not a hang and not a 0. */
  close(fds[0]); close(fds[1]);
  FD_ZERO(&r); FD_SET(fds[0], &r);
  tv.tv_sec = 0; tv.tv_usec = 0;
  errno = 0;
  n = select(fds[0] + 1, &r, 0, 0, &tv);
  printf("9 %d %d\n", n, errno == EBADF);
  return 0;
}

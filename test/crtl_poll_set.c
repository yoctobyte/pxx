/* SPDX-License-Identifier: Zlib */
/*
 * poll() over a SET, which is the part that could not be faked.
 *
 * poll was declared in poll.h with no body, so every caller bound to libc.so.6
 * through the unresolved-extern fallback: correct output on a glibc host, and a
 * binary that had silently stopped being self-contained. So the linkage is
 * asserted alongside the values (see lib-test — `readelf -d` must show no
 * DT_NEEDED), not just the printout.
 *
 * The set cases are the ones with teeth. A per-handle poll in a loop passes
 * "one fd is ready" and cannot pass "block on two and report which": it either
 * blocks on the first descriptor or busy-spins the rest. Hence the second and
 * third checks — write to the SECOND pipe and require exactly it, then both.
 *
 * Every expectation here is gcc's own output for this file, and it also matches
 * on i386, arm32 and aarch64 under qemu.
 */
#include <poll.h>
#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>

int main(void) {
  int p[2], q[2];
  struct pollfd fds[2];
  int r;

  if (pipe(p) != 0 || pipe(q) != 0) { printf("pipe failed\n"); return 1; }

  /* nothing written yet: a set of two must time out, not report ready */
  fds[0].fd = p[0]; fds[0].events = POLLIN; fds[0].revents = 0;
  fds[1].fd = q[0]; fds[1].events = POLLIN; fds[1].revents = 0;
  r = poll(fds, 2, 50);
  printf("timeout r=%d rev0=%d rev1=%d\n", r, fds[0].revents, fds[1].revents);

  /* write to the SECOND one: the set must report exactly that one ready */
  write(q[1], "x", 1);
  fds[0].revents = 0; fds[1].revents = 0;
  r = poll(fds, 2, 1000);
  printf("ready r=%d rev0=%d rev1in=%d\n", r, fds[0].revents,
         (fds[1].revents & POLLIN) != 0);

  /* both ready */
  write(p[1], "y", 1);
  fds[0].revents = 0; fds[1].revents = 0;
  r = poll(fds, 2, 1000);
  printf("both r=%d in0=%d in1=%d\n", r, (fds[0].revents & POLLIN) != 0,
         (fds[1].revents & POLLIN) != 0);

  /* a closed/invalid fd must come back POLLNVAL, not hang */
  fds[0].fd = 9999; fds[0].events = POLLIN; fds[0].revents = 0;
  r = poll(fds, 1, 100);
  printf("nval r=%d nval=%d\n", r, (fds[0].revents & POLLNVAL) != 0);

  /* nfds=0 is a plain sleep that returns 0 */
  r = poll(fds, 0, 10);
  printf("zero r=%d\n", r);
  return 0;
}

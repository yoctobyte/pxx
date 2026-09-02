/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/select.h> -- fd_set, the four FD_* macros, and select(2).
 *
 * Brought in by busybox: telnetd, httpd, nc, microcom and the udhcp daemons all
 * sit in a select loop, and `call to undeclared function: FD_ZERO' was where a
 * 400-translation-unit build stopped.
 *
 * fd_set is glibc's, which is the kernel's: FD_SETSIZE bits in an array of
 * `long', so the array is 16 longs on a 64-bit target and 32 on a 32-bit one
 * and the BIT NUMBERING is identical either way. That is the property that
 * matters -- the kernel reads this memory, so a differently-shaped word here
 * does not produce a slower program, it produces one that watches the wrong
 * descriptors.
 *
 * NOTHING HERE BOUNDS-CHECKS THE FD, exactly as glibc does not. FD_SET(fd, s)
 * with fd >= FD_SETSIZE writes past the end of the object, and every real
 * select loop is one dup2 away from that. It is left alone because a check
 * that silently dropped the fd would turn a memory bug into a hang, which is
 * strictly harder to find; callers that can exceed 1024 fds want poll(2),
 * which crtl already has in <poll.h>.
 */
#ifndef _CRTL_SYS_SELECT_H
#define _CRTL_SYS_SELECT_H

#include <sys/types.h>
#include <sys/time.h>

#define FD_SETSIZE 1024

#define __NFDBITS (8 * (int)sizeof(long))

typedef struct {
  long fds_bits[FD_SETSIZE / (8 * (int)sizeof(long))];
} fd_set;

/* The casts to (unsigned) on the shift keep the bit at 1L, not 1: on a 64-bit
   target a bit index of 32..63 shifted into an `int' 1 is undefined and in
   practice wraps to bit 0, which watches fd 0 instead of fd 40. */
#define FD_ZERO(s)                                                          \
  do {                                                                      \
    int __i;                                                                \
    fd_set *__s = (s);                                                      \
    for (__i = 0; __i < (int)(FD_SETSIZE / (8 * (int)sizeof(long))); __i++) \
      __s->fds_bits[__i] = 0L;                                              \
  } while (0)

#define FD_SET(d, s)   ((s)->fds_bits[(d) / __NFDBITS] |=  (1L << ((d) % __NFDBITS)))
#define FD_CLR(d, s)   ((s)->fds_bits[(d) / __NFDBITS] &= ~(1L << ((d) % __NFDBITS)))
#define FD_ISSET(d, s) (((s)->fds_bits[(d) / __NFDBITS] & (1L << ((d) % __NFDBITS))) != 0L)

/* select(2). `timeout' is IN-OUT on Linux -- the kernel writes back the time
   remaining -- and that is preserved on the targets whose kernel offers a
   select syscall. See src/sys/select.c: the targets that only have pselect6
   cannot preserve it, and the file says which they are rather than leaving a
   caller to discover it from a loop that never terminates. */
int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds,
           struct timeval *timeout);

#endif

/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_RANDOM_H
#define PXX_CRTL_SYS_RANDOM_H 1

/* <sys/random.h> -- getrandom(2).

   THE FLAGS LIVE IN <linux/random.h> AND ARE NOT REPEATED HERE. glibc splits
   them the same way, and busybox's miscutils/seedrng.c includes both headers
   because it needs both halves -- RNDADDENTROPY from there, getrandom() from
   here. A second copy of GRND_INSECURE would be a second thing to keep right.

   WHY IT IS A SYSCALL AND NOT A PAL ENTRY: the kernel's CSPRNG is the point.
   Reading /dev/urandom is not the same call -- it needs an fd, it can fail
   inside a chroot with no /dev, and it cannot express GRND_NONBLOCK. seedrng
   asks specifically for the non-blocking and the insecure behaviours and
   branches on which it got, so a substitute that "also returns random bytes"
   would be answering a different question.

   PARTIAL READS ARE THE CALLER'S PROBLEM, DELIBERATELY, and that is the
   contract glibc has: kernels before 5.18 could return a short count for a
   request over 256 bytes, so the return value is a LENGTH and not a status.
   seedrng loops on it. A wrapper that looped here would hide GRND_NONBLOCK's
   whole purpose. */

#include <stddef.h>
#include <sys/types.h>
#include <linux/random.h>

ssize_t getrandom(void *buf, size_t buflen, unsigned int flags);

#endif /* PXX_CRTL_SYS_RANDOM_H */

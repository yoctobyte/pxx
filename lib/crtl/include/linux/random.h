/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LINUX_RANDOM_H
#define PXX_CRTL_LINUX_RANDOM_H 1

/* <linux/random.h> -- the /dev/random ioctls and the GRND_ flags.

   TWO HEADERS, ONE SUBJECT, AND BOTH ARE NEEDED. busybox's miscutils/seedrng.c
   includes this AND <sys/random.h>: the first for RNDADDENTROPY and struct
   rand_pool_info, the second for getrandom(). Neither is a superset of the
   other, and the x86-64 run reported only the second while i386 stopped at the
   first -- so a list built from first refusals named one of them and the other
   was invisible until that one was supplied.

   THE IOCTL NUMBERS TRAVEL TO THE KERNEL. RNDADDENTROPY credits the entropy
   pool; a wrong command number on an open /dev/urandom is a different request
   on the same fd, not a compile error. Every number here is diffed against the
   kernel's own linux/random.h.

   GRND_INSECURE is defined here even though seedrng.c defines it itself under
   #ifndef -- that fallback exists for old distro headers, and a header that
   makes a program take its compatibility path is a header that is missing
   something. */

#include <stdint.h>
#include <sys/ioctl.h>

/* Get the entropy count of the input pool, in bits. */
#define RNDGETENTCNT    _IOR( 'R', 0x00, int )
/* Add to (or subtract from) the entropy count, without adding data. */
#define RNDADDTOENTCNT  _IOW( 'R', 0x01, int )
/* Historical; the kernel no longer implements it. */
#define RNDGETPOOL      _IOR( 'R', 0x02, int [2] )
/* Add data AND credit it: the argument is a struct rand_pool_info. */
#define RNDADDENTROPY   _IOW( 'R', 0x03, int [2] )
/* Zero the entropy count. The pool data itself is untouched. */
#define RNDZAPENTCNT    _IO( 'R', 0x04 )
/* Zero the pool and its count, and reload from the hardware if there is one. */
#define RNDCLEARPOOL    _IO( 'R', 0x06 )
/* Reseed the CRNG. */
#define RNDRESEEDCRNG   _IO( 'R', 0x07 )

/* The argument to RNDADDENTROPY. `buf' is a FLEXIBLE ARRAY: callers allocate
   the header plus buf_size bytes and the kernel reads exactly that many, so
   sizeof(struct rand_pool_info) is the header alone and is not what you pass
   as a length. busybox allocates it that way. */
struct rand_pool_info {
  int      entropy_count;
  int      buf_size;
  uint32_t buf[];
};

/* Flags for getrandom(2), declared in <sys/random.h>. */
#define GRND_NONBLOCK   0x0001  /* fail with EAGAIN rather than block */
#define GRND_RANDOM     0x0002  /* draw from the blocking pool (legacy) */
#define GRND_INSECURE   0x0004  /* return possibly-unseeded bytes, never block */

#endif /* PXX_CRTL_LINUX_RANDOM_H */

/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/sysmacros.h> -- major()/minor()/makedev().
 *
 * Macros only, and the ENCODING is the whole content: Linux's dev_t is not
 * "major in the top half, minor in the bottom". It is the split glibc calls
 * the "new" encoding, where the minor is 20 bits in two pieces and the major
 * is 12 bits in two pieces:
 *
 *   bits 63..44  major, high 20        bits 43..20  minor, high 24
 *   bits 19..12  major, low 12         bits  7..0   minor, low 8
 *
 * so major() and minor() each read TWO fields and OR them. A naive
 * `(dev >> 8) & 0xfff` agrees with the real thing for every device on a
 * typical desktop -- which is exactly why getting it wrong is expensive: it
 * diverges only on the large minors (loop devices past 255, /dev/pts past
 * 255) that a test box does not have. The values below are transcribed from
 * glibc's own sysmacros.h and asserted row for row against it in
 * test/c_sysmacros_dev.c.
 *
 * The arithmetic is done in `unsigned long long` regardless of dev_t's width
 * so the shifts above 31 are defined. On the 32-bit targets dev_t is 32 bits
 * (see <sys/types.h>) and the two high fields simply cannot be represented --
 * the same truncation our own struct stat has, not something this header
 * introduces.
 */
#ifndef _CRTL_SYS_SYSMACROS_H
#define _CRTL_SYS_SYSMACROS_H

#include <sys/types.h>

#define major(dev) \
  ((unsigned int)((((unsigned long long)(dev)) & 0x00000000000fff00ULL) >> 8) | \
   (unsigned int)((((unsigned long long)(dev)) & 0xfffff00000000000ULL) >> 32))

#define minor(dev) \
  ((unsigned int)((((unsigned long long)(dev)) & 0x00000000000000ffULL)) | \
   (unsigned int)((((unsigned long long)(dev)) & 0x00000ffffff00000ULL) >> 12))

#define makedev(maj, min) \
  ((dev_t)((((unsigned long long)((maj) & 0x00000fffU)) << 8) | \
           (((unsigned long long)((maj) & 0xfffff000U)) << 32) | \
           (((unsigned long long)((min) & 0x000000ffU))) | \
           (((unsigned long long)((min) & 0xffffff00U)) << 12)))

#define gnu_dev_major(dev)        major(dev)
#define gnu_dev_minor(dev)        minor(dev)
#define gnu_dev_makedev(maj, min) makedev(maj, min)

#endif

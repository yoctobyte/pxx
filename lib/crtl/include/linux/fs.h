/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/fs.h> -- the block-device and filesystem ioctls.
 *
 * A PARTIAL SHADOW OF A KERNEL UAPI HEADER, and the second one crtl carries on
 * purpose (<asm/swab.h> is the first, and that one exists to keep the host's
 * x86 inline asm OUT). The general rule stated in <net/ethernet.h> still
 * holds -- UAPI is the kernel's to ship, not crtl's to reproduce -- but it has
 * an edge the rule did not anticipate: a CROSS target has no host tree to read
 * at all, so "not ours to shadow" becomes "nobody's", and six busybox
 * translation units stop at `#include <linux/fs.h>' with nothing to fall back
 * on.
 *
 * So: the ioctls the corpus actually issues, every one of them #ifndef-guarded
 * so that including the REAL linux/fs.h alongside this file stays legal and
 * cannot double-define. This is deliberately NOT a copy of the kernel header --
 * no superblock flags, no struct file_clone_range, no mount API. Adding a name
 * here is cheap; adding one nobody calls is how a shadow becomes a fork.
 *
 * BLKGETSIZE64 IS SPELLED WITH size_t ON PURPOSE, which makes its ioctl number
 * DIFFER between 32- and 64-bit userspace (0x80041272 against 0x80081272).
 * That is the kernel header's own spelling and the kernel accepts both; a
 * "fix" to uint64_t here would send 64-bit userspace a number nothing answers.
 *
 * EVERY VALUE IS DIFFED AGAINST THE HOST'S OWN linux/fs.h by
 * test/c_crtl_linux_fs_ioctls.c, which is the only instrument that can catch a
 * transposed ioctl number: a wrong _IO(0x12, n) does not fail to compile, it
 * issues a DIFFERENT ioctl -- BLKRRPART instead of BLKGETSIZE64 rereads the
 * partition table of the disk you asked the size of.
 *
 * Found attempting busybox on i386: blkdiscard, blockdev, fsfreeze, fstrim,
 * mkfs_ext2 and partprobe.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_LINUX_FS_H
#define _CRTL_LINUX_FS_H

#include <sys/ioctl.h>
#include <stddef.h>
#include <stdint.h>

/* FITRIM's argument. The kernel spells these __u64; they are 64-bit on every
   target, including the 32-bit ones, which is the whole reason it is spelled
   out rather than left as `unsigned long'. */
#ifndef _CRTL_HAVE_FSTRIM_RANGE
#define _CRTL_HAVE_FSTRIM_RANGE 1
struct fstrim_range {
  uint64_t start;
  uint64_t len;
  uint64_t minlen;
};
#endif

/* Block-device ioctls: type 0x12. */
#ifndef BLKROSET
#define BLKROSET          _IO(0x12, 93)
#endif
#ifndef BLKROGET
#define BLKROGET          _IO(0x12, 94)
#endif
#ifndef BLKRRPART
#define BLKRRPART         _IO(0x12, 95)
#endif
#ifndef BLKGETSIZE
#define BLKGETSIZE        _IO(0x12, 96)
#endif
#ifndef BLKFLSBUF
#define BLKFLSBUF         _IO(0x12, 97)
#endif
#ifndef BLKRASET
#define BLKRASET          _IO(0x12, 98)
#endif
#ifndef BLKRAGET
#define BLKRAGET          _IO(0x12, 99)
#endif
#ifndef BLKFRASET
#define BLKFRASET         _IO(0x12, 100)
#endif
#ifndef BLKFRAGET
#define BLKFRAGET         _IO(0x12, 101)
#endif
#ifndef BLKSECTSET
#define BLKSECTSET        _IO(0x12, 102)
#endif
#ifndef BLKSECTGET
#define BLKSECTGET        _IO(0x12, 103)
#endif
#ifndef BLKSSZGET
#define BLKSSZGET         _IO(0x12, 104)
#endif
#ifndef BLKBSZGET
#define BLKBSZGET         _IOR(0x12, 112, size_t)
#endif
#ifndef BLKBSZSET
#define BLKBSZSET         _IOW(0x12, 113, size_t)
#endif
#ifndef BLKGETSIZE64
#define BLKGETSIZE64      _IOR(0x12, 114, size_t)
#endif
#ifndef BLKDISCARD
#define BLKDISCARD        _IO(0x12, 119)
#endif
#ifndef BLKIOMIN
#define BLKIOMIN          _IO(0x12, 120)
#endif
#ifndef BLKIOOPT
#define BLKIOOPT          _IO(0x12, 121)
#endif
#ifndef BLKALIGNOFF
#define BLKALIGNOFF       _IO(0x12, 122)
#endif
#ifndef BLKPBSZGET
#define BLKPBSZGET        _IO(0x12, 123)
#endif
#ifndef BLKDISCARDZEROES
#define BLKDISCARDZEROES  _IO(0x12, 124)
#endif
#ifndef BLKSECDISCARD
#define BLKSECDISCARD     _IO(0x12, 125)
#endif
#ifndef BLKROTATIONAL
#define BLKROTATIONAL     _IO(0x12, 126)
#endif
#ifndef BLKZEROOUT
#define BLKZEROOUT        _IO(0x12, 127)
#endif

/* Filesystem ioctls. FIBMAP/FIGETBSZ are type 0; the freeze/trim trio is 'X'. */
#ifndef FIBMAP
#define FIBMAP    _IO(0x00, 1)
#endif
#ifndef FIGETBSZ
#define FIGETBSZ  _IO(0x00, 2)
#endif
#ifndef FIFREEZE
#define FIFREEZE  _IOWR('X', 119, int)
#endif
#ifndef FITHAW
#define FITHAW    _IOWR('X', 120, int)
#endif
#ifndef FITRIM
#define FITRIM    _IOWR('X', 121, struct fstrim_range)
#endif

#endif

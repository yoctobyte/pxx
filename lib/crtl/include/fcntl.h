/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_FCNTL_H
#define PXX_CRTL_FCNTL_H 1

/* Minimal fcntl surface for sqlite's unix VFS (file open flags + advisory
   locking). Declarations only; unused with a `:memory:` database.

   THE ORIGINAL NOTE HERE SAID THE FLAG VALUES ARE "identical across the pxx
   cross targets", AND THAT IS TRUE ONLY OF THE TEN IT WAS WRITTEN ABOUT.
   O_DIRECTORY, O_NOFOLLOW, O_DIRECT and O_LARGEFILE are the four open() flags
   Linux does NOT define uniformly: arm and arm64 override asm-generic and
   effectively swap O_DIRECTORY with O_DIRECT. lib/rtl/platform.pas already
   carries the same split for PAL_OPEN_DIRECTORY, with the measurement behind
   it -- on ARM the x86 value made a real directory return EINVAL *and* made a
   regular file open succeed where the flag should have rejected it, so it is
   wrong in both directions and neither shows up as a compile error.
   Source of the values: the kernel's own arch/{arm,arm64}/include/uapi/asm/
   fcntl.h against include/uapi/asm-generic/fcntl.h. */

#include <sys/types.h>

#define O_RDONLY   00000000
#define O_WRONLY   00000001
#define O_RDWR     00000002
#define O_ACCMODE  00000003
#define O_CREAT    00000100
#define O_EXCL     00000200
#define O_NOCTTY   00000400
#define O_TRUNC    00001000
#define O_APPEND   00002000
#define O_NONBLOCK 00004000
#define O_SYNC     04010000
#define O_DSYNC    00010000
#define O_CLOEXEC  02000000

/* Uniform on every target we build for. */
#define O_ASYNC    00020000
#define O_NOATIME  01000000
#define O_PATH     010000000
#define O_NDELAY   O_NONBLOCK   /* the historical spelling; same bit */
#define O_FSYNC    O_SYNC
#define O_RSYNC    O_SYNC

/* NOT uniform -- see the note at the top. arm and arm64 override asm-generic. */
#if defined(__arm__) || defined(__aarch64__)
#define O_DIRECTORY 00040000
#define O_NOFOLLOW  00100000
#define O_DIRECT    00200000
#define O_LARGEFILE 00400000
#define __O_TMPFILE 020000000
#else
#define O_DIRECT    00040000
#define O_LARGEFILE 00100000
#define O_DIRECTORY 00200000
#define O_NOFOLLOW  00400000
#define __O_TMPFILE 020000000
#endif
#define O_TMPFILE  (__O_TMPFILE | O_DIRECTORY)

/* O_LARGEFILE IS THE ONE VALUE HERE THAT DISAGREES WITH GLIBC ON PURPOSE.
   glibc defines it as 0 on a 64-bit userspace, because its off_t is already
   64-bit and the flag would be redundant; the KERNEL value is the one above on
   every target. crtl takes the kernel's, because crtl's callers reach the
   kernel directly through <sys/syscall.h> rather than through glibc's
   open(). A test comparing this name against gcc's view will differ on
   x86-64, and that difference is correct in both directions -- so
   test/c_crtl_header_constants.c asserts the kernel value and says why. */

/* fcntl commands */
#define F_DUPFD   0
#define F_GETFD   1
#define F_SETFD   2
#define F_GETFL   3
#define F_SETFL   4
#define F_GETLK   5
#define F_SETLK   6
#define F_SETLKW  7

#define FD_CLOEXEC 1

/* lock types */
#define F_RDLCK 0
#define F_WRLCK 1
#define F_UNLCK 2

struct flock {
  short  l_type;
  short  l_whence;
  off_t  l_start;
  off_t  l_len;
  int    l_pid;
};

extern int open(const char *path, int flags, ...);
extern int openat(int dirfd, const char *path, int flags, ...);
extern int creat(const char *path, mode_t mode);
extern int fcntl(int fd, int cmd, ...);


/* *at() family constants. These are Linux-ABI-wide, not per-arch: AT_FDCWD is
   -100 and the flag bits are fixed across every architecture, which is why
   they can sit here rather than in a per-target table the way syscall NUMBERS
   have to. busybox's touch/stat/chmod pass them. */
#define AT_FDCWD              (-100)
#define AT_SYMLINK_NOFOLLOW   0x100
#define AT_REMOVEDIR          0x200
#define AT_SYMLINK_FOLLOW     0x400
#define AT_EMPTY_PATH         0x1000

/* fallocate(2) modes. Only the two busybox names are here; the rest of the
   kernel's set is deliberately absent, because a constant that no call site
   passes is a promise this runtime has not been asked to keep. */
#define FALLOC_FL_KEEP_SIZE   0x01
#define FALLOC_FL_PUNCH_HOLE  0x02

/* flock(2) operations. THESE LIVE HERE AND NOT ONLY IN <sys/file.h> because
   glibc puts them here too (bits/fcntl-linux.h), so code that includes just
   <fcntl.h> and writes LOCK_EX compiles there and must compile here. They are
   NOT related to `struct flock' above: that is fcntl record locking, this is
   a whole-file advisory lock on the open file description, and on Linux the
   two do not see each other. <sys/file.h> includes this header rather than
   repeating the numbers -- one definition site. */
#define LOCK_SH    1   /* shared */
#define LOCK_EX    2   /* exclusive */
#define LOCK_NB    4   /* OR'd in with one of the above: fail rather than block */
#define LOCK_UN    8   /* release */
#define LOCK_MAND  32  /* a mandatory flock ... */
#define LOCK_READ  64  /* ... allowing concurrent reads */
#define LOCK_WRITE 128 /* ... allowing concurrent writes */
#define LOCK_RW    192 /* ... allowing both */

/* posix_fallocate(3) RETURNS THE ERROR NUMBER AND DOES NOT SET errno. That is
   not a quirk of this implementation; it is what POSIX specifies, and busybox
   writes `if ((errno = posix_fallocate(fd, ofs, len)) != 0)' precisely because
   of it. An implementation that returned -1 and set errno would make that line
   assign -1 to errno and report "Unknown error -1" for every failure -- and
   would look right in every diff.

   fallocate(2) is the Linux call underneath and keeps the ordinary -1/errno
   convention. Two functions, two conventions, one syscall; the divergence is
   the reason both are declared here rather than one being written in terms of
   the other at a call site. */
extern int posix_fallocate(int fd, off_t offset, off_t len);
extern int fallocate(int fd, int mode, off_t offset, off_t len);

#endif

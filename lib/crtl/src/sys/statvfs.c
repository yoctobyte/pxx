/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: statvfs(3) and fstatvfs(3), over statfs(2).
 *
 * THE ONLY INTERESTING PART IS THE MAPPING, so it is written out rather than
 * left to be read off the assignments:
 *
 *   f_bsize   <- f_bsize     f_files   <- f_files
 *   f_frsize  <- f_frsize    f_ffree   <- f_ffree
 *   f_blocks  <- f_blocks    f_favail  <- f_ffree   [see below]
 *   f_bfree   <- f_bfree     f_namemax <- f_namelen
 *   f_bavail  <- f_bavail    f_type    <- f_type
 *
 * f_favail HAS NO KERNEL SOURCE. POSIX asks for "free inodes available to an
 * unprivileged process"; Linux does not track it, so it is f_ffree -- which is
 * what glibc does, and the reason a caller cannot use f_ffree != f_favail to
 * detect a reserved inode pool.
 *
 * f_fsid IS TWO 32-BIT WORDS IN THE KERNEL AND ONE `unsigned long' HERE. Where
 * long is 64 bits both halves fit and are packed; where it is 32 they do not,
 * and the high word is dropped rather than shifted off the end of the type.
 * glibc shifts unconditionally, which is a no-op or worse at ILP32; dropping
 * is at least a defined answer, and f_fsid is documented as unspecified.
 *
 * ST_VALID IS STRIPPED FROM f_flag AND THAT IS NOT TIDYING. It is statfs's
 * internal marker for "the kernel filled f_flags in", not a mount option, so
 * leaving it in makes a program that PRINTS the flag set report a mount option
 * that does not exist -- and it is bit 0x0020, sitting in the middle of the
 * real ones. glibc masks it out for the same reason; measured 2026-09-02, that
 * mask is the only place statvfs("/") disagreed with glibc. <sys/statfs.h>
 * keeps ST_VALID for statfs callers, where it means something.
 *
 * WHAT IS NOT DONE: glibc re-reads /proc/mounts when ST_VALID is clear, to
 * recover the flags an old kernel did not report. Every kernel since 2.6.36
 * sets it, so that path is for kernels crtl does not target, and paying for it
 * would make a filesystem-statistics call open and parse a file. If ST_VALID
 * is clear here, f_flag is what the kernel said and nothing more.
 */
#include <sys/statvfs.h>
#include <sys/statfs.h>
#include <string.h>
#include <limits.h>

static void crtl_statfs_to_statvfs(const struct statfs *s, struct statvfs *v)
{
  memset(v, 0, sizeof *v);
  v->f_bsize   = (unsigned long)s->f_bsize;
  v->f_frsize  = (unsigned long)(s->f_frsize != 0 ? s->f_frsize : s->f_bsize);
  v->f_blocks  = (fsblkcnt_t)s->f_blocks;
  v->f_bfree   = (fsblkcnt_t)s->f_bfree;
  v->f_bavail  = (fsblkcnt_t)s->f_bavail;
  v->f_files   = (fsfilcnt_t)s->f_files;
  v->f_ffree   = (fsfilcnt_t)s->f_ffree;
  v->f_favail  = (fsfilcnt_t)s->f_ffree;   /* no kernel source -- see above */
  if (sizeof(unsigned long) >= 8)
    v->f_fsid = (unsigned long)(unsigned int)s->f_fsid.val[0]
              | ((unsigned long)(unsigned int)s->f_fsid.val[1] << 16 << 16);
  else
    v->f_fsid = (unsigned long)(unsigned int)s->f_fsid.val[0];
  v->f_flag    = (unsigned long)s->f_flags & ~(unsigned long)ST_VALID;
  v->f_namemax = (unsigned long)s->f_namelen;
  v->f_type    = (unsigned int)s->f_type;
}

int statvfs(const char *path, struct statvfs *buf)
{
  struct statfs s;

  if (statfs(path, &s) != 0)
    return -1;
  crtl_statfs_to_statvfs(&s, buf);
  return 0;
}

int fstatvfs(int fd, struct statvfs *buf)
{
  struct statfs s;

  if (fstatfs(fd, &s) != 0)
    return -1;
  crtl_statfs_to_statvfs(&s, buf);
  return 0;
}

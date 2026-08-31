/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: dirent — opendir/readdir/closedir over the PAL's getdents64.
 *
 * Real, not stubs. The PAL has exposed PalGetDents64 all along; an earlier
 * pass through this gap assumed it did not and was about to ship an ENOSYS
 * stub. Same lesson <sys/ioctl.h> already records in this tree: measure the
 * PAL before believing a scoping line that says an entry is missing.
 */

#include <dirent.h>
#include <fcntl.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

extern int __pxx_open(const char *path, int flags, int mode);
extern int __pxx_close(int fd);
extern long long __pxx_getdents64(int fd, void *buf, int len);
extern long long __pxx_seek(int fd, long long offset, int whence);

/* One syscall per 4 KB of directory, which is what glibc uses too. Smaller
   costs syscalls on big directories; larger wastes a page on the common tiny
   one. */
#define PXX_DIRBUF 4096

struct __pxx_dir {
  int  fd;
  int  used;            /* valid bytes in buf */
  int  pos;             /* read offset within buf */
  struct dirent cur;    /* what the last readdir returned; caller borrows it */
  char buf[PXX_DIRBUF];
};

/* The kernel record: u64 d_ino, s64 d_off, u16 d_reclen, u8 d_type, then the
   NUL-terminated name. Read the fields by OFFSET rather than by casting to a
   struct: the name is flexible, so a struct with a fixed name array would have
   the wrong sizeof and the wrong alignment expectations, and reading d_reclen
   through it is how a directory walk desynchronises. */
#define KD_INO(p)    (*(unsigned long long *)((p) + 0))
#define KD_OFF(p)    (*(long long *)((p) + 8))
#define KD_RECLEN(p) (*(unsigned short *)((p) + 16))
#define KD_TYPE(p)   (*(unsigned char *)((p) + 18))
#define KD_NAME(p)   ((const char *)((p) + 19))

/* Refill from the kernel. Returns 1 on data, 0 at end of directory, -1 on
   error with errno set. */
static int pxx_dir_fill(DIR *d)
{
  long long got = __pxx_getdents64(d->fd, d->buf, PXX_DIRBUF);
  if (got < 0) { errno = (int)-got; return -1; }
  d->used = (int)got;
  d->pos = 0;
  return got == 0 ? 0 : 1;
}

/* No O_DIRECTORY, deliberately: its value is 0200000 on x86 and 040000 on the
   asm-generic targets (aarch64, arm32, riscv, xtensa), so spelling it here
   would need a per-target constant table for a flag whose whole job is to move
   an error earlier. fdopendir reads the first chunk eagerly instead, and
   getdents64 on a non-directory fd fails with ENOTDIR — the same errno at the
   same call, from the syscall that had to happen anyway rather than from a
   constant we would have to keep right on five targets.

   Measured against glibc: without the eager read, opendir("/etc/hostname")
   SUCCEEDED here and failed with ENOTDIR there. That divergence is the whole
   reason the prefill is not lazy. */
DIR *opendir(const char *name)
{
  int fd = __pxx_open(name, O_RDONLY, 0);
  if (fd < 0) { errno = -fd; return 0; }
  { DIR *d = fdopendir(fd);
    if (!d) { int e = errno; __pxx_close(fd); errno = e; return 0; }
    return d; }
}

DIR *fdopendir(int fd)
{
  DIR *d = (DIR *)malloc(sizeof(DIR));
  if (!d) { errno = ENOMEM; return 0; }
  d->fd = fd;
  d->used = 0;
  d->pos = 0;
  if (pxx_dir_fill(d) < 0) { int e = errno; free(d); errno = e; return 0; }
  return d;
}

struct dirent *readdir(DIR *d)
{
  const char *rec;
  const char *nm;
  size_t n;

  if (!d) { errno = EBADF; return 0; }

  if (d->pos >= d->used) {
    int r = pxx_dir_fill(d);
    if (r <= 0) return 0;   /* r==0: end of directory, errno UNTOUCHED */
  }

  rec = d->buf + d->pos;
  /* A zero or over-long reclen would loop forever or walk off the buffer.
     The kernel does not produce either; refusing them costs one compare and
     turns a corrupt record into a clean error instead of a hang. */
  if (KD_RECLEN(rec) < 19 || d->pos + (int)KD_RECLEN(rec) > d->used) {
    errno = EIO;
    return 0;
  }
  d->pos += KD_RECLEN(rec);

  d->cur.d_ino    = KD_INO(rec);
  d->cur.d_off    = KD_OFF(rec);
  d->cur.d_reclen = KD_RECLEN(rec);
  d->cur.d_type   = KD_TYPE(rec);

  nm = KD_NAME(rec);
  n = strnlen(nm, sizeof(d->cur.d_name) - 1);
  memcpy(d->cur.d_name, nm, n);
  d->cur.d_name[n] = 0;
  return &d->cur;
}

/* readdir returns NULL for BOTH end-of-directory and error, so a caller that
   needs to tell them apart clears errno first and checks it after — which only
   works because the end-of-directory path above leaves errno alone. */

int closedir(DIR *d)
{
  int fd, rc;
  if (!d) { errno = EBADF; return -1; }
  fd = d->fd;
  free(d);
  rc = __pxx_close(fd);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

void rewinddir(DIR *d)
{
  if (!d) return;
  __pxx_seek(d->fd, 0, 0 /* SEEK_SET */);
  d->used = 0;
  d->pos = 0;
  /* Deliberately NOT refilling here: rewinddir returns void, so a refill error
     would have nowhere to go. The next readdir refills and reports it. */
}

int dirfd(DIR *d)
{
  if (!d) { errno = EBADF; return -1; }
  return d->fd;
}

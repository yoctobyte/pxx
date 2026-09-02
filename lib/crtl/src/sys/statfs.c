/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: statfs(2) and fstatfs(2).
 *
 * OVER THE RAW SYSCALL BRIDGE, for the reason src/sys/sysinfo.c states at
 * length: the struct these fill is the kernel's own, field for field, and a
 * PalStatFs would be a Linux layout wearing a portable name. busybox's df,
 * mount and switch_root are what brought them in.
 *
 * THE LAYOUT QUESTION, SETTLED BY MEASUREMENT (2026-09-02). <sys/statfs.h>
 * used to carry a note saying its `struct statfs' was "the 64-bit kernel's"
 * and was "the WRONG one" on 32-bit targets. That was wrong, and the note has
 * been replaced: the declaration is written in `long' and `unsigned long', so
 * it tracks the target's word size, which is exactly how the kernel defines
 * __statfs_word. A layout probe (sizeof plus every offsetof) compiled by gcc
 * and by pxx agrees on both widths:
 *
 *     x86-64   size 120, f_blocks at 16, f_namelen at 64
 *     i386     size  64, f_blocks at  8, f_namelen at 36
 *
 * gcc and pxx print byte-identical output on x86-64, and pxx's i386 output
 * matches `gcc -m32'. So on x86-64, i386 and aarch64 the kernel writes
 * straight into the caller's struct and there is no conversion here at all.
 *
 * riscv32 IS different, and not because of the struct. asm-generic slot 43 is
 * __NR3264_statfs, which on a 32-bit target is sys_statfs64 -- there is no
 * plain statfs to call. So that arm calls statfs64, into the kernel's OWN
 * statfs64 shape, and narrows. Narrowing can lose, so it reports EOVERFLOW
 * rather than returning a plausible small number, which is what glibc does on
 * the same path and is the difference between "this filesystem is 2TB" and
 * "this filesystem is 200GB".
 *
 * TWO ERROR CONVENTIONS LIVE IN THIS RUNTIME AND THEY LOOK THE SAME AT THE
 * CALL SITE. __pxx_ioctl and the other PAL entries hand back -errno, so a
 * caller writes `if (rc < 0) { errno = -rc; return -1; }' -- that is what
 * src/termios.c does. syscall() in src/unistd.c has ALREADY done that
 * translation and returns -1 with errno set. Applying the PAL idiom to it
 * therefore overwrites the real errno with 1 (EPERM), and every failure
 * reports "operation not permitted". Measured here 2026-09-02: statfs on a
 * nonexistent path gave EPERM where glibc gave ENOENT, and it was only the
 * error ROW of the test that showed it -- rows 1 through 6 all passed.
 */
#include <sys/statfs.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>

#if defined(__riscv) && (__riscv_xlen == 32)

/* The kernel's struct statfs64 as 32-bit targets see it (asm-generic/statfs.h).
   Declared HERE and not in the header: nothing outside this file may name it,
   because a public struct statfs64 is a promise to keep a second ABI, and the
   one call that needs it is the one below. It is packed to 4-byte alignment in
   the kernel's own definition -- the __u64 members would otherwise be 8-aligned
   and every field from f_blocks on would move. */
struct __pxx_kstatfs64 {
  unsigned int  f_type;
  unsigned int  f_bsize;
  unsigned long long f_blocks;
  unsigned long long f_bfree;
  unsigned long long f_bavail;
  unsigned long long f_files;
  unsigned long long f_ffree;
  fsid_t        f_fsid;
  unsigned int  f_namelen;
  unsigned int  f_frsize;
  unsigned int  f_flags;
  unsigned int  f_spare[4];
} __attribute__((packed, aligned(4)));

static int pxx_narrow(const struct __pxx_kstatfs64 *k, struct statfs *b)
{
  /* Every 64-bit field, checked before it is stored. A single combined check
     after the fact would be the cheaper spelling and would also be the one that
     stores five wrong numbers first. */
  if (k->f_blocks != (unsigned long long)(unsigned long)k->f_blocks
   || k->f_bfree  != (unsigned long long)(unsigned long)k->f_bfree
   || k->f_bavail != (unsigned long long)(unsigned long)k->f_bavail
   || k->f_files  != (unsigned long long)(unsigned long)k->f_files
   || k->f_ffree  != (unsigned long long)(unsigned long)k->f_ffree) {
    errno = EOVERFLOW;
    return -1;
  }
  b->f_type    = (long)k->f_type;
  b->f_bsize   = (long)k->f_bsize;
  b->f_blocks  = (unsigned long)k->f_blocks;
  b->f_bfree   = (unsigned long)k->f_bfree;
  b->f_bavail  = (unsigned long)k->f_bavail;
  b->f_files   = (unsigned long)k->f_files;
  b->f_ffree   = (unsigned long)k->f_ffree;
  b->f_fsid    = k->f_fsid;
  b->f_namelen = (long)k->f_namelen;
  b->f_frsize  = (long)k->f_frsize;
  b->f_flags   = (long)k->f_flags;
  return 0;
}

int statfs(const char *path, struct statfs *buf)
{
  struct __pxx_kstatfs64 k;
  if (syscall(SYS_statfs64, (long)path, (long)sizeof(k), (long)&k) < 0) return -1;
  return pxx_narrow(&k, buf);
}

int fstatfs(int fd, struct statfs *buf)
{
  struct __pxx_kstatfs64 k;
  if (syscall(SYS_fstatfs64, (long)fd, (long)sizeof(k), (long)&k) < 0) return -1;
  return pxx_narrow(&k, buf);
}

#elif defined(SYS_statfs)

int statfs(const char *path, struct statfs *buf)
{
  return syscall(SYS_statfs, (long)path, (long)buf) < 0 ? -1 : 0;
}

int fstatfs(int fd, struct statfs *buf)
{
  return syscall(SYS_fstatfs, (long)fd, (long)buf) < 0 ? -1 : 0;
}

#else

/* arm32 and xtensa: <sys/syscall.h> deliberately names no numbers for them,
   so there is nothing to call. They REFUSE, in the shape the ESP work already
   uses -- ENOSYS and -1, never a plausible wrong answer.

   The test is `#ifdef SYS_statfs' and not a use of SYS_statfs, and that is
   load-bearing. pxx's C frontend does not reject an undeclared identifier used
   as a value: it warns and treats it as 0. So this file, written the obvious
   way, COMPILED for arm32 and called syscall number 0 -- and the header's own
   claim that "naming any SYS_* here is a compile error, which is the point" is
   not true under this compiler. Measured 2026-09-02: the arm32 build produced
   a binary that reported errno 38 from statfs("/"), which reads as a missing
   syscall and is really a call to the wrong one. Filed as
   bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error.
   Until that is settled, a guard here has to be a PREPROCESSOR test, because
   that is the one that cannot be answered with a silent zero. */
int statfs(const char *path, struct statfs *buf)
{
  (void)path; (void)buf;
  errno = ENOSYS;
  return -1;
}

int fstatfs(int fd, struct statfs *buf)
{
  (void)fd; (void)buf;
  errno = ENOSYS;
  return -1;
}

#endif

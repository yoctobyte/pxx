/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: select(2).
 *
 * OVER THE RAW SYSCALL BRIDGE, same reasoning as src/sys/statfs.c and
 * src/sys/sysinfo.c: fd_set is the kernel's own memory layout and a PAL entry
 * would be a Linux bitmap wearing a portable name.
 *
 * THREE KERNEL SPELLINGS, and which one a target has is not a detail:
 *
 *   x86-64   sys_select     (nfds, r, w, e, struct timeval *)
 *   i386     sys__newselect (nfds, r, w, e, struct timeval *)   -- sys_select
 *                           on i386 is the ANCIENT one that takes a pointer to
 *                           a five-word argument block, which is why glibc
 *                           calls _newselect there and so does this file
 *   others   sys_pselect6   (nfds, r, w, e, struct timespec *, sigmask block)
 *
 * THE TIMEOUT IS THE DIFFERENCE THAT LEAKS INTO CALLERS. Linux's select
 * updates *timeout with the time remaining; pselect6 does not, and POSIX
 * permits both. A loop written as `while (n) select(..., &tv)' therefore
 * terminates on x86-64 and i386 and spins forever on a pselect6 target. glibc
 * has exactly this split and does not paper over it either. Stated here, in
 * the file, because the only other place it could be discovered is a hang.
 */
#include <sys/select.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <unistd.h>
#include <errno.h>

#if defined(SYS_select) && defined(__x86_64__)

int select(int nfds, fd_set *r, fd_set *w, fd_set *e, struct timeval *tv)
{
  return (int)syscall(SYS_select, (long)nfds, (long)r, (long)w, (long)e, (long)tv);
}

#elif defined(SYS__newselect)

int select(int nfds, fd_set *r, fd_set *w, fd_set *e, struct timeval *tv)
{
  return (int)syscall(SYS__newselect, (long)nfds, (long)r, (long)w, (long)e, (long)tv);
}

#elif defined(SYS_pselect6) || defined(SYS_pselect6_time64)

/* pselect6's sixth argument is not a sigset_t. It is a pointer to a two-word
   block {const sigset_t *set, size_t setsize}, and passing a null sigset
   directly -- the obvious reading of the man page's `const sigset_t *sigmask'
   -- is a null 6th argument, which the kernel accepts and which means
   "no mask". That is what is passed here, and it is correct BY THE
   NULL-POINTER RULE rather than by the block being filled in. */

/* riscv32 has no 32-bit time syscalls at all: its only pselect6 is the
   time64 one, and its timespec is two 64-bit words even though `long' is 32
   bits. So the struct passed to the kernel is spelled out here rather than
   taken from <time.h>, whose struct timespec is the target's own and is the
   WRONG shape on exactly this path. */
struct __pxx_kts64 { long long tv_sec; long long tv_nsec; };
struct __pxx_kts32 { long tv_sec; long tv_nsec; };

int select(int nfds, fd_set *r, fd_set *w, fd_set *e, struct timeval *tv)
{
#if defined(SYS_pselect6) && !(defined(__riscv) && (__riscv_xlen == 32))
  struct __pxx_kts32 ts;
  struct __pxx_kts32 *pts = 0;
  if (tv) { ts.tv_sec = (long)tv->tv_sec; ts.tv_nsec = (long)tv->tv_usec * 1000L; pts = &ts; }
  return (int)syscall(SYS_pselect6, (long)nfds, (long)r, (long)w, (long)e,
                      (long)pts, (long)0);
#else
  struct __pxx_kts64 ts;
  struct __pxx_kts64 *pts = 0;
  if (tv) { ts.tv_sec = (long long)tv->tv_sec; ts.tv_nsec = (long long)tv->tv_usec * 1000LL; pts = &ts; }
  return (int)syscall(SYS_pselect6_time64, (long)nfds, (long)r, (long)w, (long)e,
                      (long)pts, (long)0);
#endif
}

#else

/* arm32 and xtensa: <sys/syscall.h> names no numbers for them on purpose, so
   there is nothing to call and this REFUSES rather than guessing. The guard is
   a preprocessor test and not a use of SYS_select, because pxx's C frontend
   turns an undeclared identifier into 0 with a warning -- see
   bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error,
   and src/sys/statfs.c, where that cost an arm32 build a silent call to
   syscall number 0. */
int select(int nfds, fd_set *r, fd_set *w, fd_set *e, struct timeval *tv)
{
  (void)nfds; (void)r; (void)w; (void)e; (void)tv;
  errno = ENOSYS;
  return -1;
}

#endif

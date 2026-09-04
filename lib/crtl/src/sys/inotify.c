/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: inotify, over the raw syscall bridge.
 *
 * THE ONE INTERESTING LINE IS inotify_init. The asm-generic targets -- aarch64
 * and riscv32 -- have NO SYS_inotify_init: their table begins at init1, and
 * glibc synthesises init as init1(0) there. Without that fallback, inotifyd
 * would work on x86-64, i386 and arm32 and take an ENOSYS arm on the other
 * two, with nothing in the build saying so. That asymmetry is exactly the
 * arm32 syscall-table bug this runtime closed on 2026-09-04, one target
 * further in, and it is why the #ifdef here is a CASCADE and not a guard:
 *
 *     have SYS_inotify_init   -> call it
 *     have SYS_inotify_init1  -> call init1(0), which is the same thing
 *     neither                 -> ENOSYS
 *
 * ERRNO CONVENTION: syscall() in src/unistd.c already returns -1 with errno
 * set, so these pass it through. Applying the PAL's -errno idiom here would
 * report EPERM for every failure.
 */
#include <sys/inotify.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>

int inotify_init(void) {
#if defined(SYS_inotify_init)
  return (int)syscall(SYS_inotify_init);
#elif defined(SYS_inotify_init1)
  /* aarch64 and riscv32 land here: init1 with no flags IS init. */
  return (int)syscall(SYS_inotify_init1, 0L);
#else
  errno = ENOSYS;
  return -1;
#endif
}

int inotify_init1(int flags) {
#ifdef SYS_inotify_init1
  return (int)syscall(SYS_inotify_init1, (long)flags);
#else
  (void)flags;
  errno = ENOSYS;
  return -1;
#endif
}

int inotify_add_watch(int fd, const char *pathname, uint32_t mask) {
#ifdef SYS_inotify_add_watch
  return (int)syscall(SYS_inotify_add_watch, (long)fd, pathname, (long)mask);
#else
  (void)fd; (void)pathname; (void)mask;
  errno = ENOSYS;
  return -1;
#endif
}

int inotify_rm_watch(int fd, int wd) {
#ifdef SYS_inotify_rm_watch
  return (int)syscall(SYS_inotify_rm_watch, (long)fd, (long)wd);
#else
  (void)fd; (void)wd;
  errno = ENOSYS;
  return -1;
#endif
}

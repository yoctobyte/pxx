/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: mount/umount/umount2, over the raw syscall bridge.
 *
 * These have no PAL entry of their own and should not: there is nothing for a
 * FreeRTOS or WASI backend to refuse in terms of -- no filesystem namespace
 * exists there to mount into -- and the calls are used by exactly one class of
 * program. <sys/syscall.h> already refuses honestly on the targets whose
 * syscall table this runtime cannot source.
 *
 * umount(target) IS umount2(target, 0), by the kernel's own definition on
 * every architecture that still has a separate umount number, so there is one
 * implementation and not two to keep in step.
 */
#include <sys/mount.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>

int mount(const char *source, const char *target, const char *fstype,
          unsigned long mountflags, const void *data) {
#ifdef SYS_mount
  return (int)syscall(SYS_mount, (long)source, (long)target, (long)fstype,
                      (long)mountflags, (long)data, 0L);
#else
  (void)source; (void)target; (void)fstype; (void)mountflags; (void)data;
  errno = ENOSYS;
  return -1;
#endif
}

int umount2(const char *target, int flags) {
#ifdef SYS_umount2
  return (int)syscall(SYS_umount2, (long)target, (long)flags, 0L, 0L, 0L, 0L);
#else
  (void)target; (void)flags;
  errno = ENOSYS;
  return -1;
#endif
}

int umount(const char *target) {
  return umount2(target, 0);
}

/* pivot_root(2). Same family and the same reasoning as mount above: it moves
   the root of a mount namespace, which is not a thing a FreeRTOS or WASI
   backend can be asked to refuse in terms of.

   WHY THIS EXISTS AT ALL: it is the ONE symbol that stood between a 258-applet
   pxx-built busybox and a link with no libc in it. Measured 2026-09-16 over
   400 objects -- 780 undefined references, 779 of them satisfied by another
   pxx object, and this. glibc carries a stub for it, so the ordinary
   `gcc -o out obj/*.o' link resolved it silently and nothing was ever red;
   the gap was only visible once the link was asked to use no library at all.
   See feature-a-pxx-cannot-link-its-own-objects. */
int pivot_root(const char *new_root, const char *put_old) {
#ifdef SYS_pivot_root
  return (int)syscall(SYS_pivot_root, (long)new_root, (long)put_old,
                      0L, 0L, 0L, 0L);
#else
  (void)new_root; (void)put_old;
  errno = ENOSYS;
  return -1;
#endif
}

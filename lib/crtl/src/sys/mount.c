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

/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: reboot(2).
 *
 * THE KERNEL'S reboot IS A FOUR-ARGUMENT CALL and the libc one is not. The
 * syscall takes (magic1, magic2, cmd, arg); the two magic words exist so that
 * a stray call cannot reboot the machine by accident, and every libc supplies
 * them. Passing `howto' as the first argument -- the obvious reading of the
 * prototype -- gets EINVAL, which at least fails loudly; the values below are
 * from uapi/linux/reboot.h.
 */
#include <sys/reboot.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>

#define PXX_REBOOT_MAGIC1 0xfee1deadu
#define PXX_REBOOT_MAGIC2 672274793u    /* 0x28121969 -- Linus's birthday */

int reboot(int howto) {
#ifdef SYS_reboot
  return (int)syscall(SYS_reboot, (long)(int)PXX_REBOOT_MAGIC1,
                      (long)(int)PXX_REBOOT_MAGIC2, (long)howto, 0L);
#else
  /* arm32/xtensa carry no syscall table here; see <sys/syscall.h>. */
  (void)howto;
  errno = ENOSYS;
  return -1;
#endif
}

/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: sysinfo(2).
 *
 * OVER THE RAW SYSCALL BRIDGE RATHER THAN A PAL ENTRY, and that is the
 * deliberate choice syscall.c's header comment describes: the call has exactly
 * one shape, the struct it fills is the kernel's own, and there is nothing for
 * a non-Linux backend to implement in terms of. A PalSysInfo would be a Linux
 * struct with a Linux layout wearing a portable name -- the shape this codebase
 * calls "the name is not the thing".
 *
 * Consequence, stated rather than discovered: this is Linux-only. On a target
 * whose <sys/syscall.h> has no SYS_sysinfo the reference below does not
 * compile, which is the loud failure and the one worth having.
 */
#include <sys/sysinfo.h>
#include <sys/syscall.h>
#include <unistd.h>

int sysinfo(struct sysinfo *info) {
  return (int)syscall(SYS_sysinfo, (long)info);
}

/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/reboot.h>.
 *
 * The RB_ values are MAGIC NUMBERS the kernel compares literally -- they are
 * not a bitmask and not an enum, and a wrong one is rejected rather than
 * misread, which is the one mercy in this header. They are transcribed from
 * uapi/linux/reboot.h.
 *
 * Found attempting busybox rung 2: init/halt.c (halt, poweroff, reboot) and
 * init/init.c's CTRL-ALT-DEL handling.
 */
#ifndef _CRTL_SYS_REBOOT_H
#define _CRTL_SYS_REBOOT_H

#define RB_AUTOBOOT     0x01234567
#define RB_HALT_SYSTEM  0xcdef0123
#define RB_ENABLE_CAD   0x89abcdef
#define RB_DISABLE_CAD  0x00000000
#define RB_POWER_OFF    0x4321fedc
#define RB_SW_SUSPEND   0xd000fce2
#define RB_KEXEC        0x45584543

/* Returns only on failure (-1 with errno) -- or on RB_ENABLE_CAD /
   RB_DISABLE_CAD, which merely set a flag and return 0. */
int reboot(int howto);

#endif

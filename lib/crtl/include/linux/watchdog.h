/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/watchdog.h>.
 *
 * WDIOC_SETTIMEOUT IS _IOWR AND WDIOC_GETTIMEOUT IS _IOR, and the pair is the
 * reason these are spelled with the _IOC macros here rather than transcribed
 * as hex: the direction bits are part of the NUMBER, so a SETTIMEOUT written
 * as _IOR is a different ioctl that the driver does not implement, and
 * busybox's watchdog daemon then runs with the hardware's default timeout
 * while reporting that it set one. Note WDIOC_SETOPTIONS is _IOR despite
 * writing -- that is the kernel's own inconsistency, transcribed, not fixed.
 *
 * Found attempting busybox on i386: miscutils/watchdog.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_LINUX_WATCHDOG_H
#define _CRTL_LINUX_WATCHDOG_H

#include <linux/types.h>
#include <sys/ioctl.h>

#define WATCHDOG_IOCTL_BASE 'W'

struct watchdog_info {
  __u32 options;           /* Options the card/driver supports */
  __u32 firmware_version;  /* Firmware version of the card */
  __u8  identity[32];      /* Identity of the board */
};

#define WDIOC_GETSUPPORT     _IOR(WATCHDOG_IOCTL_BASE, 0, struct watchdog_info)
#define WDIOC_GETSTATUS      _IOR(WATCHDOG_IOCTL_BASE, 1, int)
#define WDIOC_GETBOOTSTATUS  _IOR(WATCHDOG_IOCTL_BASE, 2, int)
#define WDIOC_GETTEMP        _IOR(WATCHDOG_IOCTL_BASE, 3, int)
#define WDIOC_SETOPTIONS     _IOR(WATCHDOG_IOCTL_BASE, 4, int)
#define WDIOC_KEEPALIVE      _IOR(WATCHDOG_IOCTL_BASE, 5, int)
#define WDIOC_SETTIMEOUT     _IOWR(WATCHDOG_IOCTL_BASE, 6, int)
#define WDIOC_GETTIMEOUT     _IOR(WATCHDOG_IOCTL_BASE, 7, int)
#define WDIOC_SETPRETIMEOUT  _IOWR(WATCHDOG_IOCTL_BASE, 8, int)
#define WDIOC_GETPRETIMEOUT  _IOR(WATCHDOG_IOCTL_BASE, 9, int)
#define WDIOC_GETTIMELEFT    _IOR(WATCHDOG_IOCTL_BASE, 10, int)

#define WDIOF_UNKNOWN        -1      /* Unknown flag error */
#define WDIOS_UNKNOWN        -1      /* Unknown status error */

#define WDIOF_OVERHEAT       0x0001  /* Reset due to CPU overheat */
#define WDIOF_FANFAULT       0x0002  /* Fan failed */
#define WDIOF_EXTERN1        0x0004  /* External relay 1 */
#define WDIOF_EXTERN2        0x0008  /* External relay 2 */
#define WDIOF_POWERUNDER     0x0010  /* Power bad/power fault */
#define WDIOF_CARDRESET      0x0020  /* Card previously reset the CPU */
#define WDIOF_POWEROVER      0x0040  /* Power over voltage */
#define WDIOF_SETTIMEOUT     0x0080  /* Set timeout (in seconds) */
#define WDIOF_MAGICCLOSE     0x0100  /* Supports magic close char */
#define WDIOF_PRETIMEOUT     0x0200  /* Pretimeout (in seconds), get/set */
#define WDIOF_ALARMONLY      0x0400  /* Alarm only, no reset */
#define WDIOF_KEEPALIVEPING  0x8000  /* Keep alive ping reply */

#define WDIOS_DISABLECARD    0x0001  /* Turn off the watchdog timer */
#define WDIOS_ENABLECARD     0x0002  /* Turn on the watchdog timer */
#define WDIOS_TEMPPANIC      0x0004  /* Kernel panic on temperature trip */

#endif

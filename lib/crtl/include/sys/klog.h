/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/klog.h> -- klogctl(2), the kernel ring buffer.
 *
 * THE SYSCALL IS NAMED syslog AND THE FUNCTION IS NOT. glibc renames it here
 * because <syslog.h> already spends that name on the unrelated user-level
 * logging function; the two have nothing to do with each other.
 *
 * THE COMMAND NUMBERS ARE THE INTERFACE, and glibc does NOT declare them --
 * it ships the function and leaves every caller writing bare integers
 * (busybox's dmesg.c and klogd.c both do). They are the kernel's own
 * SYSLOG_ACTION_* from <linux/kmsg.h> and are named here because a wrong
 * number does not fail: READ_CLEAR where READ was meant EMPTIES the ring
 * buffer the next reader wanted. This is a superset of glibc, never a
 * divergence -- the function and its signature are identical.
 *
 * Found attempting busybox on i386: util-linux/dmesg.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_KLOG_H
#define _CRTL_SYS_KLOG_H

#define SYSLOG_ACTION_CLOSE          0
#define SYSLOG_ACTION_OPEN           1
#define SYSLOG_ACTION_READ           2
#define SYSLOG_ACTION_READ_ALL       3
#define SYSLOG_ACTION_READ_CLEAR     4
#define SYSLOG_ACTION_CLEAR          5
#define SYSLOG_ACTION_CONSOLE_OFF    6
#define SYSLOG_ACTION_CONSOLE_ON     7
#define SYSLOG_ACTION_CONSOLE_LEVEL  8
#define SYSLOG_ACTION_SIZE_UNREAD    9
#define SYSLOG_ACTION_SIZE_BUFFER   10

int klogctl(int type, char *bufp, int len);

#endif

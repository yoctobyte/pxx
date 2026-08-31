/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <paths.h> -- the BSD-derived table of well-known filesystem
 * locations. Macros only; there is nothing to implement.
 *
 * These are the values a Linux system uses, which is the only platform this
 * runtime targets. _PATH_BSHELL is /bin/sh rather than /bin/bash on purpose:
 * it names the POSIX shell a program may exec, not the login shell a user
 * happens to have.
 */
#ifndef _CRTL_PATHS_H
#define _CRTL_PATHS_H

#define _PATH_DEFPATH   "/usr/bin:/bin"
#define _PATH_STDPATH   "/usr/bin:/bin:/usr/sbin:/sbin"
#define _PATH_BSHELL    "/bin/sh"
#define _PATH_CONSOLE   "/dev/console"
#define _PATH_DEVNULL   "/dev/null"
#define _PATH_KLOG      "/proc/kmsg"
#define _PATH_LASTLOG   "/var/log/lastlog"
#define _PATH_MAILDIR   "/var/mail"
#define _PATH_MAN       "/usr/share/man"
#define _PATH_MNTTAB    "/etc/fstab"
#define _PATH_MOUNTED   "/etc/mtab"
#define _PATH_NOLOGIN   "/etc/nologin"
#define _PATH_SENDMAIL  "/usr/sbin/sendmail"
#define _PATH_SHADOW    "/etc/shadow"
#define _PATH_SHELLS    "/etc/shells"
#define _PATH_TTY       "/dev/tty"
#define _PATH_UTMP      "/var/run/utmp"
#define _PATH_VI        "/usr/bin/vi"
#define _PATH_WTMP      "/var/log/wtmp"
#define _PATH_DEV       "/dev/"
#define _PATH_TMP       "/tmp/"
#define _PATH_VARDB     "/var/db/"
#define _PATH_VARRUN    "/var/run/"
#define _PATH_VARTMP    "/var/tmp/"

#endif

/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <pty.h> -- openpty, forkpty, and login_tty (which glibc declares
 * in <utmp.h> and which lives with the other two here).
 *
 * Found building dropbear (feature-c-dropbear-builds-with-pxx): sshpty.c's
 * pty_allocate() calls openpty() for every interactive session.
 *
 * They are built on the posix_openpt/grantpt/unlockpt/ptsname_r family that
 * <stdlib.h> already provides, the way the BSDs and musl build them.
 */
#ifndef _CRTL_PTY_H
#define _CRTL_PTY_H

#include <termios.h>
#include <sys/types.h>

int openpty(int *amaster, int *aslave, char *name,
            const struct termios *termp, const struct winsize *winp);
pid_t forkpty(int *amaster, char *name,
              const struct termios *termp, const struct winsize *winp);
int login_tty(int fd);

#endif

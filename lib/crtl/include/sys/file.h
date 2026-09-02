/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/file.h> -- flock(2).
 *
 * FLOCK IS NOT fcntl RECORD LOCKING and on Linux the two do not see each
 * other: this is a whole-file advisory lock tied to the open FILE DESCRIPTION,
 * so it is inherited by fork and by dup and released when the LAST copy
 * closes. crtl's <fcntl.h> already carries `struct flock' for the other kind;
 * that they share a name is the C library's accident, not a relationship.
 *
 * THE LOCK_* NUMBERS ARE IN <fcntl.h>, not here -- glibc puts them there and
 * repeating them would give the pair two definition sites to disagree at.
 * This header is the include-guarded name busybox and POSIX code reach for,
 * plus the declaration that pulls src/sys/file.c in.
 *
 * Found attempting busybox on i386: util-linux/flock.c and runit/sv.c, which
 * take an exclusive non-blocking lock to be the single controller.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_FILE_H
#define _CRTL_SYS_FILE_H

#include <fcntl.h>

int flock(int fd, int operation);

#endif

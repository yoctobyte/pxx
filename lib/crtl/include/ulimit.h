/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <ulimit.h> (POSIX XSI, obsolescent): the file-size limit in
 * 512-byte blocks, over getrlimit/setrlimit(RLIMIT_FSIZE). mksh includes it
 * whenever it exists (HAVE_ULIMIT_H) and uses the UL_ names only when it has
 * no rlimits. Only the two POSIX commands; any other is EINVAL.
 */
#ifndef _CRTL_ULIMIT_H
#define _CRTL_ULIMIT_H

#define UL_GETFSIZE 1   /* the soft limit, in 512-byte blocks */
#define UL_SETFSIZE 2   /* set both limits to the argument, in blocks */

long ulimit(int cmd, ...);

#endif

/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <memory.h> -- the pre-ANSI name for the mem* half of <string.h>.
 *
 * glibc's is one line that includes <string.h>, and so is this. Without it the
 * include fell through to the host's /usr/include/memory.h (sqlite's shell.c
 * includes it), which works only while glibc's own headers happen to parse.
 */
#ifndef _CRTL_MEMORY_H
#define _CRTL_MEMORY_H
#include <string.h>
#endif

/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <libgen.h> -- POSIX basename() and dirname().
 *
 * Both MAY MODIFY the string they are given and both may return a pointer into
 * it, which is the whole reason this header exists separately from <string.h>:
 * glibc's <string.h> declares a DIFFERENT, non-modifying `basename`, and a
 * program gets one or the other depending on which header it included and
 * whether _GNU_SOURCE was defined. We provide only the POSIX one, here, so
 * there is one function with one behaviour and no include-order dependency.
 */
#ifndef _CRTL_LIBGEN_H
#define _CRTL_LIBGEN_H

char *basename(char *path);
char *dirname(char *path);

#endif

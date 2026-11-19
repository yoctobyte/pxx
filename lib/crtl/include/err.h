/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <err.h> -- the BSD formatted error reporters.
 *
 *   warn/vwarn    "prog: <fmt>: <strerror(errno)>\n" to stderr
 *   warnx/vwarnx  "prog: <fmt>\n"
 *   err/verr      warn, then exit(status)
 *   errx/verrx    warnx, then exit(status)
 *
 * `prog` is program_invocation_short_name, the basename of argv[0], as glibc
 * prints it. Missing until 2026-11-19: without it `#include <err.h>` fell
 * through to the host's glibc header, whose <sys/cdefs.h> pxx cannot parse
 * (e2fsprogs, util-linux). feature-crtl-runtime-gaps-from-e2fsprogs-util-linux-dosfstools
 */
#ifndef _CRTL_ERR_H
#define _CRTL_ERR_H

#include <stdarg.h>

void warn(const char *fmt, ...);
void vwarn(const char *fmt, va_list ap);
void warnx(const char *fmt, ...);
void vwarnx(const char *fmt, va_list ap);
void err(int status, const char *fmt, ...);
void verr(int status, const char *fmt, va_list ap);
void errx(int status, const char *fmt, ...);
void verrx(int status, const char *fmt, va_list ap);

#endif

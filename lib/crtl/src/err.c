/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <err.h>. Output format matches glibc byte for byte:
 *
 *   warn("open %s", f)    ->  "prog: open f: No such file or directory\n"
 *   warnx("bad %d", 3)    ->  "prog: bad 3\n"
 *   warn(NULL)            ->  "prog: No such file or directory\n"
 *   warnx(NULL)           ->  "prog: \n"
 *
 * errno is read BEFORE anything is printed, because the stdio calls below may
 * themselves change it. stdout is flushed first so that interleaved output
 * keeps its order, as glibc does.
 */
#include <err.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>   /* program_invocation_short_name, set before main in unistd.c */
#include <fcntl.h>

/* The program's short name. Set before main from argv[0]; a shared library
   has no initial stack, so it is NULL there and the kernel's comm (the first
   15 bytes of the same basename) stands in. */
static const char *crtl_err_prog(void)
{
  static char comm[32];
  int fd, n;
  if (program_invocation_short_name) return program_invocation_short_name;
  if (comm[0]) return comm;
  fd = open("/proc/self/comm", O_RDONLY);
  if (fd < 0) return "";
  n = (int)read(fd, comm, sizeof comm - 1);
  close(fd);
  if (n <= 0) { comm[0] = 0; return ""; }
  if (comm[n - 1] == '\n') n--;
  comm[n] = 0;
  return comm;
}

static void crtl_err_head(void)
{
  fflush(stdout);
  fprintf(stderr, "%s: ", crtl_err_prog());
}

void vwarn(const char *fmt, va_list ap)
{
  int e = errno;
  crtl_err_head();
  if (fmt) {
    vfprintf(stderr, fmt, ap);
    fputs(": ", stderr);
  }
  fprintf(stderr, "%s\n", strerror(e));
}

void vwarnx(const char *fmt, va_list ap)
{
  crtl_err_head();
  if (fmt) vfprintf(stderr, fmt, ap);
  fputc('\n', stderr);
}

void warn(const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  vwarn(fmt, ap);
  va_end(ap);
}

void warnx(const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  vwarnx(fmt, ap);
  va_end(ap);
}

void verr(int status, const char *fmt, va_list ap)
{
  vwarn(fmt, ap);
  exit(status);
}

void verrx(int status, const char *fmt, va_list ap)
{
  vwarnx(fmt, ap);
  exit(status);
}

void err(int status, const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  verr(status, fmt, ap);
  va_end(ap);
}

void errx(int status, const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  verrx(status, fmt, ap);
  va_end(ap);
}

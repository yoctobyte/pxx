/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: ioctl. Was DECLARED in sys/ioctl.h with no body, so every caller
 * bound to libc.so.6 through the unresolved-extern fallback and the binary
 * silently stopped being self-contained (tools/crtl_decl_probe.sh).
 *
 * The PAL entry it needs already existed: PalIoctl is a fully general
 * `syscall(SYS_ioctl, fd, cmd, argp)` — __pxx_isatty has been using it for the
 * single TCGETS case all along. __pxx_ioctl in lib/rtl/pxxcio.pas exposes the
 * general form; this file only converts the result to the C convention.
 *
 * ON ESP: the IDF backend routes this to lwip_ioctl (sockets work), and the
 * bare profile answers PAL_ERR_UNSUPPORTED. That surfaces here as -1 with an
 * errno, which is the deliberate Track S failure mode — a refusal, not a wrong
 * answer.
 */

#include <sys/ioctl.h>
#include <stdarg.h>
#include <errno.h>

int ioctl(int fd, unsigned long request, ...) {
  va_list ap;
  void *argp;
  int r;
  /* The third argument is optional in the C signature but always present in
     the syscall. Reading it when the caller passed nothing yields garbage the
     kernel ignores for the arg-less requests — the same bargain libc makes. */
  va_start(ap, request);
  argp = va_arg(ap, void *);
  va_end(ap);
  r = __pxx_ioctl(fd, (long)request, argp);
  if (r < 0) { errno = -r; return -1; }
  return r;
}

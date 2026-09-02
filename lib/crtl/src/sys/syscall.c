/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: syscall(2).
 *
 * The escape hatch, and it is one on purpose. Everything crtl offers goes
 * through a named PAL entry that the non-Linux backends can refuse in terms
 * of; this hands the kernel interface to the caller directly, because a
 * program spelling syscall(2) has asked for exactly that. busybox's
 * util-linux/ionice.c (ioprio_get/ioprio_set) and modutils (finit_module) are
 * why it exists -- the alternative is a bespoke PAL entry per exotic call,
 * each used once, and none of them portable anyway.
 *
 * SIX ARGUMENTS ARE ALWAYS FETCHED, however many were passed. That is what
 * every libc does (in asm, which is why it is not UB there), and it is safe
 * for the same reason: the kernel reads only the registers the call number
 * defines, so the extra words are never looked at. A variadic C version cannot
 * know the count -- the number decides it -- so there is nothing else to do.
 *
 * The PAL returns the kernel's answer untranslated: negative is -errno, and
 * the conversion to -1/errno happens here, once. A call that legitimately
 * returns a large negative value (there is none in Linux's table -- the kernel
 * reserves -1..-4095 for errors precisely so this works) would be
 * misinterpreted, which is the same trade glibc makes.
 */
#include <sys/syscall.h>
#include <stdarg.h>
#include <errno.h>

extern long __pxx_syscall(long num, long a1, long a2, long a3,
                          long a4, long a5, long a6);

long syscall(long number, ...) {
  va_list ap;
  long a[6];
  int i;
  long rc;

  va_start(ap, number);
  for (i = 0; i < 6; i++) a[i] = va_arg(ap, long);
  va_end(ap);

  rc = __pxx_syscall(number, a[0], a[1], a[2], a[3], a[4], a[5]);
  if (rc < 0 && rc > -4096) { errno = (int)-rc; return -1; }
  return rc;
}

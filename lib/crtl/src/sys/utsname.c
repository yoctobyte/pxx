/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: uname(2).
 *
 * busybox reaches it through libbb/kernel_version.c, whose comment says
 * "never fails" -- and on Linux it effectively does not. This wrapper still
 * reports failure rather than leaving the buffer untouched and returning 0,
 * because on the PAL backends that refuse (ESP, WASI) the caller would
 * otherwise read an uninitialised struct and parse whatever was on the stack
 * as a kernel version.
 */
#include <sys/utsname.h>
#include <errno.h>

int __pxx_uname(void *buf);

int uname(struct utsname *buf) {
  int rc = __pxx_uname((void *)buf);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

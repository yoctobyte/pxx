/* SPDX-License-Identifier: Zlib */
/*
 * crtl: the BSD bit-array macros, the unprefixed sighandler_t, and fdatasync.
 *
 * THREE THINGS BUSYBOX ASSUMES EXIST WITHOUT A GUARD. Its include/platform.h
 * carries a table of HAVE_* defaults (lines 403-433) that are all 1 for a
 * glibc-shaped libc, and it defines its own fallback ONLY under the matching
 * #undef -- so an entry crtl lacked was a compile error with no fallback path,
 * waiting for the configuration that reached it. These three were the entries
 * crtl lacked: HAVE_SETBIT, HAVE_SIGHANDLER_T, HAVE_FDATASYNC.
 *
 * ROW 1 IS THE ONE WITH A WRONG ANSWER AVAILABLE. setbit's array is addressed
 * in BYTES while its bit index runs across the whole array, so bit 9 is bit 1
 * of a[1]. A macro that gets the two halves inconsistent still sets A bit, in
 * range, with no error -- it just sets a different one. Row 1 prints three
 * bytes so the bit's PLACE is checked and not merely its presence.
 *
 * fdatasync is NOT fsync. Aliasing it would pass rows 6-9 and quietly flush
 * more than asked; row 9 is the negative control that it is a real syscall
 * (EBADF from the kernel on a closed descriptor, not a silent 0).
 *
 * _GNU_SOURCE because glibc gates sighandler_t and setbit behind it. busybox
 * defines it too. crtl publishes them unconditionally; accepting what glibc
 * hides is not a divergence that can break a program.
 *
 * Every row was diffed against glibc by compiling this same file with gcc.
 * feature-c-corpus-busybox-multi-applet
 */
#define _GNU_SOURCE 1
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <sys/param.h>

static void h(int s) { (void)s; }

int main(void) {
  unsigned char bits[4];
  sighandler_t fp;
  int fd, rc, e;
  char path[256];
  const char *dir;

  /* Directory from the environment, never a bare /tmp literal: a path written
     at RUNTIME is one no Makefile sweep reaches, so testmgr cannot privatize
     it and two concurrent runs share the file. TESTMGR_TMP first (testmgr's
     env allowlist is what $TESTTMP does not survive), TESTTMP second, /tmp
     last so a bare run stays byte-identical.
     Guard: tools/testmgr_hardcoded_tmp_devtest.py. */
  dir = getenv("TESTMGR_TMP");
  if (!dir) dir = getenv("TESTTMP");
  if (!dir) dir = "/tmp";
  snprintf(path, sizeof path, "%s/pxx_fdatasync_probe_%d", dir, (int)getpid());

  memset(bits, 0, sizeof(bits));
  setbit(bits, 9);
  setbit(bits, 0);
  printf("1 %d %d %d\n", bits[0], bits[1], bits[2]);
  rc = isset(bits, 9) ? 1 : 0;
  printf("2 %d\n", rc);
  rc = isclr(bits, 10) ? 1 : 0;
  printf("3 %d\n", rc);
  clrbit(bits, 9);
  rc = isset(bits, 9) ? 1 : 0;
  printf("4 %d %d\n", rc, bits[1]);

  fp = h;                       /* the unprefixed typedef must exist */
  printf("5 %d\n", fp == h);

  fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0600);
  printf("6 %d\n", fd >= 0);
  rc = (int)write(fd, "hello", 5);
  printf("7 %d\n", rc);
  rc = fdatasync(fd);
  printf("8 %d\n", rc);
  close(fd);
  unlink(path);
  /* a closed fd: EBADF from the kernel, not a silent success */
  rc = fdatasync(fd);
  e = errno;
  printf("9 %d %d\n", rc, rc < 0 ? e == EBADF : -1);
  return 0;
}

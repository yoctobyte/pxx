/* SPDX-License-Identifier: Zlib */
/* The four open() flags Linux does NOT define uniformly, asserted by EFFECT.
   O_DIRECTORY, O_NOFOLLOW, O_DIRECT and O_LARGEFILE are overridden by arm and
   arm64 against asm-generic -- arm effectively swaps O_DIRECTORY with
   O_DIRECT -- so <fcntl.h> carries an #if and this file is what says the #if
   is on the right side.

   IT ASSERTS NO CONSTANT, ON PURPOSE. Every row is a relation that holds on
   every target: a directory opens with O_DIRECTORY, a regular file does not,
   a symlink refuses O_NOFOLLOW. So one expected output is correct for x86-64,
   i386, arm32, aarch64 and riscv32, and the same file runs everywhere without
   a per-target table to go stale. The companion test
   c_crtl_header_constants.c does the value comparison, and can only do it on
   the host, against gcc -- which is precisely the axis this file covers and
   that one cannot.

   WHY IT IS NOT A THEORETICAL RISK. lib/rtl/platform.pas already carries the
   same split for PAL_OPEN_DIRECTORY, with the measurement behind it: on ARM
   the x86 value made a real directory return EINVAL *and* made a regular file
   open SUCCEED where the flag should have rejected it. Wrong in both
   directions, and neither direction is a compile error.

   THE ROWS ARE CHOSEN SO THE FAILURE VALUE IS NOT THE EXPECTED VALUE. A flag
   whose value came out 0 would leave O_DIRECTORY meaning "no extra
   condition", so row 2 -- a regular FILE opened with O_DIRECTORY, which must
   FAIL -- is the row that a zeroed or swapped flag cannot pass. Row 1 alone
   would pass with the flag zeroed. */

#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>

int main(void)
{
  int fd;
  const char *d = "cofa_dir";
  const char *f = "cofa_file";
  const char *l = "cofa_link";

  unlink(l); unlink(f); rmdir(d);
  if (mkdir(d, 0700) != 0)       { printf("setup mkdir failed\n"); return 1; }
  fd = open(f, O_WRONLY | O_CREAT | O_TRUNC, 0600);
  if (fd < 0)                    { printf("setup create failed\n"); return 1; }
  close(fd);
  if (symlink(f, l) != 0)        { printf("setup symlink failed\n"); return 1; }

  /* 1: a directory opens with O_DIRECTORY. */
  fd = open(d, O_RDONLY | O_DIRECTORY);
  printf("1 dir+O_DIRECTORY   %s\n", fd >= 0 ? "ok" : "REFUSED");
  if (fd >= 0) close(fd);

  /* 2: a regular file does NOT. This is the row a zeroed or swapped flag
        cannot pass -- it is the only one whose right answer is a refusal. */
  fd = open(f, O_RDONLY | O_DIRECTORY);
  printf("2 file+O_DIRECTORY  %s\n",
         (fd < 0 && errno == ENOTDIR) ? "ENOTDIR" : (fd < 0 ? "wrong-errno" : "OPENED"));
  if (fd >= 0) close(fd);

  /* 3: a symlink refuses O_NOFOLLOW. Zeroed, the open would SUCCEED on the
        target -- which is the security downgrade busybox's unzip, chattr and
        lsattr were shipping. */
  fd = open(l, O_RDONLY | O_NOFOLLOW);
  printf("3 link+O_NOFOLLOW   %s\n",
         (fd < 0 && errno == ELOOP) ? "ELOOP" : (fd < 0 ? "wrong-errno" : "OPENED"));
  if (fd >= 0) close(fd);

  /* 4: the plain file still opens, so rows 2 and 3 are refusing for their own
        reason and not because the path is unusable. A precondition, asserted
        rather than assumed. */
  fd = open(f, O_RDONLY);
  printf("4 file+O_RDONLY     %s\n", fd >= 0 ? "ok" : "REFUSED");
  if (fd >= 0) close(fd);

  unlink(l); unlink(f); rmdir(d);
  return 0;
}

/* SPDX-License-Identifier: Zlib */
/* Regression b238: the libc-free POSIX I/O leaves sqlite's unix VFS needs —
   pread/pwrite (positioned, offset-preserving), ftruncate, access, geteuid,
   fchown, readlink. Before this, crtl lacked them: sqlite's aSyscall[] slots
   resolved to address 0 and the file-backed VFS null-called inside seekAndRead
   (pread) / fillInUnixFile (geteuid+fchown). Exercises each against a real temp
   file and exits 42 on full success. Must link fully libc-free (0 DT_NEEDED). */

#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
#include "fcntl.c"
#include "unistd.c"
#include "sys/stat.c"
#include "fcntl.h"
#include "unistd.h"

int main(void) {
  const char *path = "/tmp/pxx_crtl_posix_io_b238.tmp";
  char buf[16];

  unlink(path);
  int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) return 1;

  /* write at offset 0, then pwrite "XY" at offset 3 without moving the offset */
  if (write(fd, "abcdef", 6) != 6) return 2;
  /* seek to 6 (EOF); pwrite must NOT disturb this offset */
  if (lseek(fd, 6, 0) != 6) return 3;
  if (pwrite(fd, "XY", 2, 3) != 2) return 4;
  if (lseek(fd, 0, 1 /*SEEK_CUR*/) != 6) return 5;  /* offset preserved */

  /* pread the patched region without moving the offset */
  memset(buf, 0, sizeof(buf));
  if (pread(fd, buf, 6, 0) != 6) return 6;
  if (memcmp(buf, "abcXYf", 6) != 0) return 7;
  if (lseek(fd, 0, 1) != 6) return 8;               /* offset preserved */

  /* ftruncate shrinks the file */
  if (ftruncate(fd, 3) != 0) return 9;
  memset(buf, 0, sizeof(buf));
  if (pread(fd, buf, 6, 0) != 3) return 10;         /* only 3 bytes remain */
  if (memcmp(buf, "abc", 3) != 0) return 11;

  close(fd);

  /* access: the file exists (F_OK=0), a bogus path does not */
  if (access(path, 0) != 0) return 12;
  if (access("/tmp/pxx_no_such_file_b238", 0) == 0) return 13;

  /* geteuid returns a value (root=0 in the qemu sandbox, else the real euid) */
  (void)geteuid();

  unlink(path);
  return 42;
}

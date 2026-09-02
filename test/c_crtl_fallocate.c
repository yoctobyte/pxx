/* crtl: posix_fallocate(3) and fallocate(2).
 *
 * busybox's util-linux/fallocate.c stopped a 400-translation-unit build on
 * `call to undeclared function: posix_fallocate'.
 *
 * THE POINT OF THIS FILE IS THE ERROR CONVENTION, not the allocation. One
 * syscall, two contracts: fallocate returns -1 and sets errno, posix_fallocate
 * returns the error NUMBER and must leave errno alone. busybox writes
 * `if ((errno = posix_fallocate(fd, ofs, len)) != 0)', so an implementation
 * that used the ordinary convention would assign -1 to errno and report
 * "Unknown error -1" for every failure -- while reading correctly in a diff.
 *
 * The bad-fd rows carry that, and they are filesystem-independent. The success
 * row is not: fallocate is refused with EOPNOTSUPP on some filesystems, so
 * that row accepts either answer rather than pinning one and failing on a box
 * whose /tmp is different. What it does NOT accept is -1, which is the bug.
 */
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/stat.h>
#include <stdlib.h>

int main(void)
{
  int fd;
  int rc;
  int saved;
  struct stat st;
  char path[256];
  const char *dir;

  /* Directory from the environment, never a bare /tmp literal: a path written
     at RUNTIME is one no Makefile sweep reaches, so testmgr cannot privatize
     it and two concurrent runs share the file. TESTMGR_TMP first, TESTTMP
     second, /tmp last so a bare run stays byte-identical.
     Guard: tools/testmgr_hardcoded_tmp_devtest.py. */
  dir = getenv("TESTMGR_TMP");
  if (!dir) dir = getenv("TESTTMP");
  if (!dir) dir = "/tmp";
  snprintf(path, sizeof path, "%s/pxx_crtl_fallocate_probe_%d", dir, (int)getpid());

  /* Bad fd, POSIX contract: the number comes back as the RETURN value and
     errno is untouched. Setting errno to a sentinel first is what makes the
     second half of that assertion able to fail. */
  errno = 12345;
  rc = posix_fallocate(-1, 0, 4096);
  saved = errno;
  printf("1 %d %d\n", rc == EBADF, saved == 12345);

  /* Same call, Linux contract. */
  errno = 0;
  rc = fallocate(-1, 0, 0, 4096);
  printf("2 %d %d\n", rc, errno == EBADF);

  /* A negative length is EINVAL, and it is a DIFFERENT number -- an
     implementation that returned EBADF for everything passes row 1 and fails
     here. */
  fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
  if (fd < 0) { printf("open failed %d\n", errno); return 1; }
  rc = posix_fallocate(fd, 0, -1);
  printf("3 %d\n", rc == EINVAL);

  /* The success path. EOPNOTSUPP is a legitimate answer from a filesystem that
     does not implement it; -1 never is. */
  errno = 0;
  rc = posix_fallocate(fd, 0, 4096);
  printf("4 %d\n", rc == 0 || rc == EOPNOTSUPP);
  if (rc == 0) {
    if (fstat(fd, &st) != 0) { printf("fstat failed\n"); return 1; }
    printf("5 %d\n", (long)st.st_size == 4096L);
  } else {
    printf("5 1\n");
  }

  close(fd);
  unlink(path);
  return 0;
}

/* read / write / close / lseek — the four most basic POSIX calls, which were
 * DECLARED by <unistd.h> and implemented nowhere until 2026-08-05. Every C
 * program doing raw file I/O therefore imported them from glibc and stopped
 * being statically linked; it worked on a glibc host, which is why nothing
 * noticed. Found by probing every crtl declaration for an implementation
 * (bug-b-crtl-basic-posix-io-not-implemented).
 *
 * Whole output diffed against a gcc build of this file — no recorded
 * expectations. The cases are the ones where a plausible wrong implementation
 * differs from a right one:
 *
 *   lseek returns the NEW ABSOLUTE offset, not the delta, and for SEEK_END with
 *     a positive offset that is past the end of the file (legal: a hole)
 *   read at EOF returns 0, not -1
 *   a short read returns what it got rather than blocking or failing
 *   read/write/lseek/close on a bad fd return -1 and set errno to EBADF
 */
#include <unistd.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

int main(void) {
  const char *path = "/tmp/pxx_cposix_io.txt";
  char buf[32];
  int fd;
  ssize_t n;
  off_t off;

  unlink(path);
  fd = open(path, O_CREAT | O_RDWR | O_TRUNC, 0644);
  printf("open=%d\n", fd >= 0);

  n = write(fd, "hello world", 11);
  printf("write=%d\n", (int)n);

  /* lseek reports the new ABSOLUTE position */
  off = lseek(fd, 0, SEEK_CUR);  printf("cur=%d\n", (int)off);
  off = lseek(fd, 0, SEEK_SET);  printf("set0=%d\n", (int)off);
  off = lseek(fd, 6, SEEK_SET);  printf("set6=%d\n", (int)off);

  memset(buf, 0, sizeof buf);
  n = read(fd, buf, sizeof buf - 1);
  printf("read_tail=%d [%s]\n", (int)n, buf);

  /* at EOF read gives 0, not -1 */
  n = read(fd, buf, sizeof buf - 1);
  printf("read_eof=%d\n", (int)n);

  off = lseek(fd, 0, SEEK_END);  printf("end=%d\n", (int)off);
  /* past the end is legal and does not extend the file */
  off = lseek(fd, 5, SEEK_END);  printf("past_end=%d\n", (int)off);

  /* a short read returns what there is */
  lseek(fd, 9, SEEK_SET);
  memset(buf, 0, sizeof buf);
  n = read(fd, buf, sizeof buf - 1);
  printf("short=%d [%s]\n", (int)n, buf);

  printf("close=%d\n", close(fd));

  /* Every one of them rejects a closed fd the same way.
     NOTE each call is SEQUENCED before the printf that reports errno. Writing
     `printf("...", close(fd), errno == EBADF)` reads errno and calls close in
     the same argument list, where the evaluation order is unspecified — gcc
     read errno first and pxx-on-arm called close first, and both are right.
     That produced a target-dependent difference with nothing wrong in the
     code, which is a trap worth not re-laying. */
  errno = 0; n = read(fd, buf, 1);
  printf("read_bad=%d %d\n", (int)n, errno == EBADF);
  errno = 0; n = write(fd, "x", 1);
  printf("write_bad=%d %d\n", (int)n, errno == EBADF);
  errno = 0; off = lseek(fd, 0, SEEK_SET);
  printf("lseek_bad=%d %d\n", (int)off, errno == EBADF);
  errno = 0; { int rc = close(fd);
  printf("close_bad=%d %d\n", rc, errno == EBADF); }

  unlink(path);
  return 0;
}

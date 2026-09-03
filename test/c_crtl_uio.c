/* crtl: <sys/uio.h> -- readv/writev/preadv/pwritev, and the NORMALISATION of
 * `struct iovec' onto a single definition site.
 *
 * struct iovec HAD TWO HOMES. <sys/socket.h> declared its own copy because
 * msghdr needs it; <sys/uio.h> did not exist. Two definitions of one struct do
 * not fail to compile -- they fail when they DRIFT, and this one is two
 * pointer-sized fields, which is exactly the shape where a `void *' vs
 * `char *' or a `size_t' vs `int' costs nothing on x86-64 and costs everything
 * on i386. sys/socket.h now includes this header; row 1 is the sizeof that
 * would catch the drift if the copy ever came back.
 *
 * ROW 3 IS preadv AT AN OFFSET AND IT IS THE ROW THAT PAYS ON i386: the
 * syscall takes the offset as TWO longs, lo then hi, so a 32-bit build that
 * passes one long compiles, links, runs, and reads from offset 0 -- returning
 * real bytes from the right file, just the wrong ones. Reading "world" rather
 * than "hello" is the whole assertion.
 *
 * Rows 1-4 diffed against gcc/glibc.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/uio.h>

int main(void)
{
  char path[512];
  const char *dir;
  struct iovec wv[3], rv[3];
  char a[8], b[8], c[8], one[8];
  int fd;
  ssize_t n;

  /* The scratch file goes in the RUN'S directory, not the shared /tmp.
   * mkstemp already makes the NAME unique, so this is not about two runs
   * colliding on a filename -- it is about the DIRECTORY: a file written
   * outside $TESTMGR_TMP is one testmgr did not create and does not clean up,
   * and on a box where /tmp is small, read-only or not the tmpdir, this test
   * fails for a reason that has nothing to do with readv/writev.
   * TESTMGR_TMP first: testmgr launches jobs through an environment allowlist
   * (PXX_/TESTMGR_/LC_/QEMU_), so $TESTTMP alone does not reach the job and
   * would silently fall back to the shared path. TESTTMP second, for
   * `make test TESTTMP=$(mktemp -d)`. The bare-run default keeps the old
   * behaviour byte-identical. */
  dir = getenv("TESTMGR_TMP");
  if (!dir) dir = getenv("TESTTMP");
  if (!dir) dir = "/tmp";
  snprintf(path, sizeof path, "%s/%s", dir, "pxx_uio_XXXXXX");

  printf("1 %d %d\n", (int)sizeof(struct iovec), (int)UIO_MAXIOV / 64);

  fd = mkstemp(path);
  if (fd < 0) { printf("mkstemp failed\n"); return 1; }

  wv[0].iov_base = (void *)"hello";  wv[0].iov_len = 5;
  wv[1].iov_base = (void *)" wo";    wv[1].iov_len = 3;
  wv[2].iov_base = (void *)"rld!";   wv[2].iov_len = 4;
  n = writev(fd, wv, 3);
  lseek(fd, 0, SEEK_SET);

  memset(a, 0, sizeof a); memset(b, 0, sizeof b); memset(c, 0, sizeof c);
  rv[0].iov_base = a;  rv[0].iov_len = 5;
  rv[1].iov_base = b;  rv[1].iov_len = 3;
  rv[2].iov_base = c;  rv[2].iov_len = 4;
  readv(fd, rv, 3);
  printf("2 %d [%s][%s][%s]\n", (int)n, a, b, c);

  /* preadv at 6: "world" -- NOT at 0, which would read "hello". */
  memset(one, 0, sizeof one);
  rv[0].iov_base = one;  rv[0].iov_len = 5;
  n = preadv(fd, rv, 1, 6);
  printf("3 %d [%s]\n", (int)n, one);

  /* pwritev at 6 leaves the head alone. */
  wv[0].iov_base = (void *)"WORLD";  wv[0].iov_len = 5;
  pwritev(fd, wv, 1, 6);
  memset(a, 0, sizeof a);
  rv[0].iov_base = a;  rv[0].iov_len = 5;
  pread(fd, a, 5, 0);
  memset(b, 0, sizeof b);
  pread(fd, b, 5, 6);
  printf("4 [%s][%s]\n", a, b);

  close(fd);
  unlink(path);
  return 0;
}

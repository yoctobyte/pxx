/* crtl: the terminal foreground-pgrp pair and statfs(2).
 *
 * Both are gaps busybox walked into: getty.c calls tcsetpgrp, switch_root.c
 * and df call statfs. Neither is exercised by anything else in the tree.
 *
 * The tty rows deliberately run on a PIPE, not a terminal. A test that needs a
 * controlling terminal does not run under the harness, and the error path is
 * the half that is easy to get wrong anyway: both calls move the pgrp through
 * a POINTER, so the plausible-looking `(void *)(long)pgrp' spelling hands the
 * kernel an address and fails with EFAULT or, worse, succeeds against some
 * other process group. ENOTTY on a pipe is the answer that says the ioctl was
 * assembled correctly and the kernel rejected it for the right reason.
 */
#include <stdio.h>
#include <termios.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <fcntl.h>
#include <sys/statfs.h>

int main(void)
{
  int fds[2];
  pid_t g;
  int rc;
  struct statfs sb;
  struct statfs sb2;
  int fd;

  if (pipe(fds) != 0) { printf("pipe failed\n"); return 1; }

  errno = 0;
  g = tcgetpgrp(fds[0]);
  rc = (g == (pid_t)-1);
  printf("1 %d %d\n", rc, errno == ENOTTY);

  errno = 0;
  rc = tcsetpgrp(fds[0], (pid_t)1);
  printf("2 %d %d\n", rc, errno == ENOTTY);

  /* A closed/invalid fd is a different errno, which is what tells the two
     failure modes apart -- an implementation that returned -1/ENOTTY for
     everything would pass row 1 and 2 and fail here. */
  errno = 0;
  g = tcgetpgrp(-1);
  printf("3 %d %d\n", g == (pid_t)-1, errno == EBADF);

  /* statfs: the absolute numbers are the machine's, so nothing here compares
     them across runs. What IS comparable is the relationship the kernel
     guarantees, and a struct whose fields land at the wrong offsets breaks
     every one of these at once. */
  if (statfs("/", &sb) != 0) { printf("statfs / failed %d\n", errno); return 1; }
  printf("4 %d %d %d\n",
         sb.f_bsize > 0,
         sb.f_blocks >= sb.f_bfree,
         sb.f_bfree >= sb.f_bavail);
  printf("5 %d\n", sb.f_namelen > 0 && sb.f_namelen <= 4096);

  /* fstatfs on an fd open on / must describe the same filesystem. f_type and
     f_fsid together are the identity; f_bfree can move between the two calls
     and is deliberately not compared. */
  fd = open("/", O_RDONLY, 0);
  if (fd < 0) { printf("open / failed\n"); return 1; }
  if (fstatfs(fd, &sb2) != 0) { printf("fstatfs failed %d\n", errno); return 1; }
  printf("6 %d %d\n", sb2.f_type == sb.f_type, sb2.f_bsize == sb.f_bsize);

  errno = 0;
  rc = statfs("/nonexistent-crtl-probe", &sb2);
  printf("7 %d %d\n", rc, errno == ENOENT);
  return 0;
}

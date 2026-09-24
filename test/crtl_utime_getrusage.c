/* utime() and getrusage(), both added for sqlite's shell.c (which includes
 * <utime.h> for .archive and times every statement with getrusage).
 *
 * utime: set a file's times to fixed values, read them back with stat, then
 * NULL means "now" -- checked as "moved forward", not as a value.
 * getrusage: the struct is the kernel's own layout, so a wrong width shows up
 * as garbage in a field after the two timevals; ru_maxrss of a running process
 * is never 0, and an invalid `who' is EINVAL. Values are gcc's. */
#include <stdio.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/resource.h>
#include <utime.h>
#include <fcntl.h>
#include <unistd.h>

int main(int argc, char **argv) {
  const char *path = argc > 1 ? argv[1] : "crtl_utime_probe.tmp";
  struct utimbuf ub;
  struct stat st;
  struct rusage ru;
  int rc;
  int fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, 0644);
  if (fd < 0) { printf("open failed\n"); return 1; }
  close(fd);
  ub.actime = 1000000000; ub.modtime = 1234567890;
  printf("utime %d\n", utime(path, &ub));
  stat(path, &st);
  printf("atime %ld mtime %ld\n", (long)st.st_atime, (long)st.st_mtime);
  printf("utime-now %d\n", utime(path, NULL));
  stat(path, &st);
  printf("moved %d\n", (long)st.st_mtime > 1234567890L);
  rc = utime("/nonexistent/x", &ub);      /* sequenced: printf's argument */
  printf("utime-missing %d errno-ENOENT %d\n", rc, errno == ENOENT);   /* order is unspecified */
  unlink(path);
  printf("getrusage %d\n", getrusage(RUSAGE_SELF, &ru));
  printf("maxrss>0 %d utime-usec-ok %d\n", ru.ru_maxrss > 0, ru.ru_utime.tv_usec >= 0 && ru.ru_utime.tv_usec < 1000000);
  errno = 0;
  rc = getrusage(12345, &ru);
  printf("bad-who %d einval %d\n", rc, errno == EINVAL);
  return 0;
}

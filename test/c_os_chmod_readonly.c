/* chmod's write bits under --os=nt (compiler/builtin/winabi.pas: the
   read-only attribute) and on Linux alike: no write bit makes a file read-only
   (stat says 0444, opening it for writing fails with EACCES), a write bit
   makes it writable again. Run as an ordinary user on Linux: root may write
   a 0444 file. */
#include <stdio.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
int main(void) {
  const char *path = "c_os_chmod_readonly.tmp";
  struct stat st;
  int fd;
  fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) { printf("create failed\n"); return 1; }
  close(fd);
  printf("chmod 0444: %d\n", chmod(path, 0444));
  stat(path, &st);
  printf("mode %o\n", st.st_mode & 0777);
  fd = open(path, O_WRONLY);
  printf("open for writing: %s\n", fd < 0 ? (errno == EACCES ? "EACCES" : "other error") : "opened");
  if (fd >= 0) close(fd);
  printf("chmod 0644: %d\n", chmod(path, 0644));
  stat(path, &st);
  printf("mode %o\n", st.st_mode & 0777);
  fd = open(path, O_WRONLY);
  printf("open for writing: %s\n", fd < 0 ? "failed" : "opened");
  if (fd >= 0) close(fd);
  fd = chmod("no-such-file.tmp", 0644);
  printf("missing: %d %s\n", fd, errno == ENOENT ? "ENOENT" : "other");
  unlink(path);
  return 0;
}

/* Symbolic links under --os=nt (compiler/builtin/winabi.pas: CreateSymbolicLinkW
   and the reparse point) and on Linux alike: symlink, readlink, lstat sees a
   link and stat its target, reading through it, a link to a directory, unlink
   removes only the link, EEXIST on an existing name. A Windows without the
   privilege says EPERM; this test then says so and stops. */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
int main(void) {
  char b[256]; struct stat st; int fd, n, r;
  mkdir("c_os_symlink.d", 0755);
  fd = open("c_os_symlink.d/target.txt", O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) { printf("create failed\n"); return 1; }
  write(fd, "hello", 5); close(fd);
  r = symlink("c_os_symlink.d/target.txt", "c_os_symlink.lnk");
  if (r != 0 && errno == EPERM) { printf("no symlink privilege\n"); return 0; }
  printf("symlink %d\n", r);
  n = readlink("c_os_symlink.lnk", b, sizeof b - 1);
  if (n >= 0) b[n] = 0;
  printf("readlink %d %s\n", n, n >= 0 ? b : "-");
  r = lstat("c_os_symlink.lnk", &st);
  printf("lstat %d link %d size %d\n", r, S_ISLNK(st.st_mode), (int)st.st_size);
  r = stat("c_os_symlink.lnk", &st);
  printf("stat %d regular %d size %d\n", r, S_ISREG(st.st_mode), (int)st.st_size);
  fd = open("c_os_symlink.lnk", O_RDONLY);
  n = fd >= 0 ? (int)read(fd, b, 5) : -1;
  if (fd >= 0) close(fd);
  printf("read through %d %.5s\n", n, n > 0 ? b : "-");
  r = symlink("c_os_symlink.d", "c_os_symlink.dlnk");
  printf("dir symlink %d\n", r);
  r = stat("c_os_symlink.dlnk", &st);
  printf("stat dir %d isdir %d\n", r, S_ISDIR(st.st_mode));
  r = lstat("c_os_symlink.dlnk", &st);
  printf("lstat dir link %d\n", S_ISLNK(st.st_mode));
  fd = open("c_os_symlink.dlnk/target.txt", O_RDONLY);
  printf("open through dir link %d\n", fd >= 0);
  if (fd >= 0) close(fd);
  r = symlink("x", "c_os_symlink.lnk");
  printf("again: %d %s\n", r, errno == EEXIST ? "EEXIST" : "other");
  r = readlink("c_os_symlink.d/target.txt", b, sizeof b);
  printf("readlink of a file: %d %s\n", r, errno == EINVAL ? "EINVAL" : "other");
  printf("unlink link %d\n", unlink("c_os_symlink.lnk"));
  printf("unlink dir link %d\n", unlink("c_os_symlink.dlnk"));
  printf("target still there %d\n", access("c_os_symlink.d/target.txt", F_OK) == 0);
  unlink("c_os_symlink.d/target.txt");
  rmdir("c_os_symlink.d");
  return 0;
}

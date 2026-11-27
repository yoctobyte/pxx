/* shm_open/shm_unlink and F_DUPFD_CLOEXEC (crtl lacked both; wlroots uses
   them for wl_shm pools and dmabuf fds), under _POSIX_C_SOURCE as wlroots
   compiles, compared with gcc + glibc. feature-crtl-wlroots-gaps */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>

static void try_name(const char *label, const char *name) {
  int fd;
  errno = 0;
  fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
  printf("name %s: %s\n", label, fd >= 0 ? "ok" : (errno == EINVAL ? "EINVAL" : errno == ENAMETOOLONG ? "ENAMETOOLONG" : "other"));
  if (fd >= 0) { close(fd); shm_unlink(name); }
}

int main(void) {
  char name[64], longname[300];
  int fd, fd2, fdx;
  struct stat st;
  char buf[6] = {0};
  void *p;

  printf("F_DUPFD_CLOEXEC %d\n", F_DUPFD_CLOEXEC);

  snprintf(name, sizeof name, "/c_shm_open_dupfd-%ld", (long)getpid());
  fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
  printf("open %d cloexec %d\n", fd >= 0, fd >= 0 && (fcntl(fd, F_GETFD) & FD_CLOEXEC) != 0);
  printf("ftruncate %d\n", ftruncate(fd, 4096));
  p = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  printf("mmap %d\n", p != MAP_FAILED);
  memcpy(p, "hello", 5);
  fdx = shm_open(name + 1, O_RDONLY, 0);      /* the name without its '/' is the same object */
  printf("reopen %d read %d '%s'\n", fdx >= 0, (int)read(fdx, buf, 5), buf);
  fstat(fdx, &st);
  printf("size %ld mode %o\n", (long)st.st_size, (unsigned)(st.st_mode & 0777));
  errno = 0;
  fd2 = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
  printf("excl again %d EEXIST %d\n", fd2, errno == EEXIST);

  fd2 = fcntl(fd, F_DUPFD_CLOEXEC, 100);
  printf("dupfd_cloexec >=100 %d cloexec %d\n", fd2 >= 100, (fcntl(fd2, F_GETFD) & FD_CLOEXEC) != 0);
  fd2 = fcntl(fd, F_DUPFD, 100);
  printf("dupfd cloexec %d\n", (fcntl(fd2, F_GETFD) & FD_CLOEXEC) != 0);

  printf("unlink %d\n", shm_unlink(name));
  errno = 0;
  fd2 = shm_unlink(name);
  printf("unlink again %d ENOENT %d\n", fd2, errno == ENOENT);
  errno = 0;
  fd2 = shm_open(name, O_RDONLY, 0);
  printf("open gone %d ENOENT %d\n", fd2, errno == ENOENT);

  try_name("empty", "");
  try_name("slash-only", "/");
  try_name("inner-slash", "/a/b");
  try_name("double-lead", "//c_shm_open_dupfd-dl");
  memset(longname, 'x', sizeof longname - 1);
  longname[0] = '/';
  longname[sizeof longname - 1] = 0;
  try_name("too-long", longname);
  return 0;
}

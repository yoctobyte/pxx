/* crtl functions e2fsprogs, util-linux and dosfstools need: the LFS64 family
   (off64_t, lseek64, pread64, pwrite64, stat64, fstat64), qsort_r,
   secure_getenv, sbrk, the sized CPU_*_S macros with CPU_ALLOC, _POSIX_VDISABLE
   and <err.h>. Output matches gcc on x86-64 and i386.

   The 3 GiB offset is the point on i386: off_t is 32 bits there, so only a
   real 64-bit path lands the byte where it was asked and reports the size.
   The file is sparse; it occupies one block.

   err/warn print the program's name, which differs between the pxx and gcc
   binaries, so a child writes them into a pipe and the parent checks the
   prefix against its own argv[0] and prints the rest.
   feature-crtl-runtime-gaps-from-e2fsprogs-util-linux-dosfstools */
#define _GNU_SOURCE
#define _LARGEFILE64_SOURCE
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

static int by_dir(const void *a, const void *b, void *arg)
{
  int x = *(const int *)a, y = *(const int *)b, dir = *(int *)arg;
  return dir * ((x > y) - (x < y));
}

static void lfs(void)
{
  char path[64], c = 0;
  int fd, rc;
  off64_t big = (off64_t)3 * 1024 * 1024 * 1024 + 5, pos;
  struct stat64 st, fst;
  snprintf(path, sizeof path, "/tmp/pxx_lfs_%d", (int)getpid());
  fd = open64(path, O_CREAT | O_RDWR | O_TRUNC, 0600);   /* O_LARGEFILE on ILP32 */
  if (fd < 0) { printf("open failed\n"); return; }
  printf("pwrite64 %d\n", (int)pwrite64(fd, "Z", 1, big));
  printf("pread64 %d", (int)pread64(fd, &c, 1, big));
  printf(" %c\n", c);
  pos = lseek64(fd, 0, SEEK_END);
  printf("lseek64 end %lld\n", (long long)pos);
  pos = lseek64(fd, big - 1, SEEK_SET);
  printf("lseek64 set %lld\n", (long long)pos);
  rc = stat64(path, &st);          /* sequenced: argument order is unspecified */
  printf("stat64 %d %lld\n", rc, (long long)st.st_size);
  rc = fstat64(fd, &fst);
  printf("fstat64 %d %lld %d\n", rc, (long long)fst.st_size, S_ISREG(fst.st_mode) ? 1 : 0);
  printf("sizeof off64_t %d\n", (int)sizeof(off64_t));
  close(fd);
  unlink(path);
}

static void gnu(void)
{
  int v[6] = {4, 1, 5, 9, 2, 6}, i, up = 1, down = -1;
  cpu_set_t *set;
  size_t sz;
  char *b0, *b1;
  qsort_r(v, 6, sizeof v[0], by_dir, &up);
  for (i = 0; i < 6; i++) printf("%d ", v[i]);
  qsort_r(v, 6, sizeof v[0], by_dir, &down);
  for (i = 0; i < 6; i++) printf("%d ", v[i]);
  printf("\n");

  setenv("PXX_GAPS_PROBE", "here", 1);
  printf("secure_getenv %s\n", secure_getenv("PXX_GAPS_PROBE") ? secure_getenv("PXX_GAPS_PROBE") : "(null)");

  b0 = sbrk(0);
  b1 = sbrk(4096);
  printf("sbrk %d %d", b0 != (char *)-1 && b0 == b1, (char *)sbrk(0) == b0 + 4096);
  printf(" %d\n", sbrk(-4096) == b0 + 4096 && (char *)sbrk(0) == b0);

  set = CPU_ALLOC(200);
  sz = CPU_ALLOC_SIZE(200);
  CPU_ZERO_S(sz, set);
  CPU_SET_S(3, sz, set);
  CPU_SET_S(130, sz, set);
  CPU_SET_S(5000, sz, set);       /* outside the set: ignored */
  printf("cpu %d %d %d %d %d %d\n", (int)sz, CPU_ISSET_S(3, sz, set), CPU_ISSET_S(4, sz, set),
         CPU_ISSET_S(130, sz, set), CPU_ISSET_S(5000, sz, set), CPU_COUNT_S(sz, set));
  CPU_CLR_S(3, sz, set);
  printf("cpu-clr %d %d\n", CPU_ISSET_S(3, sz, set), CPU_COUNT_S(sz, set));
  CPU_FREE(set);

  printf("vdisable %d\n", (int)_POSIX_VDISABLE);
}

static void errs(const char *argv0)
{
  int p[2], st = 0, n, i;
  char buf[512], prog[256];
  const char *base = strrchr(argv0, '/');
  pid_t pid;
  base = base ? base + 1 : argv0;
  snprintf(prog, sizeof prog, "%s: ", base);
  fflush(stdout);
  if (pipe(p) != 0) return;
  pid = fork();
  if (pid == 0) {
    close(p[0]);
    dup2(p[1], 2);
    errno = ENOENT;
    warn("open %s", "nowhere");
    warnx("count %d", 3);
    errno = EACCES;
    warn(NULL);
    errx(3, "giving up after %s", "warnx");
  }
  close(p[1]);
  n = 0;
  while (n < (int)sizeof buf - 1) {
    int r = (int)read(p[0], buf + n, sizeof buf - 1 - n);
    if (r <= 0) break;
    n += r;
  }
  buf[n] = 0;
  close(p[0]);
  waitpid(pid, &st, 0);
  /* each line: check and strip the "prog: " prefix */
  i = 0;
  while (buf[i]) {
    char *nl = strchr(buf + i, '\n');
    int len = nl ? (int)(nl - (buf + i)) : (int)strlen(buf + i);
    int pl = (int)strlen(prog);
    if (len >= pl && strncmp(buf + i, prog, pl) == 0)
      printf("err-line [%.*s]\n", len - pl, buf + i + pl);
    else
      printf("err-line WITHOUT PREFIX [%.*s]\n", len, buf + i);
    i += len + (nl ? 1 : 0);
  }
  printf("errx status %d\n", WIFEXITED(st) ? WEXITSTATUS(st) : -1);
}

int main(int argc, char **argv)
{
  (void)argc;
  lfs();
  gnu();
  errs(argv[0]);
  return 0;
}

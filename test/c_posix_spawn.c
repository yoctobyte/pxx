/* posix_spawn / posix_spawnp (crtl's spawn.c), initstate/setstate, fgetpos,
   closefrom and memset_explicit, the libc gaps dhcpcd 10.5.2 found (Nodisx).
   Prints the same under gcc/glibc and pxx. */
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>

extern char **environ;

static int run(int usepath, const char *file, char *const argv[],
               posix_spawn_file_actions_t *fa, posix_spawnattr_t *at)
{
  pid_t pid = -1;
  int st, r;
  fflush(stdout);
  r = usepath ? posix_spawnp(&pid, file, fa, at, argv, environ)
              : posix_spawn(&pid, file, fa, at, argv, environ);
  if (r != 0) return -r;
  if (waitpid(pid, &st, 0) != pid) return -1000;
  return WIFEXITED(st) ? WEXITSTATUS(st) : 200 + WTERMSIG(st);
}

int main(void)
{
  char *a1[] = { "sh", "-c", "exit 7", NULL };
  char *a2[] = { "sh", "-c", "echo to-file", NULL };
  char *a3[] = { "sh", "-c", "kill -USR1 $$; echo survived", NULL };
  char *a4[] = { "nope", NULL };
  char path[] = "/tmp/pxx_spawn_XXXXXX";
  posix_spawn_file_actions_t fa;
  posix_spawnattr_t at;
  sigset_t s;
  char buf[64];
  int fd, n, r;
  char st1[128], st2[128], *prev;
  long x1, x2, y1;
  FILE *f;
  fpos_t pos;
  char word[16];
  char key[8] = "secret!";

  printf("exit status %d\n", run(0, "/bin/sh", a1, NULL, NULL));
  printf("spawnp status %d\n", run(1, "sh", a1, NULL, NULL));
  r = run(0, "/nonexistent/prog", a4, NULL, NULL);
  printf("missing: %s\n", r == -ENOENT ? "ENOENT" : "other");
  r = run(1, "no-such-program-pxx", a4, NULL, NULL);
  printf("missing via PATH: %s\n", r == -ENOENT ? "ENOENT" : "other");

  /* file actions: stdout to a file */
  fd = mkstemp(path);
  close(fd);
  posix_spawn_file_actions_init(&fa);
  posix_spawn_file_actions_addopen(&fa, 1, path, O_WRONLY | O_TRUNC, 0600);
  printf("redirected status %d\n", run(0, "/bin/sh", a2, &fa, NULL));
  posix_spawn_file_actions_destroy(&fa);
  fd = open(path, O_RDONLY);
  n = (int)read(fd, buf, sizeof buf - 1);
  close(fd);
  buf[n > 0 ? n : 0] = 0;
  printf("file got: %s", buf);

  /* an open failure is the return value */
  posix_spawn_file_actions_init(&fa);
  posix_spawn_file_actions_addopen(&fa, 1, "/nonexistent/dir/x", O_RDONLY, 0);
  r = run(0, "/bin/sh", a2, &fa, NULL);
  printf("open action: %s\n", r == -ENOENT ? "ENOENT" : "other");
  posix_spawn_file_actions_destroy(&fa);

  /* SETSIGDEF: the child's USR1 is default (fatal) though the parent ignores it */
  signal(SIGUSR1, SIG_IGN);
  printf("ignored usr1 status %d\n", run(0, "/bin/sh", a3, NULL, NULL));
  posix_spawnattr_init(&at);
  sigemptyset(&s);
  sigaddset(&s, SIGUSR1);
  posix_spawnattr_setsigdefault(&at, &s);
  posix_spawnattr_setflags(&at, POSIX_SPAWN_SETSIGDEF);
  printf("sigdef usr1 status %d\n", run(0, "/bin/sh", a3, NULL, &at));
  posix_spawnattr_destroy(&at);

  /* initstate/setstate: two streams, switched; the same seed repeats */
  initstate(42, st1, sizeof st1);
  x1 = random();
  prev = initstate(42, st2, sizeof st2);
  y1 = random();
  setstate(prev);
  x2 = random();
  printf("random streams: same seed %d, continue differs %d\n", x1 == y1, x2 != x1);

  /* fgetpos/fsetpos */
  f = fopen(path, "r");
  fgetc(f); fgetc(f);
  fgetpos(f, &pos);
  fscanf(f, "%15s", word);
  fsetpos(f, &pos);
  fscanf(f, "%15s", word);
  printf("fsetpos read: %s\n", word);
  fclose(f);
  unlink(path);

  /* closefrom */
  fd = open("/dev/null", O_RDONLY);
  dup2(fd, 40);
  closefrom(40);
  printf("closefrom: fd 40 %s, fd %d %s\n", fcntl(40, F_GETFD) < 0 ? "closed" : "open",
         fd, fcntl(fd, F_GETFD) < 0 ? "closed" : "open");

  memset_explicit(key, 0, sizeof key);
  printf("wiped %d\n", key[0] == 0 && key[6] == 0);
  return 0;
}

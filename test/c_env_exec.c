/* setenv/putenv/unsetenv/clearenv reach a child started with exec*, and
   `environ` walks the same environment. Run under
     env -i KEEP=k DROP=d BIG=<20000 x> ./c_env_exec
   (BIG overflows crtl's 16K buffer: a write must not lose it for the child).
   bug-crtl-setenv-and-putenv-did-not-reach-an-execd-child */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
extern char **environ;

static void child(const char *what, const char *script) {
  pid_t p;
  int st;
  fflush(stdout);
  p = fork();
  if (p == 0) {
    char *argv[4];
    argv[0] = "sh"; argv[1] = "-c"; argv[2] = (char *)script; argv[3] = 0;
    if (what[0] == 'v') execvp("sh", argv);
    else execl("/bin/sh", "sh", "-c", script, (char *)0);
    _exit(127);
  }
  waitpid(p, &st, 0);
}

int main(void) {
  char **e;
  int n = 0, sawA = 0, sawDrop = 0;
  putenv("A=putenv");
  setenv("B", "setenv", 1);
  setenv("B", "kept", 0);            /* no overwrite: stays "setenv" */
  setenv("KEEP", "replaced", 1);
  unsetenv("DROP");
  for (e = environ; *e; e++) {
    n++;
    if (strcmp(*e, "A=putenv") == 0) sawA = 1;
    if (strncmp(*e, "DROP=", 5) == 0) sawDrop = 1;
  }
  printf("environ A=%d DROP=%d\n", sawA, sawDrop);
  child("l", "echo execl: A=$A B=$B KEEP=$KEEP DROP=${DROP-unset} BIG=${#BIG}");
  child("v", "echo execvp: A=$A B=$B KEEP=$KEEP DROP=${DROP-unset} BIG=${#BIG}");
  clearenv();
  setenv("ONLY", "1", 1);
  setenv("PATH", "/bin:/usr/bin", 1);
  child("l", "echo cleared: A=${A-unset} BIG=${#BIG} ONLY=$ONLY");
  return 0;
}

/* Three crtl gaps GNU make 4.4.1 found when pxx built it (Nodisx):
 * 1. a write that fails (stdout on /dev/full) must show: printf, puts,
 *    putchar and fputs return EOF/-1, ferror() is set, errno says why.
 *    crtl's unbuffered stdout returned the byte count and kept ferror()
 *    clear, so `make -v > /dev/full` exited 0.
 *    bug-c-crtl-printf-reports-success-when-the-write-fails
 * 2. getenv reads `environ` when the program has ASSIGNED it (make does
 *    `environ = envp` before execvp, which finds PATH through getenv).
 *    bug-c-crtl-getenv-ignores-an-assigned-environ
 * 3. <unistd.h> defines _POSIX_VERSION and declares eaccess/euidaccess.
 * Output goes to stderr for part 1 (stdout is the device under test). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

extern char **environ;

int main(void) {
  int fd, saved, r1, r2, r3, r4, f1, e1;
  static char *mine[] = { "PXXT_A=one", "PATH=.", 0 };
  char **old;

  fd = open("/dev/full", O_WRONLY);
  if (fd < 0) { printf("no /dev/full\n"); return 0; }
  saved = dup(1);
  fflush(stdout);
  dup2(fd, 1);
  errno = 0;
  r1 = printf("hello %d\n", 42);
  f1 = ferror(stdout);
  e1 = errno;
  clearerr(stdout);
  r2 = puts("x");
  r3 = putchar('y');
  r4 = fputs("z\n", stdout);
  dup2(saved, 1);
  close(fd);
  clearerr(stdout);
  printf("printf=%d ferror=%d enospc=%d puts=%d putchar=%d fputs=%d\n",
         r1, f1 != 0, e1 == ENOSPC, r2, r3, r4);

  old = environ;
  environ = mine;
  printf("assigned: A=%s PATH=%s\n", getenv("PXXT_A") ? getenv("PXXT_A") : "(null)",
         getenv("PATH") ? getenv("PATH") : "(null)");
  environ = old;
  printf("restored: A=%s\n", getenv("PXXT_A") ? getenv("PXXT_A") : "(null)");
  setenv("PXXT_B", "two", 1);
  printf("setenv: B=%s environ-has-B=%d\n", getenv("PXXT_B"),
         (int)(environ && getenv("PXXT_B") != 0));

#ifdef _POSIX_VERSION
  printf("_POSIX_VERSION>=200112: %d\n", _POSIX_VERSION >= 200112L);
#else
  printf("_POSIX_VERSION missing\n");
#endif
  printf("eaccess(/,X_OK)=%d eaccess(missing)=%d\n", eaccess("/", X_OK),
         eaccess("/nonexistent-pxx-probe", F_OK));
  return 0;
}

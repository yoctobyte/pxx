/* Process/user ids, pipe, kill, sleep, getpagesize
 * (feature-crtl-implement-libc-assumptions, round 7).
 *
 * geteuid was present; getuid/getgid/getegid/getppid were not — so code
 * branching on getuid() == 0 to ask "am I root" would not have compiled at all,
 * and once it did, must not answer 0 for everyone. pipe and kill had PAL
 * primitives (PalPipe2, PalKill) with no bridge; sleep/usleep are built on the
 * nanosleep crtl already had.
 *
 * Behavioural: the pipe must move bytes, and kill(pid, 0) must distinguish a
 * live process from an absent one — a stub returning 0 would pass a
 * "did it return success" test. Whole output diffed against gcc.
 *
 * uid_nonzero assumes the suite does not run as root, which is also what the
 * existing lib-test entries assume.
 */
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
int main(void) {
  int fds[2]; char b[8]; long n;
  printf("uid_eq_euid=%d gid_eq_egid=%d\n", getuid() == geteuid(), getgid() == getegid());
  printf("uid_nonzero=%d gid_nonzero=%d\n", getuid() != 0, getgid() != 0);
  printf("pid_positive=%d ppid_positive=%d\n", getpid() > 0, getppid() > 0);
  printf("pid_ne_ppid=%d\n", getpid() != getppid());
  printf("pagesize=%d\n", getpagesize());
  /* pipe must actually move bytes */
  printf("pipe=%d\n", pipe(fds) == 0);
  write(fds[1], "hi", 2);
  memset(b, 0, sizeof b);
  n = read(fds[0], b, 2);
  printf("pipe_moves=%ld [%s]\n", n, b);
  close(fds[0]); close(fds[1]);
  /* kill with signal 0 probes existence without sending anything */
  printf("kill0_self=%d\n", kill(getpid(), 0) == 0);
  printf("kill0_absent=%d\n", kill(999999, 0) != 0);
  printf("sleep0=%d usleep0=%d\n", sleep(0), usleep(1000));
  return 0;
}

/* SPDX-License-Identifier: Zlib */
/*
 * crtl: sigprocmask / sigtimedwait / sigwait and wait4 / wait3.
 *
 * ONE FILE BECAUSE ONE MECHANISM: all five are the "block it, then collect it"
 * half of process control, and all five were stubs or absent when busybox's
 * init/init.c and miscutils/time.c were attempted.
 *
 * sigprocmask USED TO RETURN 0 AND DO NOTHING, which is why row 3 exists and
 * row 1 is not enough: a no-op passes every check that only reads the return
 * value. Rows 2-4 read the mask back out and prove SIGUSR1 went in and SIGUSR2
 * did not. That is the positive control for the whole file -- with a fake
 * sigprocmask the kill in row 5 kills the process instead, so rows 6 onward
 * never print at all, which is a failure the harness sees as a short output.
 *
 * WHY sigtimedwait WORKS WHILE sigaction DOES NOT: waiting needs no handler
 * and no arch-specific return trampoline. A blocked signal stays pending and
 * the kernel hands it back. Nothing here installs a handler.
 *
 * Every read is sequenced into its own statement before it is printed. An
 * argument list has no evaluation order, and three bogus oracle rows in this
 * corpus were produced by forgetting that.
 *
 * Every row was diffed against glibc by compiling this same file with gcc.
 * feature-c-corpus-busybox-multi-applet
 */
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <sys/wait.h>
#include <sys/resource.h>

int main(void) {
  sigset_t s, old, chk;
  struct timespec ts;
  struct rusage ru;
  pid_t p, r;
  int rc, sig, e, st;
  sigemptyset(&s);
  sigaddset(&s, SIGUSR1);
  rc = sigprocmask(SIG_BLOCK, &s, &old);
  printf("1 %d\n", rc);

  /* the mask really took: SIGUSR1 blocked, SIGUSR2 not. This is the positive
     control -- a sigprocmask that returned 0 and did nothing passes row 1. */
  sigemptyset(&chk);
  rc = sigprocmask(SIG_BLOCK, 0, &chk);
  printf("2 %d\n", rc);
  rc = sigismember(&chk, SIGUSR1);
  printf("3 %d\n", rc);
  rc = sigismember(&chk, SIGUSR2);
  printf("4 %d\n", rc);

  /* blocked, so it stays pending rather than killing us. */
  rc = kill(getpid(), SIGUSR1);
  printf("5 %d\n", rc);

  ts.tv_sec = 1; ts.tv_nsec = 0;
  rc = sigtimedwait(&s, 0, &ts);
  printf("6 %d\n", rc);

  /* nothing pending now: the same wait must time out with EAGAIN. */
  ts.tv_sec = 0; ts.tv_nsec = 20000000;
  rc = sigtimedwait(&s, 0, &ts);
  e = errno;
  printf("7 %d %d\n", rc, rc < 0 ? e == EAGAIN : -1);

  /* sigwait: positive-errno convention, reports through *sig. */
  rc = kill(getpid(), SIGUSR1);
  printf("8 %d\n", rc);
  sig = -1;
  rc = sigwait(&s, &sig);
  printf("9 %d %d\n", rc, sig);

  rc = sigprocmask(SIG_SETMASK, &old, 0);
  printf("10 %d\n", rc);
  sigemptyset(&chk);
  rc = sigprocmask(SIG_BLOCK, 0, &chk);
  printf("11 %d\n", rc);
  rc = sigismember(&chk, SIGUSR1);
  printf("12 %d\n", rc);

  /* a bad `how' is EINVAL from the kernel, not silently accepted. */
  rc = sigprocmask(12345, &s, 0);
  e = errno;
  printf("13 %d %d\n", rc, rc < 0 ? e == EINVAL : -1);

  p = fork();
  if (p == 0) { _exit(7); }
  printf("14 %d\n", p > 0);
  /* Each read sequenced on its own: an argument list has no evaluation order. */
  r = wait4(p, &st, 0, &ru);
  printf("15 %d\n", r == p);
  rc = WIFEXITED(st);
  printf("16 %d\n", rc);
  rc = WEXITSTATUS(st);
  printf("17 %d\n", rc);
  /* ru was written -- ru_maxrss is the field that cannot legitimately be 0 for
     a process that ran at all. This is the positive control on the fourth
     argument actually reaching the kernel. */
  printf("18 %d\n", ru.ru_maxrss > 0);

  p = fork();
  if (p == 0) { _exit(3); }
  printf("19 %d\n", p > 0);
  r = wait3(&st, 0, &ru);
  printf("20 %d\n", r == p);
  rc = WEXITSTATUS(st);
  printf("21 %d\n", rc);

  /* Nothing left to reap: ECHILD from the kernel, not an invention. */
  r = wait4(-1, &st, 0, 0);
  rc = errno;
  printf("22 %d %d\n", (int)r, r < 0 ? rc == ECHILD : -1);
  return 0;
}

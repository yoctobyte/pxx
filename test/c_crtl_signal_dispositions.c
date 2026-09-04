/* crtl signal dispositions: signal(), sigaction(), raise().
 *
 * These three were LINK-ONLY STUBS returning 0 until 2026-09-04, and the
 * return value is what made it a bug rather than a gap -- rc=0 and errno
 * untouched, identical to a real install, so no caller could tell them apart
 * (bug-b-crtl-signal-and-sigaction-report-success-and-install-nothing).
 *
 * EVERY ROW HERE ASSERTS THE HANDLER'S EFFECT, NEVER THE RETURN CODE ALONE.
 * That is the whole design of the file: rc=0 is exactly what the broken
 * version produced, so a row checking rc is a row that passes against the bug.
 * The observable is a counter the handler writes, or the process surviving a
 * signal whose default disposition is fatal.
 *
 * Diffed byte-for-byte against gcc/glibc. Rows carry no per-target constant. */
#define _GNU_SOURCE
#include <signal.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <sys/wait.h>

static volatile int nUsr1, nUsr2, lastSig;

static void onAny(int s) {
  lastSig = s;
  if (s == SIGUSR1) nUsr1++;
  else if (s == SIGUSR2) nUsr2++;
}

static void onNothing(int s) { (void)s; }

int main(void) {
  struct sigaction sa, old;
  __sighandler_t prev;
  int rc, e;

  /* 1: sigaction installs and the handler RUNS. */
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = onAny;
  rc = sigaction(SIGUSR1, &sa, 0);
  raise(SIGUSR1);
  printf("1 %d %d %d\n", rc, nUsr1, lastSig);

  /* 2: ONE handler, TWO signals, each asserting its own number. A single-signal
     row passes even against a trampoline hard-wired to a constant. */
  sigaction(SIGUSR2, &sa, 0);
  raise(SIGUSR2);
  raise(SIGUSR1);
  printf("2 %d %d %d\n", nUsr1, nUsr2, lastSig);

  /* 3: signal(2) returns the PREVIOUS disposition. SIG_DFL initially. */
  prev = signal(SIGCHLD, onNothing);
  printf("3 %d", prev == SIG_DFL);
  prev = signal(SIGCHLD, onNothing);
  printf(" %d\n", prev == onNothing);

  /* 4: SIG_IGN must genuinely ignore -- the process SURVIVES a signal whose
     default disposition is fatal, and the handler does not run. Surviving is
     the assertion; a return code cannot see this. */
  signal(SIGPIPE, SIG_IGN);
  raise(SIGPIPE);
  printf("4 alive\n");

  /* 5: SIG_DFL reverts. Asserted in a CHILD, because the observable is death:
     the parent cannot report a disposition that kills it. WIFSIGNALED, not the
     exit code -- a shell's 128+n is a shell convention, not the wait status. */
  {
    pid_t p = fork();
    if (p == 0) { signal(SIGUSR1, onAny); signal(SIGUSR1, SIG_DFL); raise(SIGUSR1); _exit(7); }
    else { int st = 0; waitpid(p, &st, 0);
           printf("5 %d %d\n", WIFSIGNALED(st) != 0, WIFSIGNALED(st) ? WTERMSIG(st) : -1); }
  }

  /* 6: the two that cannot be caught. EINVAL, and SIG_ERR from signal(). */
  errno = 0; rc = (signal(SIGKILL, onNothing) == SIG_ERR); e = errno;
  printf("6 %d %d", rc, e == EINVAL);
  errno = 0; rc = (signal(SIGSTOP, onNothing) == SIG_ERR); e = errno;
  printf(" %d %d\n", rc, e == EINVAL);

  /* 7: out-of-range signal numbers. */
  errno = 0; printf("7 %d", signal(0, onNothing) == SIG_ERR && errno == EINVAL);
  errno = 0; printf(" %d\n", signal(999, onNothing) == SIG_ERR && errno == EINVAL);

  /* 8: sigaction's oact reports the previous handler, and a NULL act is a
     query that changes nothing. */
  memset(&old, 0, sizeof old);
  rc = sigaction(SIGUSR1, 0, &old);
  printf("8 %d %d", rc, old.sa_handler == onAny);
  raise(SIGUSR1);
  printf(" %d\n", nUsr1);

  /* 9: raise() actually SENDS. Before the fix it returned 0 having sent
     nothing, so a program that raised a signal it handled saw neither the
     handler nor an error. Counted, not returned. */
  {
    int before = nUsr2;
    rc = raise(SIGUSR2);
    printf("9 %d %d\n", rc, nUsr2 - before);
  }
  return 0;
}

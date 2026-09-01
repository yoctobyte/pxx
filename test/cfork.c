/* fork/vfork/wait/waitpid.
 *
 * All four were ENOSYS or ECHILD stubs, and NOT because a syscall was missing.
 * The PAL entry was called PalVfork while its body issued SYS_fork (or clone
 * with SIGCHLD and no CLONE_VM, which is the same thing). Three separate crtl
 * comments then reasoned from that name -- one of them closing with "MEASURE
 * the PAL before believing a line that says an entry is missing" -- and all
 * three agreed with each other, which is what made it durable. busybox ash
 * failed with `can't fork' against a PAL that had had fork all along. Found
 * attempting rung 2 (feature-c-corpus-busybox-multi-applet).
 *
 * OUTPUT IS ORDERED BY CONSTRUCTION, not by luck: the parent blocks in
 * waitpid() before printing anything, and the child says nothing at all -- it
 * reports through its exit status. A test that had both sides print would
 * interleave differently between runs and between gcc and pxx for reasons that
 * are not about fork.
 *
 * THE COW ROW IS THE ONE THAT MATTERS. If fork were secretly a vfork, the
 * child's store to `shared' would be visible in the parent, because they would
 * be the same memory. Asserting only "a child ran and exited 7" passes just as
 * well over a vfork, and that is precisely the corruption the old comment was
 * afraid of -- so the fear is answered with a measurement rather than repeated.
 */
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
#include <signal.h>

static volatile int shared = 111;

int main(void) {
  pid_t p, r;
  int st;

  /* 1: fork returns twice; the child exits 7 and the parent reaps exactly it. */
  p = fork();
  if (p < 0) { printf("1 fork failed errno=%d\n", errno); return 1; }
  if (p == 0) { shared = 222; _exit(7); }
  r = waitpid(p, &st, 0);
  printf("1 reaped=%d exited=%d status=%d\n", r == p, WIFEXITED(st), WEXITSTATUS(st));

  /* 2: COW -- the child's store must NOT be visible here. A vfork would show
        222. This is what distinguishes a real fork from the entry's old name. */
  printf("2 shared=%d\n", shared);

  /* 3: a signalled child decodes as signalled, not exited. */
  p = fork();
  if (p == 0) { _exit(0); }
  waitpid(p, &st, 0);
  printf("3 exited=%d signalled=%d\n", WIFEXITED(st), WIFSIGNALED(st));

  /* 4: wait() is waitpid(-1,...) and reaps whichever child there is. */
  p = fork();
  if (p == 0) { _exit(3); }
  r = wait(&st);
  printf("4 reaped=%d status=%d\n", r == p, WEXITSTATUS(st));

  /* 5: with no children left, ECHILD -- and it must come from the kernel, not
        from a stub that always said so. Row 1 already proved it can succeed. */
  errno = 0;
  r = wait(&st);
  printf("5 rc=%d echild=%d\n", r == -1, errno == ECHILD);

  /* 6: vfork's contract is exec-or-_exit, and under that contract it is
        indistinguishable from fork. That is all this asserts. */
  p = vfork();
  if (p == 0) { _exit(9); }
  waitpid(p, &st, 0);
  printf("6 status=%d\n", WEXITSTATUS(st));

  /* 7: WNOHANG on a child that is still alive returns 0 immediately. */
  p = fork();
  if (p == 0) { for (;;) sleep(1); }   /* not pause(): crtl has no pause, and
                                          adding one is not this ticket's job */
  r = waitpid(p, &st, WNOHANG);
  printf("7 nohang=%d\n", r == 0);
  kill(p, SIGKILL);
  waitpid(p, &st, 0);
  printf("8 killed=%d sig=%d\n", WIFSIGNALED(st), WTERMSIG(st));

  return 0;
}

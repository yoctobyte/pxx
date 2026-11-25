/* sigsuspend waking on SIGCHLD, killpg, sig_t, and a `.section .comment` ...
   `.previous` file-scope asm: what mksh needs to run an external command.

   mksh's j_waitj blocks SIGCHLD, forks, and sigsuspends with it unblocked
   until its handler has reaped the child. sigsuspend answered ENOSYS, so the
   shell spun forever on its first `printf`. The expected output is gcc +
   glibc's. Ticket: feature-nodisx-toybox-and-a-posix-shell-built-by-pxx. */
#define _GNU_SOURCE
#include <signal.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <sys/wait.h>

/* mksh's __RCSID, by hand: an ident string in .comment, ended by .previous */
__asm__(".section .comment"
        "\n	.ascii	\"@(\"\"#)rcsid: \""
        "\n	.asciz	\"c_crtl_sigsuspend_waits_for_a_child\""
        "\n	.previous");

static volatile sig_atomic_t reaped = 0;
static volatile int child_status = -1;

static void on_chld(int sig) {
  int st;
  (void)sig;
  while (waitpid(-1, &st, WNOHANG) > 0) {
    child_status = WEXITSTATUS(st);
    reaped++;
  }
}

static void on_usr1(int sig) { (void)sig; }

int main(void) {
  struct sigaction sa;
  sigset_t chld, old;
  sig_t prev;
  pid_t pid;
  int r, e;

  sa.sa_handler = on_chld;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = 0;
  sigaction(SIGCHLD, &sa, 0);

  sigemptyset(&chld);
  sigaddset(&chld, SIGCHLD);
  sigprocmask(SIG_BLOCK, &chld, &old);
  pid = fork();
  if (pid == 0) _exit(7);
  /* SIGCHLD may already be pending: blocked, it waits for sigsuspend */
  while (!reaped) {
    r = sigsuspend(&old);
    e = errno;
    if (r != -1 || e != EINTR) { printf("sigsuspend r=%d errno=%d\n", r, e); return 1; }
  }
  sigprocmask(SIG_SETMASK, &old, 0);
  printf("child reaped by the handler: %d, exit %d\n", (int)reaped, child_status);

  /* the old mask came back: SIGCHLD is unblocked again */
  sigprocmask(SIG_SETMASK, 0, &old);
  printf("SIGCHLD blocked after: %d\n", sigismember(&old, SIGCHLD));

  /* killpg reaches a whole group: a child in a group of its own, so the
     signal cannot touch this test's own group (make, a pipeline) */
  signal(SIGCHLD, SIG_DFL);
  prev = signal(SIGUSR1, on_usr1);
  printf("previous SIGUSR1 handler was SIG_DFL: %d\n", prev == SIG_DFL);
  pid = fork();
  if (pid == 0) { setpgid(0, 0); for (;;) pause(); }
  setpgid(pid, pid);
  while (getpgid(pid) != pid) usleep(1000);
  r = killpg(pid, SIGTERM);
  waitpid(pid, &e, 0);
  printf("killpg(child group) = %d, child killed by SIGTERM: %d\n", r,
         WIFSIGNALED(e) && WTERMSIG(e) == SIGTERM);
  errno = 0;
  r = killpg(-1, SIGUSR1);
  printf("killpg(-1) = %d, EINVAL: %d\n", r, errno == EINVAL);
  return 0;
}

/* sigaction with SA_SIGINFO: the handler is called as h(sig, info, ctx) with
 * the kernel's siginfo_t, as toybox `timeout` uses it -- a SIGCHLD handler
 * reading si_status and si_code (feature-a-crtl-sigaction-cannot-honour-sa-
 * siginfo; crtl refused the flag with EINVAL before). A child that exits 3
 * gives CLD_EXITED/3, one killed by SIGKILL gives CLD_KILLED/9, and si_pid is
 * the child's. The query form reports SA_SIGINFO back, and a plain sa_handler
 * still gets one argument. The expected output is gcc+glibc's. */
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile int got, code, status, pid, signo, ctx_nonnull;

static void on_child(int sig, siginfo_t *si, void *ctx) {
  signo = sig;
  code = si->si_code;
  status = si->si_status;
  pid = si->si_pid;
  ctx_nonnull = ctx != 0;
  got = 1;
}

static volatile int plain;
static void on_usr1(int sig) { plain = sig; }

static void run(const char *what, int kill_it) {
  int p, w, i;
  got = 0;
  p = fork();
  if (p == 0) {
    if (kill_it) for (;;) pause();
    _exit(3);
  }
  if (kill_it) kill(p, SIGKILL);
  for (i = 0; i < 5000 && !got; i++) usleep(1000);
  waitpid(p, &w, 0);
  printf("%s: got=%d sig=%d code=%d status=%d pid_ok=%d ctx=%d\n", what, got, signo,
         code, status, pid == p, ctx_nonnull);
}

int main(void) {
  struct sigaction sa, old;
  memset(&sa, 0, sizeof sa);
  sa.sa_sigaction = on_child;
  sa.sa_flags = SA_SIGINFO | SA_NOCLDSTOP;
  sigemptyset(&sa.sa_mask);
  printf("install: %d\n", sigaction(SIGCHLD, &sa, 0));
  memset(&old, 0, sizeof old);
  sigaction(SIGCHLD, 0, &old);
  printf("query: siginfo=%d same=%d\n", (old.sa_flags & SA_SIGINFO) != 0,
         old.sa_sigaction == on_child);
  run("exit", 0);
  run("kill", 1);
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = on_usr1;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGUSR1, &sa, 0);
  kill(getpid(), SIGUSR1);
  printf("plain: %d\n", plain);
  return 0;
}

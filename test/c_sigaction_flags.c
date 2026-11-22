/* sigaction's sa_flags, against gcc+glibc. crtl passed only SA_SIGINFO on:
 * the signal runtime installs every handler SA_ONSTACK|SA_RESTART, so a C
 * handler ran on pxx's alt stack (micropython's thread GC scans from the
 * handler's sp to the thread's stack top and crashed: select_poll_eintr), and
 * a read() interrupted by a handler installed without SA_RESTART restarted
 * instead of failing with EINTR.
 * bug-crtl-sigaction-ignores-sa-flags-so-every-handler-runs-on-the-alt-stack-with-sa-restart */
#include <stdio.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/time.h>

static char *main_local;
static volatile long handler_dist;
static int fds[2];
static volatile int depth, max_depth, fed, raised;

static void where(int s) {
  char here;
  (void)s;
  handler_dist = (long)(main_local - &here);
}

static void feed(int s) {
  (void)s;
  if (!fed) { fed = 1; write(fds[1], "x", 1); }
}

static void nest(int s) {
  depth++;
  if (depth > max_depth) max_depth = depth;
  if (depth == 1 && !raised) { raised = 1; raise(s); }
  depth--;
}

static void arm(int ms) {
  struct itimerval it;
  memset(&it, 0, sizeof it);
  it.it_value.tv_usec = ms * 1000;
  setitimer(ITIMER_REAL, &it, 0);
}

static void install(int sig, void (*h)(int), int flags) {
  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sa.sa_handler = h;
  sa.sa_flags = flags;
  sigemptyset(&sa.sa_mask);
  sigaction(sig, &sa, 0);
}

int main(void) {
  char local, c;
  struct sigaction old;
  int r;
  main_local = &local;

  install(SIGUSR1, where, 0);
  raise(SIGUSR1);
  printf("handler on the thread's stack %d\n", handler_dist > 0 && handler_dist < (1L << 20));

  pipe(fds);
  install(SIGALRM, where, 0);
  arm(30);
  errno = 0;
  r = (int)read(fds[0], &c, 1);
  printf("no SA_RESTART: read %d %s\n", r, errno == EINTR ? "EINTR" : "?");

  install(SIGALRM, feed, SA_RESTART);
  fed = 0;
  arm(30);
  r = (int)read(fds[0], &c, 1);
  printf("SA_RESTART: read %d '%c'\n", r, r == 1 ? c : '-');

  signal(SIGALRM, feed);
  fed = 0;
  arm(30);
  r = (int)read(fds[0], &c, 1);
  printf("signal(): read %d '%c'\n", r, r == 1 ? c : '-');

  install(SIGUSR2, nest, 0);
  depth = max_depth = raised = 0;
  raise(SIGUSR2);
  printf("deferred: max depth %d\n", max_depth);
  install(SIGUSR2, nest, SA_NODEFER);
  depth = max_depth = raised = 0;
  raise(SIGUSR2);
  printf("SA_NODEFER: max depth %d\n", max_depth);

  install(SIGUSR1, where, SA_RESTART | SA_NODEFER);
  sigaction(SIGUSR1, 0, &old);
  printf("oact restart %d nodefer %d onstack %d siginfo %d\n",
         (old.sa_flags & SA_RESTART) != 0, (old.sa_flags & SA_NODEFER) != 0,
         (old.sa_flags & SA_ONSTACK) != 0, (old.sa_flags & SA_SIGINFO) != 0);
  return 0;
}

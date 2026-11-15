/* setitimer/getitimer and struct itimerval (lib/crtl sys/time): busybox's
   fancy ping arms SIGALRM this way, and <sys/time.h> had neither the struct
   nor the calls. One 50 ms ITIMER_REAL shot, read back while armed, then a
   bad timer number. The output is gcc's. */
#include <stdio.h>
#include <signal.h>
#include <unistd.h>
#include <sys/time.h>

static volatile int hit;
static void h(int s) { (void)s; hit++; }

int main(void) {
  struct itimerval v, g;
  int r;
  signal(SIGALRM, h);
  v.it_interval.tv_sec = 0; v.it_interval.tv_usec = 0;
  v.it_value.tv_sec = 0; v.it_value.tv_usec = 50000;
  r = setitimer(ITIMER_REAL, &v, 0);
  printf("set %d\n", r);
  r = getitimer(ITIMER_REAL, &g);
  printf("get %d armed=%d\n", r, g.it_value.tv_sec > 0 || g.it_value.tv_usec > 0);
  pause();
  printf("hit %d\n", hit);
  r = setitimer(99, &v, 0);
  printf("bad %d\n", r);
  return 0;
}

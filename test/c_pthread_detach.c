/* pthread_detach: a detached thread's registry slot comes back once it exits.
 *
 * crtl had no pthread_detach at all ("call to undeclared function"), found
 * 2026-09-25 by the thread leak census. The registry has 64 slots, so this
 * creates 300 detached threads in waves: without the reclaim, create 65 fails
 * with EAGAIN. join on a detached thread is EINVAL, as POSIX says. */
#include <pthread.h>
#include <stdio.h>
#include <unistd.h>

static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
static int done;

static int release;

static void *held(void *a) {
  for (;;) {
    int r;
    pthread_mutex_lock(&mu); r = release; pthread_mutex_unlock(&mu);
    if (r) return a;
    usleep(200);
  }
}

static void *body(void *a) {
  pthread_mutex_lock(&mu); done++; pthread_mutex_unlock(&mu);
  return a;
}

int main(void) {
  int i, k, fails = 0, d;
  pthread_t t;
  for (i = 0; i < 300; i += 10) {
    for (k = 0; k < 10; k++) {
      if (pthread_create(&t, 0, body, 0) != 0) { fails++; continue; }
      if (pthread_detach(t) != 0) fails++;
    }
    for (;;) {
      pthread_mutex_lock(&mu); d = done; pthread_mutex_unlock(&mu);
      if (d >= i + 10 - fails) break;
      usleep(500);
    }
  }
  printf("created+detached 300, failures %d, ran %d\n", fails, done);
  /* A detached thread that is still RUNNING (held on a flag): join is EINVAL.
   * Once one has exited, detach may already have given its slot back, and
   * the tid is then simply unknown (ESRCH) -- which is what aarch64 and arm32
   * showed for a thread that finished before the join, so the row holds it. */
  pthread_create(&t, 0, held, 0);
  pthread_detach(t);
  printf("join on detached -> %d\n", pthread_join(t, 0));
  pthread_mutex_lock(&mu); release = 1; pthread_mutex_unlock(&mu);
  return 0;
}

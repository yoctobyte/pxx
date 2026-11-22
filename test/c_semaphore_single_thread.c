/* <semaphore.h> without --threadsafe, against gcc: the header must not drag in
 * <pthread.h> (refused without the flag; tcc's tcc.h includes semaphore.h),
 * and a one-thread semaphore is a plain count. A wait at zero is not tested
 * (it blocks forever under glibc; crtl reports EDEADLK). */
#include <stdio.h>
#include <errno.h>
#include <semaphore.h>
#include <time.h>
int main(void) {
  sem_t s; int v, r; struct timespec ts;
  printf("init %d", sem_init(&s, 0, 2));
  sem_getvalue(&s, &v); printf(" value %d", v);
  printf(" wait %d %d", sem_wait(&s), sem_trywait(&s));
  r = sem_trywait(&s); printf(" empty %d %s", r, errno == EAGAIN ? "EAGAIN" : "?");
  clock_gettime(CLOCK_REALTIME, &ts); ts.tv_nsec = 0; ts.tv_sec += 0;
  r = sem_timedwait(&s, &ts); printf(" timedwait %d %s", r, errno == ETIMEDOUT ? "ETIMEDOUT" : "?");
  sem_post(&s); sem_post(&s); sem_post(&s); sem_getvalue(&s, &v);
  printf(" posted %d timedwait %d", v, sem_timedwait(&s, &ts));
  printf(" destroy %d\n", sem_destroy(&s));
  return 0;
}

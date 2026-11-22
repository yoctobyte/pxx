/* Unnamed POSIX semaphores, against gcc+glibc. crtl had no <semaphore.h>;
 * micropython's unix thread layer needs sem_init/sem_wait/sem_post.
 * A producer posts N items to three consumers; trywait on an empty one is
 * EAGAIN; timedwait with a deadline already near times out with ETIMEDOUT;
 * getvalue reports the count; pshared is ENOSYS in crtl, and not tested.
 * Then pthread_cond_timedwait on both clocks: crtl read every deadline as
 * CLOCK_MONOTONIC, so a default (CLOCK_REALTIME) cond -- and with it
 * sem_timedwait -- waited about 56 years. */
#include <stdio.h>
#include <errno.h>
#include <pthread.h>
#include <semaphore.h>
#include <time.h>

#define N 3000
static sem_t items, done;
static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
static int consumed[3], total;

static int cond_times_out(int clk) {
  pthread_condattr_t ca;
  pthread_cond_t c;
  pthread_mutex_t cm = PTHREAD_MUTEX_INITIALIZER;
  struct timespec ts;
  int r, got;
  pthread_condattr_init(&ca);
  if (clk >= 0) pthread_condattr_setclock(&ca, clk);
  pthread_condattr_getclock(&ca, &got);
  pthread_cond_init(&c, clk >= 0 ? &ca : 0);
  clock_gettime(clk >= 0 ? clk : CLOCK_REALTIME, &ts);
  ts.tv_nsec += 20000000;
  if (ts.tv_nsec >= 1000000000) { ts.tv_sec++; ts.tv_nsec -= 1000000000; }
  pthread_mutex_lock(&cm);
  r = pthread_cond_timedwait(&c, &cm, &ts);
  pthread_mutex_unlock(&cm);
  pthread_cond_destroy(&c);
  pthread_condattr_destroy(&ca);
  return r == ETIMEDOUT ? (clk >= 0 ? got == clk : 1) : -r;
}

static void *consumer(void *a) {
  int k = (int)(long)a;
  for (;;) {
    sem_wait(&items);
    pthread_mutex_lock(&m);
    if (total == N) { pthread_mutex_unlock(&m); sem_post(&items); break; }
    total++;
    consumed[k]++;
    pthread_mutex_unlock(&m);
  }
  sem_post(&done);
  return 0;
}

int main(void) {
  pthread_t t[3];
  int i, v, r, sum;
  struct timespec ts;
  sem_init(&items, 0, 0);
  sem_init(&done, 0, 0);
  for (i = 0; i < 3; i++) pthread_create(&t[i], 0, consumer, (void *)(long)i);
  for (i = 0; i < N; i++) sem_post(&items);
  sem_post(&items);   /* wakes the first consumer to see total == N; each passes it on */
  for (i = 0; i < 3; i++) sem_wait(&done);
  for (i = 0; i < 3; i++) pthread_join(t[i], 0);
  sum = consumed[0] + consumed[1] + consumed[2];
  printf("total %d sum %d\n", total, sum);

  sem_getvalue(&items, &v);
  printf("left %d\n", v);
  while (sem_trywait(&items) == 0) ;
  r = sem_trywait(&items);
  printf("trywait empty %d %s\n", r, errno == EAGAIN ? "EAGAIN" : "?");

  clock_gettime(CLOCK_REALTIME, &ts);
  ts.tv_nsec += 20000000;
  if (ts.tv_nsec >= 1000000000) { ts.tv_sec++; ts.tv_nsec -= 1000000000; }
  r = sem_timedwait(&items, &ts);
  printf("timedwait %d %s\n", r, errno == ETIMEDOUT ? "ETIMEDOUT" : "?");

  sem_post(&items); sem_post(&items);
  sem_getvalue(&items, &v);
  printf("after two posts %d, timedwait %d\n", v, sem_timedwait(&items, &ts));
  printf("cond realtime %d monotonic %d default %d\n",
         cond_times_out(CLOCK_REALTIME), cond_times_out(CLOCK_MONOTONIC), cond_times_out(-1));
  sem_destroy(&items);
  sem_destroy(&done);
  return 0;
}

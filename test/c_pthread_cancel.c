/* pthread cancellation, against gcc+glibc. crtl had no pthread_cancel,
 * pthread_setcancelstate/type or pthread_testcancel; micropython's unix port
 * sets PTHREAD_CANCEL_ASYNCHRONOUS in every thread and cancels the ones still
 * running at exit. feature-crtl-pthread-cancellation */
#include <stdio.h>
#include <pthread.h>
#include <semaphore.h>

static volatile int started, progress, dtor_ran;
static pthread_key_t key;
static sem_t sem;

static void dtor(void *v) { (void)v; dtor_ran = 1; }

static void *deferred(void *a) {
  (void)a;
  pthread_setspecific(key, (void *)1);
  started = 1;
  for (;;) pthread_testcancel();
  return 0;
}

static void *disabled(void *a) {
  int i;
  (void)a;
  pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, 0);
  started = 1;
  while (started != 2) { }          /* main has cancelled us by now */
  for (i = 0; i < 1000; i++) pthread_testcancel();   /* ignored while disabled */
  progress = 1;
  pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, 0);
  pthread_testcancel();
  progress = 2;                     /* never reached */
  return 0;
}

static void *async(void *a) {
  volatile unsigned long n = 0;
  (void)a;
  pthread_setcanceltype(PTHREAD_CANCEL_ASYNCHRONOUS, 0);
  started = 1;
  for (;;) n++;                     /* no cancellation point */
  return 0;
}

static void *waiter(void *a) {
  (void)a;
  started = 1;
  for (;;) sem_wait(&sem);
  return 0;
}

static void *run(void *(*f)(void *), int post) {
  pthread_t t;
  void *r = 0;
  started = 0;
  pthread_create(&t, 0, f, 0);
  while (!started) { }
  pthread_cancel(t);
  if (post) sem_post(&sem);
  started = 2;
  pthread_join(t, &r);
  return r;
}

int main(void) {
  int old = -1, r;
  pthread_key_create(&key, dtor);
  sem_init(&sem, 0, 0);
  r = run(deferred, 0) == PTHREAD_CANCELED;
  printf("deferred canceled %d, key destructor %d\n", r, dtor_ran);
  r = run(disabled, 0) == PTHREAD_CANCELED;
  printf("disabled canceled %d, progress %d\n", r, progress);
  printf("async canceled %d\n", run(async, 0) == PTHREAD_CANCELED);
  printf("sem_wait canceled %d\n", run(waiter, 1) == PTHREAD_CANCELED);
  r = pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &old);
  printf("main setcancelstate %d old %d\n", r, old);
  pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, 0);
  printf("bad state %d, bad type %d\n", pthread_setcancelstate(7, 0), pthread_setcanceltype(7, 0));
  return 0;
}

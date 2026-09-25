/* A RECURSIVE pthread mutex can be re-locked by its owner. crtl accepted
   PTHREAD_MUTEX_RECURSIVE and ignored it, so the second lock deadlocked --
   stock threadsafe SQLite (no SQLITE_HOMEGROWN_RECURSIVE_MUTEX) hung on its
   first statement. Four threads contend with a nested lock/unlock each, the
   main thread waits on a condvar under the mutex and relocks it after, an
   unlock by a non-owner is EPERM and a bad type is EINVAL. Values are glibc's. */
#include <stdio.h>
#include <pthread.h>
static pthread_mutex_t m; static pthread_cond_t cv = PTHREAD_COND_INITIALIZER;
static long counter; static int ready;
static void *work(void *arg) { int i; (void)arg;
  for (i = 0; i < 100000; i++) {
    pthread_mutex_lock(&m); pthread_mutex_lock(&m);   /* recursive */
    counter++;
    pthread_mutex_unlock(&m); pthread_mutex_unlock(&m);
  }
  pthread_mutex_lock(&m); ready++; pthread_cond_broadcast(&cv); pthread_mutex_unlock(&m);
  return 0; }
int main(void) {
  pthread_mutexattr_t a; pthread_t t[4]; int i, r;
  pthread_mutexattr_init(&a); pthread_mutexattr_settype(&a, PTHREAD_MUTEX_RECURSIVE);
  pthread_mutex_init(&m, &a);
  for (i = 0; i < 4; i++) pthread_create(&t[i], 0, work, 0);
  pthread_mutex_lock(&m);
  while (ready < 4) pthread_cond_wait(&cv, &m);       /* depth 1: defined by POSIX */
  pthread_mutex_lock(&m);                             /* relock after the wait */
  pthread_mutex_unlock(&m);
  r = pthread_mutex_unlock(&m);
  for (i = 0; i < 4; i++) pthread_join(t[i], 0);
  printf("counter %ld ready %d unlock %d extra-unlock %d settype-bad %d\n", counter, ready, r,
         pthread_mutex_unlock(&m), pthread_mutexattr_settype(&a, 7));
  return 0; }

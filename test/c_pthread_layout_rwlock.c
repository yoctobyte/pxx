/* crtl's pthread types have glibc's size and alignment (x86-64, i386), so
   under --system-libs glibc never writes past one and a struct holding one
   lays out as gcc's does; and pthread_rwlock_t works: four readers share it,
   two writers exclude everyone. Output must match gcc + glibc. */
#include <pthread.h>
#include <stdio.h>

#define P(t) printf("%s %d %d\n", #t, (int)sizeof(t), (int)_Alignof(t));

static pthread_rwlock_t rw = PTHREAD_RWLOCK_INITIALIZER;
static pthread_mutex_t mx = PTHREAD_MUTEX_INITIALIZER;
static long counter, bad;
static int readers_in;

static void *writer(void *arg)
{
  int i;
  (void)arg;
  for (i = 0; i < 2000; i++) {
    pthread_rwlock_wrlock(&rw);
    pthread_mutex_lock(&mx);
    if (readers_in) bad++;
    pthread_mutex_unlock(&mx);
    counter++;
    pthread_rwlock_unlock(&rw);
  }
  return 0;
}

static void *reader(void *arg)
{
  int i;
  long seen = 0;
  (void)arg;
  for (i = 0; i < 2000; i++) {
    pthread_rwlock_rdlock(&rw);
    pthread_mutex_lock(&mx); readers_in++; pthread_mutex_unlock(&mx);
    seen += counter & 1;
    pthread_mutex_lock(&mx); readers_in--; pthread_mutex_unlock(&mx);
    pthread_rwlock_unlock(&rw);
  }
  return (void *)seen;
}

int main(void)
{
  pthread_t t[6];
  int i, rc;
  P(pthread_mutex_t) P(pthread_mutexattr_t) P(pthread_cond_t) P(pthread_condattr_t)
  P(pthread_attr_t) P(pthread_rwlock_t) P(pthread_rwlockattr_t)
  for (i = 0; i < 2; i++) pthread_create(&t[i], 0, writer, 0);
  for (i = 2; i < 6; i++) pthread_create(&t[i], 0, reader, 0);
  for (i = 0; i < 6; i++) pthread_join(t[i], 0);
  rc = pthread_rwlock_trywrlock(&rw);
  printf("counter %ld bad %ld trywr %d", counter, bad, rc);
  rc = pthread_rwlock_tryrdlock(&rw);
  printf(" tryrd-while-writing %d", rc != 0);
  pthread_rwlock_unlock(&rw);
  rc = pthread_rwlock_tryrdlock(&rw);
  printf(" tryrd %d", rc);
  rc = pthread_rwlock_trywrlock(&rw);
  printf(" trywr-while-reading %d\n", rc != 0);
  return 0;
}

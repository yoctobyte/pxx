/* __thread and pthread keys in an --emit-obj object without --system-libs,
 * linked by pxx --link (bug-c-thread-local-is-shared-in-emit-obj-without-
 * system-libs). Before, such an object kept ONE shared copy of every __thread
 * variable -- crtl's own key table included, so pthread_getspecific was
 * process-wide and rumpuser's `pthread_getspecific(curlwpkey) == NULL` fired
 * at boot. Each thread must see the initial value and its own copy; main's
 * value survives; a key is NULL in a new thread. Expected output is gcc's. */
#include <pthread.h>
#include <stdio.h>

static __thread int v = 5;
__thread long counter;
static pthread_key_t key;

static void *th(void *a) {
  long id = (long)a, i;
  int same = 0;
  if (v != 5) same = 1;
  v = 100 + (int)id;
  for (i = 0; i < 1000; i++) counter++;
  printf("thread %ld: key=%s v=%d counter=%ld shared=%d\n", id,
         pthread_getspecific(key) ? "SET" : "NULL", v, counter, same);
  pthread_setspecific(key, a);
  return pthread_getspecific(key);
}

int main(void) {
  pthread_t t[3];
  void *r;
  long i;
  pthread_key_create(&key, 0);
  pthread_setspecific(key, (void *)7);
  v = 11;
  counter = 42;
  for (i = 0; i < 3; i++) {
    pthread_create(&t[i], 0, th, (void *)(i + 1));
    pthread_join(t[i], &r);
    printf("joined %ld -> %ld\n", i + 1, (long)r);
  }
  printf("main: v=%d counter=%ld key=%ld\n", v, counter, (long)pthread_getspecific(key));
  return 0;
}

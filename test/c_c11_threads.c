/* C11 <threads.h>, against gcc. Built two ways in test-core: --threadsafe
 * (crtl's threads.h over its pthreads) and --system-libs (glibc's thrd_*, with
 * thrd_create routed through pxx's block install).
 *
 * Every thread must get its own copy of a thread_local, initialised from the
 * image. Before crtl had a threads.h, a pxx program called glibc's
 * thrd_create, and its threads all shared the main thread's copy.
 * bug-c-thread-local-storage-still-shares-one-copy-off-x86-64-and-a-warning-is-all-that-stands-there */
#include <stdio.h>
#include <threads.h>
#include <time.h>

static thread_local int tv = 5;
static _Thread_local int arr[3] = {1, 2, 3};
static mtx_t m, rm;
static cnd_t cv;
static int ready, counter, once_runs;
static once_flag once = ONCE_FLAG_INIT;
static tss_t key;
static int dtor_runs;

static void init_once(void) { once_runs++; }
static void dtor(void *p) { (void)p; mtx_lock(&m); dtor_runs++; mtx_unlock(&m); }

static int worker(void *a) {
  int k = (int)(long)a, i;
  call_once(&once, init_once);
  tss_set(key, &tv);
  for (i = 0; i < 100000; i++) { tv += k; arr[1] += 1; }
  for (i = 0; i < 1000; i++) {
    mtx_lock(&rm); mtx_lock(&rm); counter++; mtx_unlock(&rm); mtx_unlock(&rm);
  }
  if (tss_get(key) != &tv) return -1;
  if (k == 3) thrd_exit(tv + arr[1] + 1000);
  return tv + arr[1];
}

static int waiter(void *a) {
  (void)a;
  mtx_lock(&m);
  while (!ready) cnd_wait(&cv, &m);
  mtx_unlock(&m);
  return 77;
}

int main(void) {
  thrd_t t[3], w;
  int r, i;
  struct timespec ts, nap = {0, 2000000};
  if (mtx_init(&m, mtx_plain) != thrd_success) return 1;
  if (mtx_init(&rm, mtx_plain | mtx_recursive) != thrd_success) return 1;
  if (cnd_init(&cv) != thrd_success) return 1;
  if (tss_create(&key, dtor) != thrd_success) return 1;

  for (i = 0; i < 3; i++)
    if (thrd_create(&t[i], worker, (void *)(long)(i + 1)) != thrd_success) return 1;
  for (i = 0; i < 3; i++) { thrd_join(t[i], &r); printf("worker %d -> %d\n", i + 1, r); }
  printf("main tv=%d arr=%d,%d,%d\n", tv, arr[0], arr[1], arr[2]);
  printf("counter=%d once=%d dtors=%d\n", counter, once_runs, dtor_runs);

  thrd_create(&w, waiter, 0);
  printf("sleep %d\n", thrd_sleep(&nap, 0));
  mtx_lock(&m); ready = 1; cnd_signal(&cv); mtx_unlock(&m);
  thrd_join(w, &r);
  printf("waiter -> %d\n", r);

  mtx_lock(&m);
  timespec_get(&ts, TIME_UTC);
  ts.tv_nsec += 20000000;
  if (ts.tv_nsec >= 1000000000) { ts.tv_sec++; ts.tv_nsec -= 1000000000; }
  printf("trylock held: %s\n", mtx_trylock(&m) == thrd_busy ? "busy" : "?");
  mtx_unlock(&m);
  printf("timedlock free: %s\n", mtx_timedlock(&m, &ts) == thrd_success ? "success" : "?");
  mtx_unlock(&m);
  printf("equal %d %d\n", thrd_equal(thrd_current(), thrd_current()) != 0, thrd_equal(thrd_current(), w) != 0);

  tss_delete(key);
  cnd_destroy(&cv);
  mtx_destroy(&rm);
  mtx_destroy(&m);
  return 0;
}

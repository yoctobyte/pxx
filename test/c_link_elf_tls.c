/* ELF thread-local storage through pxx --link (feature-a-pxx-link-has-no-elf-tls).
 *
 * Three objects, as rumpnic has them: TLS_A and TLS_B are compiled with
 * --system-libs, which makes a `__thread` real ELF TLS (.tdata.<name>,
 * reached through fs); the third is a hosted --threadsafe object, which
 * carries crtl and so pthread_create and printf.
 *
 *   - initial-exec (R_X86_64_GOTTPOFF, relaxed to an immediate): tx, tz, and
 *     ty, which is defined in the OTHER object;
 *   - local-exec (R_X86_64_TPOFF32): the statics ts and buf;
 *   - an initialised and an all-zero variable, of sizes 4, 8 and 100;
 *   - the main thread (its block comes from the linker's entry stub) and two
 *     pthreads (theirs from crtl's pthread_create), each changing its own
 *     copy differently, and main printing its values AFTER both threads have
 *     run: a shared copy would show their writes.
 *
 * The expected output is gcc's, from the same source. */
#if defined(TLS_A)
int printf(const char *, ...);
__thread int tx = 5;
__thread long tz;
static __thread int ts = 7;
extern __thread int ty;
int bump(void);
int spawn2(void *(*fn)(void *), long *r0, long *r1);
static void *work(void *arg) {
  long k = (long)arg;
  int b;
  ts += k; tx += 100 * k; tz = k;
  b = bump();
  return (void *)(long)(ts * 1000000 + tx * 1000 + b * 10 + tz);
}
int main(void) {
  long r0 = 0, r1 = 0;
  int b;
  ts++; tx += 10; tz = 3;
  b = bump();
  if (spawn2(work, &r0, &r1)) return 1;
  printf("main %d %d %ld %d %d\n", ts, tx, tz, ty, b);
  printf("t1 %ld t2 %ld\n", r0, r1);
  return 0;
}
#elif defined(TLS_B)
__thread int ty = 40;
static __thread char buf[100];
int bump(void) { buf[3] += 2; ty += buf[3]; return ty; }
#else
#include <pthread.h>
int spawn2(void *(*fn)(void *), long *r0, long *r1) {
  pthread_t a, b;
  void *x, *y;
  if (pthread_create(&a, 0, fn, (void *)1) || pthread_create(&b, 0, fn, (void *)2)) return 1;
  pthread_join(a, &x);
  pthread_join(b, &y);
  *r0 = (long)x; *r1 = (long)y;
  return 0;
}
#endif

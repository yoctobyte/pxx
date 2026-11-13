/* 3000 threads created and joined one after another must not grow the
   process: each finished thread's resources (stack, and on OpenBSD's libc
   build its libc thread block from ld.so) are given back. Before the fix
   the OpenBSD libc build peaked at ~31 MB here, after it ~1 MB.
   feature-port-libc-family-openbsd-netbsd-minix */
#include <stdio.h>
#include <pthread.h>
#include <sys/resource.h>

static void *body(void *arg) { return arg; }

int main(void) {
  struct rusage ru;
  int i;
  for (i = 0; i < 3000; i++) {
    pthread_t t;
    void *r = 0;
    if (pthread_create(&t, 0, body, (void *)(long)i) != 0) {
      printf("pthread_create failed at %d\n", i);
      return 1;
    }
    pthread_join(t, &r);
    if ((long)r != i) { printf("wrong result at %d\n", i); return 1; }
  }
  if (getrusage(RUSAGE_SELF, &ru) != 0) { printf("getrusage failed\n"); return 1; }
  /* ru_maxrss is in KB on Linux and the BSDs. */
  printf("bounded=%s\n", ru.ru_maxrss < 16384 ? "yes" : "no");
  return 0;
}

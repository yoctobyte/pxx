#include <stdio.h>
#include <pthread.h>
struct pt { int x, y; };
static int bump(void) { static __thread int x = 10; return ++x; }
static int buf(int i) { static __thread int a[4] = {1, 2, 3, 4}; a[i] += 100; return a[i]; }
static int sp(void) { static __thread struct pt p = {5, 6}; p.y++; return p.x * 100 + p.y; }
static const char *nm(int set) { static __thread char n[8]; if (set) n[0] = 'A' + set; return n; }
static void run(const char *who, int k) {
  int a = bump(), b = bump(), c = buf(1), d = buf(1), e = sp(), f = sp();
  printf("%s %d %d %d %d %d %d [%s]", who, a, b, c, d, e, f, nm(0)); nm(k); printf(" [%s]\n", nm(0));
}
static void *w(void *x) { run((char *)x, 2); return 0; }
int main(void) { pthread_t t; run("main", 1); pthread_create(&t, 0, w, "thr"); pthread_join(t, 0); run("main", 3); return 0; }

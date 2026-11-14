/* __thread arrays and structs get one copy per thread, and every new thread
   starts from the initialisers (not from main's current values).
   feature-c-thread-local-arrays. Expected output: gcc's. */
#include <stdio.h>
#include <string.h>
#include <pthread.h>

struct pt { int x, y; };
struct big { char name[12]; double v; struct pt p[2]; };

__thread int ia[4] = {11, 22, 33, 44};
__thread char nm[8] = "tls";
static __thread short sm[2][3] = {{1, 2, 3}, {4, 5, 6}};
__thread int za[5];
__thread long long ll[4];
__thread struct pt tp = {3, 4};
__thread struct big tb = {"init", 1.5, {{1, 2}, {5, 6}}};
__thread struct pt arr[3] = {{7, 8}, {9, 10}};
static __thread struct pt sp;

static struct pt get(void) { return tp; }

static void show(const char *who) {
  int *p = ia + 2;
  short *r1 = sm[1];
  struct pt c = tp;
  struct big *pb = &tb;
  printf("%s ia=%d,%d,%d,%d p=%d *ia=%d nm=%s sm=%d r1=%d za=%d d=%d ll=%lld sz=%d,%d\n",
         who, ia[0], ia[1], ia[2], ia[3], *p, *ia, nm, sm[1][2], r1[1], za[4],
         (int)(&ia[3] - &ia[0]), ll[3], (int)sizeof ia, (int)sizeof sm);
  printf("%s tp=%d,%d tb=%s,%.1f,%d arr=%d,%d,%d sp=%d,%d c=%d g=%d\n",
         who, tp.x, tp.y, pb->name, tb.v, tb.p[1].y, arr[0].x, arr[1].y, arr[2].x,
         sp.x, sp.y, c.x, get().y);
}

static void mutate(int k) {
  int i;
  ia[0] = 99 * k; nm[0] = 'T'; za[4] = 7 * k; sm[1][2] = (short)(60 * k);
  ll[3] = (long long)k << 40;
  for (i = 0; i < 4; i++) ia[i] += 1000;
  strcpy(nm + 1, k == 1 ? "one" : "two");
  tp.x += 100; tb.p[1].y = 66; strcpy(tb.name, "changed"); arr[2].x = 77;
  sp = tp; sp.y = 9;
}

static void *w(void *x) {
  show((char *)x);
  mutate(x == (void *)0 ? 3 : 2);
  show((char *)x);
  return 0;
}

int main(void) {
  pthread_t t;
  show("main");
  mutate(1);
  show("main");
  pthread_create(&t, 0, w, "thr");
  pthread_join(t, 0);
  show("main");
  return 0;
}

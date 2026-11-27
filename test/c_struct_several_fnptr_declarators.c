/* Several function-pointer declarators in one struct member declaration:
   `void (*f)(void *), (*g)(void *);`. pxx kept only the first, so `x.g`
   was "no member named 'g'" (Rainyday's kernel/dev/pci.c). Every name is
   a member at gcc's offset, and calls through each reach their function.
   bug-c-a-second-function-pointer-declarator-in-a-struct-member-is-dropped */
#include <stdio.h>
#include <stddef.h>

static int hits;
static void fa(void *p) { hits += 1 + (p != 0); }
static void fb(void *p) { hits += 10 + (p != 0); }
static int twice(int v) { return 2 * v; }
static int thrice(int v) { return 3 * v; }

struct s {
  int a;
  void (*f)(void *), (*g)(void *);
  char c;
  int n, (*h)(int), *pn;
  int (*arr[2])(int), (*one)(int);
  long tail;
};

union u { void (*f)(void *), (*g)(void *); long l; };

int main(void) {
  struct s x;
  union u y;
  int v = 7;
  x.a = 1; x.f = fa; x.g = fb; x.c = 'c'; x.n = 5; x.h = twice; x.pn = &v;
  x.arr[0] = twice; x.arr[1] = thrice; x.one = thrice; x.tail = 99;
  x.f(0); x.g(&x);
  printf("hits %d\n", hits);
  printf("h %d arr %d %d one %d pn %d n %d c %c a %d tail %ld\n", x.h(4), x.arr[0](5),
         x.arr[1](5), x.one(6), *x.pn, x.n, x.c, x.a, x.tail);
  printf("off f %d g %d c %d n %d h %d pn %d arr %d one %d tail %d size %d\n",
         (int)offsetof(struct s, f), (int)offsetof(struct s, g), (int)offsetof(struct s, c),
         (int)offsetof(struct s, n), (int)offsetof(struct s, h), (int)offsetof(struct s, pn),
         (int)offsetof(struct s, arr), (int)offsetof(struct s, one),
         (int)offsetof(struct s, tail), (int)sizeof(struct s));
  y.g = fb; y.f(0);
  printf("union %d size %d g==f %d\n", hits, (int)sizeof(union u), y.g == y.f);
  return 0;
}

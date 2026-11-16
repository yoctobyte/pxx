/* gcc builtins NetBSD's rump sources use: __builtin_return_address(0),
   __builtin_prefetch, __builtin_unreachable, __builtin_isnan,
   __builtin_types_compatible_p, and __builtin_constant_p in a constant
   expression (an array size). The output is gcc's. */
#include <stdio.h>

typedef int myint;
struct p { int x; };

static int counter;
static int bump(void) { return ++counter; }

static void *__attribute__((noinline)) ra(void) { return __builtin_return_address(0); }

static int un(int x) { if (x) return 1; __builtin_unreachable(); }

static int a4[__builtin_constant_p(4) ? 4 : 8];
static int a8[__builtin_constant_p(counter) ? 4 : 8];
static int tcs[__builtin_types_compatible_p(int, myint) + 1];

int main(void) {
  int v[4] = {1, 2, 3, 4};
  double z = 0.0, nan_ = z / z;
  void *r = ra();
  int ra_in_main = (char *)r >= (char *)main && (char *)r < (char *)main + 4096;
  __builtin_prefetch(&v[bump()]);
  __builtin_prefetch(v, 0, 3);
  printf("ra %d prefetch %d un %d\n", ra_in_main, counter, un(5));
  printf("isnan %d %d %d %d\n", __builtin_isnan(nan_), __builtin_isnan(1.5),
         __builtin_isnan(3.0f), __builtin_isnan(nan_ + bump()));
  printf("counter %d\n", counter);
  printf("tc %d %d %d %d %d %d %d\n",
         __builtin_types_compatible_p(int, myint),
         __builtin_types_compatible_p(int, char),
         __builtin_types_compatible_p(__typeof__(v[0]), int),
         __builtin_types_compatible_p(int *, int *),
         __builtin_types_compatible_p(int *, int **),
         __builtin_types_compatible_p(struct p, struct p),
         __builtin_types_compatible_p(struct p *, int *));
  printf("sizes %d %d %d\n", (int)(sizeof a4 / sizeof a4[0]),
         (int)(sizeof a8 / sizeof a8[0]), (int)(sizeof tcs / sizeof tcs[0]));
  return 0;
}

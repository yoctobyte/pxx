/* gcc __builtin_choose_expr: the chosen arm keeps its own type (sizeof, a struct
   value). feature-c-builtin-choose-expr. Expected output is gcc's. */
#include <stdio.h>
#define is_constexpr(x) (sizeof(int) == sizeof(*(8 ? ((void *)((long)(x) * 0l)) : (int *)8)))
struct big { long a, b; };
int main(void) {
  int v = 3; struct big b = { 7, 8 };
  long r1 = __builtin_choose_expr(1, 10L, (struct big){0});
  struct big r2 = __builtin_choose_expr(sizeof(int) == 4, b, 5);
  printf("%ld %ld %ld %zu %zu\n", r1, r2.a, r2.b,
         sizeof(__builtin_choose_expr(0, (char)1, (long)2)),
         sizeof(__builtin_choose_expr(1, (char)1, (long)2)));
  return 0;
}

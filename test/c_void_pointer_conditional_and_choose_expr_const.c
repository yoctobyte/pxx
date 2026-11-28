/* `?:` with a void * arm is void * unless that arm is a null pointer
   constant (C11 6.5.15p6); sizeof of a void deref is GNU C's 1. Together they
   make Linux's __is_constexpr. __builtin_choose_expr folds in constant
   expressions (i915 REG_FIELD_PREP in BUILD_BUG_ON_ZERO).
   bug-c-a-conditional-with-a-void-pointer-arm-is-typed-by-its-first-arm,
   feature-c-builtin-choose-expr. Expected output is gcc's. */
#include <stdio.h>
#define __is_constexpr(x) (sizeof(int) == sizeof(*(8 ? ((void *)((long)(x) * 0l)) : (int *)8)))
#define BUILD_BUG_ON_ZERO(e) ((int)(sizeof(struct { int:(-!!(e)); })))
#define FIELD(mask, val) ((val) + BUILD_BUG_ON_ZERO(__builtin_choose_expr(__is_constexpr(val), (~(mask) & (val)), 0)))
#define pick(x, y) __builtin_choose_expr(__is_constexpr(x), 100 + (x), (y))
_Static_assert(__builtin_choose_expr(1, 4, (void)0) == 4, "c1");
_Static_assert(__builtin_choose_expr(sizeof(int) == 8, 1, 2) == 2, "c2");
enum { E = __builtin_choose_expr(1, 7, 99) };
int main(int argc, char **argv) {
  long v = argc; int *ip = 0; void *vp = 0;
  printf("%d %d %d %d\n", (int)sizeof(*vp), (int)sizeof(*(void *)ip),
         (int)sizeof(*(8 ? ip : vp)), (int)sizeof(*(argc ? ip : (void *)0)));
  printf("%d %d %d\n", (int)sizeof(*(8 ? (void *)0 : (int *)8)),
         (int)sizeof(*(8 ? (void *)(v * 0l) : (int *)8)), (int)sizeof(*(8 ? ip : ip)));
  printf("%d %d %d %d %d\n", (int)__is_constexpr(3), (int)__is_constexpr(v),
         FIELD(0xf, 3), FIELD(0xf, (int)v + 2), E);
  printf("%d %ld\n", pick(5, 0), (long)pick(v, v * 3));
  return 0;
}

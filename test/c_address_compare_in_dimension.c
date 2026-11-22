/* An address comparison inside an array dimension, against gcc.
 *
 * micropython's mp_obj_is_type asserts `(t) != &mp_type_int` with
 * `sizeof(char[1 - 2 * !(cond)])`. `&a != &b` is not an integer constant
 * expression, so inside a function gcc makes the array a VLA and sizes it at
 * run time. pxx folded `&object` to 0, so `&a != &b` became `0 != 0`, and the
 * dimension -1 was reported as a failing static assert in 24 micropython files.
 * bug-c-an-address-comparison-in-an-array-dimension-folds-to-a-failing-static-assert */
#include <stdio.h>

struct T { int x; };
extern const struct T ta, tb;
const struct T ta = {1}, tb = {2};
static int sa, sb;
static int fn(void) { return 0; }

#define ASSERT_NC(c) ((void)sizeof(char[1 - 2 * !(c)]))
#define IS(t, o) (ASSERT_NC((t) != &tb), (o) == (t))

int main(void) {
  const struct T *p = &ta;
  ASSERT_NC(&ta != &tb);
  ASSERT_NC(&sa != &sb);
  ASSERT_NC(&ta == &ta);
  ASSERT_NC(&fn != 0);
  printf("values %d %d %d %d\n", &ta != &tb, &sa == &sb, &ta == &ta, &fn != 0);
  printf("sizes %d %d\n", (int)sizeof(char[1 - 2 * !(&ta != &tb)]), (int)sizeof(char[2 + (&sa == &sa)]));
  printf("macro %d %d\n", IS(&ta, p), IS(&ta, &tb));
  printf("truth %d %d\n", (&ta && 1), (&sa || 0));
  return 0;
}

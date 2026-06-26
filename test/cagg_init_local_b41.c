/* Aggregate initializer `= { ... }` on a NON-array local (lua lcode
   `static const expdesc ef = {VKINT, {0}, NO_JUMP, NO_JUMP};`). The initializer
   is skipped (not yet materialised), with balanced braces so nested `{0}` and
   inner commas don't end it early; parsing must continue past it. Exit 42. */
struct Inner { int p, q; };
struct Outer { int tag; struct Inner in; int a, b; };
int compute(int x) { return x; }
int main(void) {
  static const struct Outer ef = { 1, {0, 0}, 2, 3 };
  int x = 40;
  (void)ef;
  return compute(x) + 2;     /* parsing survived the aggregate init -> 42 */
}

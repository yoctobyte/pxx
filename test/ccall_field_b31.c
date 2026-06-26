/* Field/`->` chain on a pointer-returning call result `f()->field`, and field
   access on a struct-typed GLOBAL (its record id must be recorded). All writes at
   runtime (global initializers are a separate gap). Exit 42. */
struct N { int x; };
struct L { int a, b; struct N *n; };
struct N nn;
struct L gg;
struct L *g(void) { return &gg; }
int main(void) {
  gg.a = 20;            /* global struct field write */
  gg.b = 13;
  gg.n = &nn;
  nn.x = 9;
  return g()->a + g()->b + g()->n->x;   /* 20 + 13 + 9 = 42 */
}

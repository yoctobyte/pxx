/* Record passed BY VALUE as a param, any size (>8B). C struct-by-value: the
   param is a by-ref pointer slot the callee derefs, caller copies to a temp. */
struct S { long a, b, c; };
static int sumb(struct S s) { return (int)(s.a + s.b + s.c); }   /* by-value copy */
static int mutate(struct S s) { s.b = 999; return (int)s.b; }    /* local mutation */
int main(void) {
  struct S x; x.a = 10; x.b = 20; x.c = 12;
  int r = sumb(x);          /* 42 */
  mutate(x);                /* must NOT change caller's x.b */
  return r + (x.b == 20 ? 0 : 100);   /* 42 */
}

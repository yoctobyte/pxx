/* lua's `tonumber` macro: `(1) ? (*(np) = (o)->n, 1) : 0` with np = &local.
   `*(&local_double) = expr` truncated to a 4-byte store before the
   CNodePointeeTk AN_ADDR fix. */
typedef union V { long i; double n; } V;
#define tonum(np, o) ( (1) ? (*(np) = (o)->n, 1) : 0 )
static double conv(V *o) { double n = 0; (void)tonum(&n, o); return n; }
int main(void) {
  V v; v.n = 2.5;
  double r = conv(&v);
  long b = *(long *)&r;
  return (r == 2.5 && (b >> 32) != 0) ? 42 : 1;
}

/* Redundant struct-to-struct cast (struct S)x is an identity yielding the aggregate.
   It was retagged as an AN_PTR_CAST (records are carried by address) -> a by-value
   copy read garbage and SEGV'd. Now yields the operand. -> 42. */
struct S { int a, b; };
struct V { struct S s; int t; };
static int sum(struct S s) { return s.a + s.b; }
int main(void) {
  struct S x = {3, 4};
  struct S y;
  y = (struct S)x;                    /* assign  */
  struct S z = (struct S)x;           /* init    */
  struct V v = {(struct S)x, 9};      /* whole-value element */
  int viaArg = sum((struct S)x);      /* by-value arg */
  return (y.a==3 && y.b==4 && z.a==3 && v.s.b==4 && v.t==9 && viaArg==7) ? 42 : 1;
}

/* Field access through pointer arithmetic: `(p+i)->field` and `(p+i)[j]`.
   lua's s2v(stack + idx) pattern. Exit 42. */
struct V { int x; int y; };
int sum(struct V *p, int i) { return (p + i)->x + (p + i)->y; }
int main(void) {
  struct V a[4];
  a[2].x = 18; a[2].y = 24;
  struct V *p = a;
  int viaArith = sum(a, 2);          /* 18 + 24 = 42 */
  int viaIdx   = (p + 2)->x + (p + 2)->y;
  return (viaArith == 42 && viaIdx == 42) ? 42 : 0;
}

/* A C assignment is an expression yielding the stored value: usable as a call
   argument, chained, and as a pointer base for `->` (lua ldo
   `isLua(ci = ci->previous)` -> `(ci = ci->previous)->callstatus`). Exit 42. */
struct N { int v; int w; struct N *next; };
int getw(struct N *x) { return x->w; }
int main(void) {
  int a, b;
  b = (a = 18);                 /* chained: a=18, b=18 */
  struct N n2, n1;
  n2.v = 0; n2.w = 6; n2.next = 0;
  n1.v = 0; n1.w = 0; n1.next = &n2;
  struct N *p = &n1;
  int viaArg  = getw(p = p->next);   /* p = &n2, getw(&n2) = 6 */
  int viaBase = (p = &n1)->w + (n1.w = 0, 6);  /* (p=&n1)->w=0, +6 */
  /* a + b + viaArg + viaBase = 18 + 18 + 6 + 0... recompute below */
  return a + b + viaArg;        /* 18 + 18 + 6 = 42 */
}

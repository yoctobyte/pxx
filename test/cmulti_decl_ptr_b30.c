/* Multi-declarator pointers `T *a, *b;` — the star binds per-declarator. lua uses
   `TValue *io1, *io2;` everywhere. Mixed `int x, *p, y;` too. Exit 42. */
struct S { int t; };
int main(void) {
  struct S s; struct S *p, *q;          /* both pointers */
  p = &s; q = &s;
  p->t = 20;
  int x = 22, *r, y;                     /* x int, r ptr, y int */
  r = &x; y = *r;
  return q->t + y;                       /* 20 + 22 = 42 */
}

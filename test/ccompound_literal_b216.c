/* Block-scope C99 compound literals (T){...} as expressions.
   AN_COMPOUND_LITERAL node: materialise a hidden temp, carried by address in IR.
   Exercises: by-value arg, &(T){..} + ->, struct init RHS, designated. -> 42. */
struct P { int a; int b; int c; };
static int sum(struct P p) { return p.a + p.b + p.c; }
struct FF { float x; float y; };
int main(void) {
  int r = 0;
  r += sum((struct P){3,4,0});         /* 7 */
  struct P *q = &(struct P){1,2,3};
  r += q->a + q->b + q->c;             /* +6 = 13 */
  struct FF f = (struct FF){1.5f,2.5f};
  r += (int)(f.x + f.y);               /* +4 = 17 */
  struct P d = (struct P){.c=5,.a=1};
  r += d.a + d.c;                      /* +6 = 23 */
  return r + 19;                       /* 42 */
}

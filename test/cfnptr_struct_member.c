/* C: inline function-pointer struct member — layout + indirect call.
   Regression for bug-c-function-pointer-struct-member +
   bug-c-call-inline-function-pointer-struct-member. Exit 42. */
struct cfg {
  int n;
  int (*fp)(int);          /* inline fn-ptr member between two ints */
  int m;
};
static int add1(int x){ return x + 1; }
int main(void){
  struct cfg c;
  struct cfg *p = &c;
  c.n = 10; c.m = 30;
  if (c.n + c.m != 40) return 1;      /* layout: fp must not shift n/m */
  c.fp = add1;
  if (c.fp(1) != 2) return 2;         /* dot call */
  if (p->fp(0) != 1) return 3;        /* arrow call */
  if ((*c.fp)(40) != 41) return 4;    /* explicit-deref call */
  return c.fp(41);                    /* 42 */
}

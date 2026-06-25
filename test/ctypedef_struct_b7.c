/* typedef of a struct tag (`typedef struct Zio ZIO;`) aliases the struct's
   record, so `ZIO *p; p->field` resolves even when the typedef precedes the
   struct body (the lua ZIO/lua_State pattern). Exit code 51. */
typedef struct Zio ZIO;            /* forward: alias precedes the body */
typedef int (*BinOp)(int, int);

struct Zio { int n; BinOp op; };

int mul(int a, int b) { return a * b; }

int call_op(ZIO *z) { return z->op(6, 7); }  /* alias-pointer fn-ptr field call -> 42 */
int get_n(ZIO *z)   { return z->n; }          /* alias-pointer plain field      ->  9 */

int main(void) {
  struct Zio z;
  z.n = 9;
  z.op = mul;
  return call_op(&z) + get_n(&z);  /* 42 + 9 = 51 */
}

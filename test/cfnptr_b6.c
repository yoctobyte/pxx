/* Function pointers: typedef'd fn-ptr type, indirect call through a variable
   and through a struct field, function-name decay to address. Exit code 91. */
typedef int (*BinOp)(int, int);

struct Calc {
  BinOp op;
  int bias;
};

int add(int a, int b) { return a + b; }
int mul(int a, int b) { return a * b; }

int apply(BinOp f, int x, int y) { return f(x, y); }  /* fn-ptr parameter */

int main(void) {
  BinOp f = add;
  struct Calc c;
  c.op = mul;
  c.bias = 5;
  int r1 = f(3, 4);           /* indirect via variable      -> 7  */
  int r2 = c.op(6, 7);        /* indirect via struct field  -> 42 */
  int r3 = apply(add, 20, 17);/* fn-name decay + param call -> 37 */
  return r1 + r2 + r3 + c.bias; /* 7 + 42 + 37 + 5 = 91 */
}

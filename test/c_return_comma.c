/* `return a, b;`: the comma operator in a return statement. pxx parsed a
   single assignment expression there and refused the comma.
   bug-c-return-of-a-comma-expression-is-refused */
#include <stdio.h>
static int calls;
static int bump(void) { return ++calls; }
static int pick(int x) { if (x) return bump(), bump(), x * 10; return calls = 0, -1; }
int main(void) {
  int a = pick(4);
  printf("%d %d\n", a, calls);
  a = pick(0);
  printf("%d %d\n", a, calls);
  return 0;
}

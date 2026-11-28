/* A gcc statement expression inside a constant-expression context (an array
   dimension, LinuxKPI BUILD_BUG_ON(!is_power_of_2(N))) is read as a run-time
   value; its locals are not looked up as names.
   bug-c-a-statement-expression-in-a-constant-expression-reads-its-locals.
   Expected output is gcc's. */
#include <stdio.h>
#define is_power_of_2(n) ({ __typeof(n) _n = (n); _n != 0 && (_n & (_n - 1)) == 0; })
#define CTASSERT(x) while (0) { typedef char chk_[(x) ? 1 : -1]; chk_ _x; _x[0] = 0; }
#define QUEUES 32
static int f(int n) {
  CTASSERT(is_power_of_2(QUEUES));
  int v[({ int _k = n; _k + 1; })];
  return (int)(sizeof v / sizeof v[0]) + is_power_of_2(n);
}
int main(void) { printf("%d %d\n", f(8), f(6)); return 0; }

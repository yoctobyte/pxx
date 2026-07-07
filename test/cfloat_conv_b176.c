/* Regression: C float semantics on x86-64.
   (1) a float through `...` promotes to double — no narrowing at the variadic
       call (printf("%f", floatvar) rounded wrong before).
   (2) a double assigned/passed to an integer target truncates (cvttsd2si). */
#include <stdio.h>
static int ci(int a){ return a; }
static char cc(char a){ return a; }
int main(void){
  float a = 12.34 + 56.78;     /* -> single 0x428a3d71 */
  char buf[32];
  sprintf(buf, "%f", a);       /* single->double promotion for vararg */
  if (buf[0] != '6' || buf[1] != '9' || buf[3] != '1' || buf[5] != '0') return 1;
  int x = 3.7;   if (x != 3) return 2;
  char c = 99.0; if (c != 'c') return 3;
  long l = 9.9;  if (l != 9) return 4;
  if (ci(99.0) != 99) return 5;    /* double->int param */
  if (cc(99.0) != 'c') return 6;   /* double->char param */
  return 42;
}

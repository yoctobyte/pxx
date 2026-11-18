/* __int128 on x86-64 (rdx:rax, ir_codegen_i128.inc), against gcc's output.
   feature-c-int128-and-attribute-mode */
#include <stdio.h>
typedef unsigned __int128 u128;
typedef __int128 i128;
static void p(const char *n, u128 v){ printf("%s %016llx%016llx\n", n, (unsigned long long)(v >> 64), (unsigned long long)v); }
u128 g = 7;
int main(void){
  u128 a = 0xFFFFFFFFFFFFFFFFull, b = 3;
  i128 s = -5;
  p("a", a); p("s", (u128)s);
  p("a+1", a + 1); p("a*b", a * b); p("a*a", a * a);
  p("sh", (u128)1 << 100); p("shr", ((u128)1 << 100) >> 37);
  p("sar", (u128)(s >> 1)); p("sar70", (u128)(((i128)-1 << 80) >> 70));
  p("sub", (u128)0 - b); p("neg", -a); p("not", ~a);
  p("and", (a << 4) & ((u128)0xF0 << 60)); p("or", a | ((u128)1 << 127)); p("xor", a ^ (a << 64));
  printf("cmp %d %d %d %d %d %d\n", a < (a + 1), s < 0, (u128)s > a, s <= -5, s >= 0, a == (a * 1));
  if (a + 1) printf("true\n");
  if (!(a - a)) printf("zero\n");
  u128 arr[3]; arr[1] = a * b; struct { char c; u128 v; } st; st.v = arr[1] + g;
  p("mem", st.v); g += 5; p("g", g);
  unsigned long long lo = (unsigned long long)(a * a); int i = (int)(s * 3);
  printf("narrow %llx %d\n", lo, i);
  return 0; }

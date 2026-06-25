/* Slice C fixture: C statements — local declarations with initialisers,
   assignment + compound-assign, if/else, while, for (with correct continue/post
   semantics), break/continue, prefix/postfix ++/--. Exit code asserted against
   a gcc-built oracle by the Makefile. */
int main(void) {
  int sum = 0;
  int i;
  for (i = 0; i < 10; i++) {       /* 0+1+...+9 = 45 */
    if (i == 7) continue;          /* skip 7 -> 38 */
    sum += i;
  }
  int j = 0;
  while (j < 5) {                  /* +0+1+2+3+4 = 10 -> 48 */
    sum += j;
    ++j;
  }
  int a = 0, b = 1, t, n;
  for (n = 0; n < 9; n++) { t = a + b; a = b; b = t; }  /* fib(9)=34 -> 82 */
  sum += a;
  if (sum > 80) sum -= 1; else sum += 100;              /* 81 */
  int k = 2;
  k *= 3; k |= 1;                  /* 7 ... unused-ish but exercises compound */
  return sum + (k & 1);            /* 81 + 1 = 82 */
}

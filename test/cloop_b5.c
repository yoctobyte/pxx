/* do/while loops and the comma operator (statement + for-clauses). Exit code
   asserted vs a gcc oracle by the Makefile. */
int main(void) {
  int i = 0, s = 0;
  do { s += i; i++; } while (i < 5);     /* 0+1+2+3+4 = 10 */

  int j;
  for (i = 0, j = 10; i < j; i++, j--) s += 1;  /* 5 iterations -> 15 */

  int n = 0;
  do { n++; } while (0);                  /* 1 */
  s += n;                                  /* 16 */

  int a, b;
  a = 3, b = 4;                            /* comma stmt */
  s += a * b;                              /* +12 -> 28 */
  return s;                                /* 28 */
}

/* Integer literal suffixes (U/L/UL/LL/ULL) must be consumed by the lexer, else
   they dangle as identifier tokens and break const expressions (e.g. a `UL`
   constant divided in a macro body). Exit 42. */
#define BIG  0xff00UL
#define LIM(t) (BIG / sizeof(t))       /* const division with a UL literal */
int main(void) {
  unsigned long a = 100UL;
  long b = 5L;
  unsigned int c = 2U;
  unsigned long long d = 1ULL;
  unsigned long e = LIM(int);           /* 0xff00/4 = 16320, must parse */
  return (int)(a / b) + (int)c + (int)d + (e > 100 ? 19 : 0);  /* 20+2+1+19 = 42 */
}

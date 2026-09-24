/* A space before the ')' of a function-like macro's parameter list.

   `#define K( c ) ...` is common style -- sqlite's shell.c writes its base85
   class macros that way -- and pxx's #define scanner stepped over that ')',
   read the macro BODY as more parameters up to its first ')', and left the
   macro with an empty or truncated body. Every use then failed as "expected C
   expression". `K( c)` and `K(c)` were fine, which is why nothing caught it.

   Rows: the sqlite shape verbatim; a space before ')' only; a tab; two
   parameters with spaces around the comma; a variadic `( ... )`; and the
   spellings that always worked, as controls. Values are gcc's. */
#include <stdio.h>

#define B85_CLASS( c ) (((c)>='#')+((c)>'&')+((c)>='*')+((c)>'z'))
#define IS_B85( c ) (B85_CLASS(c) & 1)
#define SP_AFTER(x ) ((x) + 1)
#define TAB_AFTER(x	) ((x) * 3)
#define TWO( a , b ) ((a) - (b))
#define VA( ... ) sum3(__VA_ARGS__)
#define TIGHT(x) ((x) + 100)
#define SP_BEFORE( x) ((x) + 200)

static int sum3(int a, int b, int c) { return a + b + c; }

static char *skipNonB85(char *s, int nc) {
  char c;
  while (nc-- > 0 && (c = *s) && !IS_B85(c)) ++s;
  return s;
}

int main(void) {
  char b[] = "  !x";
  printf("b85 %d %d %d\n", (int)(skipNonB85(b, 4) - b), B85_CLASS('+'), IS_B85('#'));
  printf("sp %d tab %d two %d va %d\n", SP_AFTER(4), TAB_AFTER(5), TWO(10, 3), VA(1, 2, 3));
  printf("controls %d %d\n", TIGHT(1), SP_BEFORE(1));
  return 0;
}

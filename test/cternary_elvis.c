/* GNU omitted-middle conditional `x ?: y`: the value is x when x is true, y
   otherwise, and x is evaluated EXACTLY ONCE. Oracle: gcc -O0. busybox uses it
   in editors/vi.c (`col - ((col % tabstop) ?: tabstop)`). */
int printf(const char *, ...);

static int calls;
static int side(int v) { calls++; return v; }

struct P { int a; int b; };

int main(void) {
  int a = 0, b = 7;
  struct P p = { 11, 22 };
  struct P *pp = &p;
  struct P *np = 0;
  char c = 0, d = 'Z';
  double f = 0.0, g = 2.5;
  int tabstop = 8, col;

  /* plain int select */
  printf("%d %d\n", a ?: b, b ?: a);

  /* left operand evaluated exactly once, either way */
  printf("%d\n", side(0) ?: 5);
  printf("%d\n", calls);
  printf("%d\n", side(3) ?: 5);
  printf("%d\n", calls);

  /* pointer arms keep the pointed-at record: ->field must resolve */
  printf("%d %d\n", (np ?: pp)->a, (pp ?: np)->b);

  /* char arms promote to int (6.5.15p4 usual arithmetic conversions) */
  printf("%d %d\n", c ?: d, d ?: c);

  /* float arms */
  printf("%.1f %.1f\n", f ?: g, g ?: f);

  /* nested / right-associative, and mixed with a full ternary */
  printf("%d\n", a ?: (b ?: 99));
  printf("%d\n", a ? 1 : (a ?: 42));

  /* the busybox shape */
  for (col = 0; col < 20; col += 5)
    printf("%d ", col - ((col % tabstop) ?: tabstop));
  printf("\n");

  /* Side effect in the else arm runs only when the left is false. `calls` is
     read in a SEPARATE printf: argument evaluation order within one call is
     unspecified in C, so reading it alongside the call that bumps it would be
     testing the compiler's argument order, not the operator. */
  calls = 0;
  printf("%d\n", 4 ?: side(1));
  printf("%d\n", calls);
  printf("%d\n", 0 ?: side(1));
  printf("%d\n", calls);
  return 0;
}

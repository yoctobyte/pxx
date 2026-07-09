/* Regression: C11 _Generic selection. Compile-time type dispatch — pick the
   association whose type-name matches the controlling expression's type after
   lvalue conversion (strip top const, array/function decay to pointer), else
   default. Distinguishes int/long, char/const-char pointers, struct tags, and
   function types. feature-c-generic-selection / bug-c-abi-battery. */
const int ci = 0;
struct a { int x; };
struct b { int y; };
typedef int int_alias;
typedef int (*fptr)(int);
int foo(int i) { return i; }

int main(void) {
  int i = 0;
  long l = 2;
  struct b tb;
  const char *cc;
  int_alias ia;
  int ok = 1;

  /* const int -> lvalue-converts to int */
  ok &= (_Generic(ci, int: 1, const int: 2) == 1);
  /* int vs long distinct */
  ok &= (_Generic(l, long: 1, int: 2) == 1);
  ok &= (_Generic(17L, int: 1, long: 2, long long: 3) == 2);
  /* usual arithmetic conversion: int + long -> long */
  ok &= (_Generic(i + 2L, int: 1, long: 2, long long: 3) == 2);
  /* struct tag */
  ok &= (_Generic(tb, struct a: 1, struct b: 2, default: 0) == 2);
  /* typedef resolves to int */
  ok &= (_Generic(ia, char: 1, int: 2) == 2);
  /* const char * pointee-const distinguishes from char * */
  ok &= (_Generic(cc, char *: 1, const char *: 2, default: 0) == 2);
  /* string literal char[N] decays to char * */
  ok &= (_Generic("hi", char *: 1, const char *: 2) == 1);
  /* function decays to fn-pointer */
  ok &= (_Generic(foo, fptr: 1, int: 2) == 1);
  /* default fallback when nothing matches */
  ok &= (_Generic(i, char: 1, int[4]: 2, default: 3) == 3);

  return ok ? 42 : 1;
}

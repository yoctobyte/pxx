/* `#if` must recursively expand chained object macros, not parse a macro body as
   a literal. lua's LUA_INT_TYPE -> LUA_INT_DEFAULT -> LUA_INT_LONGLONG -> 3
   pattern hits this. Exit 42. */
#define LL 3
#define DEFAULT LL
#define T DEFAULT
#define BASE 6
#define DERIVED BASE
int main(void) {
  int r = 0;
#if T == LL          /* chained == chained: 3 == 3 */
  r += 7;
#endif
#if T == 3           /* chained == literal */
  r += 7;
#endif
#if (DERIVED * 2) == 12   /* arithmetic over a chained macro */
  r += 28;
#endif
  return r;          /* 7 + 7 + 28 = 42 */
}

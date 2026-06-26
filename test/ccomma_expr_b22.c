/* Parenthesized comma EXPRESSION `(a, b)` — evaluate a, yield b. lua's api_check
   / lua_lock expand to `((void)l, expr)`. Exit 42. */
int g = 0;
int bump(void) { g += 10; return g; }
int main(void) {
  int x = 5;
  int a = (x++, x);              /* 6 */
  int b = ((void)x, bump(), g);  /* bump runs -> g=10, yields 10 */
  int c = ((void)0, 26);         /* 26 */
  return a + b + c;              /* 6 + 10 + 26 = 42 */
}

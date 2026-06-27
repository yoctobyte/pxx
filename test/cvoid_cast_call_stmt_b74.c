/* A cast-to-void expression statement must still evaluate its operand for side
   effects (regression: `(void)f();` and `((void)f());` were silently dropped,
   so lua's `lua_pushglobaltable` = `((void)lua_rawgeti(...))` did nothing). */

static int counter = 0;
static int bump(int by) { counter += by; return counter; }

int main(void) {
  (void)bump(1);        /* bare cast-to-void statement */
  ((void)bump(2));      /* parenthesized cast-to-void statement */
  (bump(4));            /* parenthesized call (already worked) */
  return counter + 35;  /* 1 + 2 + 4 = 7, +35 = 42 */
}

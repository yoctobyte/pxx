/* Regression: an enum-typed declarator at file scope (a function returning an
   enum, or an enum-typed global) must NOT be mis-parsed as a bare enum
   declaration (that skipped to the first ';' inside the body, desyncing the
   parse). Forward `enum Tag;` and bare `enum Tag {..};` still work. Returns 42. */
enum efoo;                          /* forward declaration (GCC ext) */
enum Color { RED, GREEN = 5, BLUE };
enum Color pick(int i) { return i ? BLUE : RED; }   /* enum return type */
enum Color gv;                      /* enum-typed global */
enum efoo { E_ONE, E_TWO };         /* completing the forward enum */

int main(void) {
    gv = GREEN;
    if ((int)gv != 5) return 1;
    if ((int)pick(0) != 0) return 2;
    if ((int)pick(1) != 6) return 3;   /* BLUE = GREEN(5)+1 = 6 */
    if ((int)E_TWO != 1) return 4;
    return 42;
}

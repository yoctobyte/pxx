/* Regression: a local variable whose name equals an in-scope typedef shadows
   the typedef (C 6.2.1), so a statement/for-init starting with that name is an
   expression, not a declaration. Pre-fix pxx tripped "expected C expression".
   Case-sensitivity matters: typedef `Code` must stay a type even with a
   variable `code` in scope. And a typedef whose name equals an unrelated
   builtin symbol (e.g. `x`) must STILL be a usable type — only a real
   local/param shadows (c-testsuite 00022 regression guard).
   Returns 42 on success. */
typedef struct { int op, val; } code;
typedef struct { int lo, hi; } Code;   /* distinct type, different case */
typedef int x;                          /* name collides with a builtin symbol */

static int loopsum(void) {
    int code;          /* shadows the typedef `code` in this block */
    int n = 0;
    for (code = 0; code < 16; code++)   /* statement-start use of the var */
        n += code;
    code = 5;          /* bare assignment-statement use */
    return n + code;   /* 120 + 5 */
}

int main(void) {
    Code c;            /* `Code` (capital) still a type despite `code` var */
    x v;               /* `x` still a usable type despite a builtin named x */
    v = 3;
    c.lo = 10; c.hi = 7;
    if (loopsum() != 125) return 1;
    if (c.hi - c.lo != -3) return 2;
    if (v != 3) return 3;
    return 42;
}

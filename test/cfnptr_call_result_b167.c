/* Regression: calling the RESULT of a call whose return type is a function
   pointer — `go()()` — must lower the second `()` as an indirect call. Returns 42. */
typedef int (*fty)(void);
static int forty_two(void) { return 42; }
static fty go(void) { return &forty_two; }
int main(void) {
    return go()();   /* go() -> fty, then () calls it -> 42 */
}

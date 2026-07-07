/* Regression: a global struct/array-of-struct with a function-pointer field
   initialized `{ &func }` (address-of form) must bind the address — it was left
   null and calling the field SIGSEGV'd (bare `{ func }` already worked).
   Returns 42. */
struct S { int (*f)(void); };
static int forty(void) { return 40; }
static int a1(void)    { return 1; }
static int a2(void)    { return 1; }
struct S sv = { &forty };
struct S arr[2] = { { &a1 }, { &a2 } };
int main(void) {
    return sv.f() + arr[0].f() + arr[1].f();   /* 40 + 1 + 1 = 42 */
}

/* Regression: a global variable of a function-pointer TYPEDEF type
   (`typedef int (*fty)(void); fty gp = &z;`) must register as callable and bind
   its initializer address — it was "undeclared" / uninitialized (SIGSEGV).
   Returns 42. */
typedef int (*fty)(void);
static int forty(void) { return 40; }
static int two(void)   { return 2; }
fty gp  = &forty;    /* address-of form */
fty gp2 = two;       /* bare form */
int main(void) {
    return gp() + gp2();   /* 40 + 2 */
}

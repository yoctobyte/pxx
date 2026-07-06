/* Regression: a global function pointer initialized with the address-of form
   `&func` (not just the bare `func`) must bind the function's address — it was
   left 0 and calling it SIGSEGV'd. Returns 42. */
static int dbl(int x) { return x * 2; }
static int neg(int x) { return -x; }
int (*gp)(int)  = &dbl;      /* address-of form */
int (*gp2)(int) = neg;       /* bare form (control) */
int main(void) {
    if (gp(20) != 40) return 1;
    if (gp2(5) != -5) return 2;
    return 42;
}

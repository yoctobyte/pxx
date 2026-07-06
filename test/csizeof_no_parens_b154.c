/* Regression: `sizeof unary-expression` without parentheses (C 6.5.3), and
   no-paren sizeof of an array yields the full array size. Returns 42. */
int main(void) {
    int x, *p;
    int a[10];
    if (sizeof 0 < 2) return 1;          /* sizeof int constant, no parens */
    if (sizeof x != sizeof(int)) return 2;
    if (sizeof p != sizeof(void*)) return 3;
    if (sizeof a != 10 * sizeof(int)) return 4;   /* full array, no parens */
    if (sizeof(&x) != sizeof p) return 5;
    return 42;
}

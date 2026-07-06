/* Regression: constant-expression evaluator handles the full C precedence —
   ?: , || , && , comparisons — not just bitwise/arithmetic. Exercised in global
   initializers, enum values, and array bounds. Returns 42. */
int gt = 1 ? 5 : 9;            /* ternary -> 5 */
int ga = (2 && 3);            /* logical and -> 1 */
int go = (0 || 7);            /* logical or  -> 1 */
int gc = (5 > 3) + (2 == 2);  /* comparisons -> 2 */
enum E { EA = (1 && 1), EB = (0 || 5), EC = (3 > 2 ? 10 : 20) };
int band[1 && 1];             /* const array bound with && */
int main(void) {
    if (gt != 5) return 1;
    if (ga != 1 || go != 1) return 2;
    if (gc != 2) return 3;
    if (EA != 1 || EB != 1 || EC != 10) return 4;
    if (sizeof(band) != sizeof(int)) return 5;
    return 42;
}

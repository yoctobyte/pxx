/* Regression: __VA_ARGS__ variadic function-like macros (C99 6.10.3). Returns 42. */
#define SUM3(a, b, c) ((a)+(b)+(c))
#define CALL(f, ...) f(__VA_ARGS__)
#define FIRST_PLUS(x, ...) ((x) + SUM0(__VA_ARGS__))
#define SUM0(...) sum0(__VA_ARGS__)
static int add2(int a, int b) { return a + b; }
static int sum0(int a, int b) { return a + b; }
int main(void) {
    int r1 = CALL(add2, 10, 20);       /* add2(10, 20) = 30 */
    int r2 = CALL(SUM3, 1, 2, 3);      /* SUM3(1,2,3) = 6 */
    int r3 = FIRST_PLUS(4, 1, 5);      /* 4 + sum0(1,5) = 10 */
    return (r1 == 30 && r2 == 6 && r3 == 10) ? 42 : 1;
}

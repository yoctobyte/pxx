/* Cross-target C argument passing + calls. On i386 C cdecl args arrive on the
   stack (not in registers as on x86-64); the callee prologue must copy them from
   [ebp+8+...] into the param slots. Regression guard for the i386 cdecl param
   spill. Exercises multi-arg calls, a struct, a loop, and recursion. Exit 42. */
struct Point { int x; int y; };

int add(int a, int b) { return a + b; }

int five(int a, int b, int c, int d, int e) {
    return a*10000 + b*1000 + c*100 + d*10 + e;
}

int fib(int n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}

int sum_to(int n) {
    int total = 0; int i;
    for (i = 1; i <= n; i++) total = add(total, i);
    return total;
}

int main(void) {
    struct Point p; p.x = 3; p.y = 4;
    if (five(1, 2, 3, 4, 5) != 12345) return 1;
    if (fib(10) != 55) return 2;
    if (sum_to(10) + p.x + p.y != 62) return 3;
    return 42;
}

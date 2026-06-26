/* Slice D fixture: multiple functions, forward + mutual calls, recursion, a
   shared global. Exit code asserted against a gcc oracle by the Makefile. */
int g_counter;

int square(int x) { return x * x; }

int is_even(int n);
int is_odd(int n)  { if (n == 0) return 0; return is_even(n - 1); }
int is_even(int n) { if (n == 0) return 1; return is_odd(n - 1); }

int fib(int n) { if (n < 2) return n; return fib(n - 1) + fib(n - 2); }

void bump(void) { g_counter = g_counter + 1; }

int main(void) {
  int r = 0;
  r += square(6);          /* 36 */
  r += fib(10);            /* 55 -> 91 */
  if (is_even(8)) r += 10; /* 101 */
  if (is_odd(8))  r += 99; /* (no) */
  bump(); bump(); bump();
  r += g_counter;          /* +3 -> 104 */
  return r;                /* 104 */
}

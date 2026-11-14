/* the other half of c_link_aarch64_a.c */
int shared = 10;
const char *names[3] = { "alpha", "beta", "gamma" };
static int add(int a, int b) { return a + b; }
static int mul(int a, int b) { return a * b; }
int (*ops[2])(int, int) = { add, mul };
int bump(int by) { shared += by; return shared; }

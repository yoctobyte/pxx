/* NetBSD rump re-measure rows 6-8 (g31-g33): sizeof of a VLA type name,
   a dead ternary arm that calls a function inside a constant expression
   (ilog2), and GNU named variadic macros (`args...`, `##args`, `#args`). */
#include <stdio.h>

struct s { long a, b; };
static unsigned long vsz(int n) { return sizeof(struct s) + sizeof(struct s [n - 1]); }
static unsigned long vsz2(int n, int m) { return sizeof(int [n][3][m]); }

static int fls64(unsigned long x) { return x ? 64 - __builtin_clzl(x) : 0; }
#define ilog2(x) (__builtin_constant_p(x) ? ((x) >= 256 ? 8 : 1) : fls64(x) - 1)
static int t[ilog2(1000)];
static int t2[__builtin_constant_p(3) ? 5 : fls64(3)];

static int sum(int n, ...) { return n; }
#define LOG(lvl, fmt, args...) printf((fmt), lvl, ##args)
#define CNT(args...) sum(0, ##args)
#define STR(args...) #args
#define FIRST(a, rest...) (a)

int main(void)
{
  int n = 3;
  printf("%lu %lu %lu %d\n", vsz(3), vsz(1), vsz2(2, 4), sizeof(char [n]) - 5 > 0);
  printf("%d %d %d\n", (int)(sizeof t / sizeof t[0]), (int)(sizeof t2 / sizeof t2[0]), ilog2((unsigned long)n * 300));
  LOG(1, "lvl %d\n");
  LOG(2, "lvl %d %d %s\n", 3, "x");
  printf("%d %s %d\n", CNT(), STR(a, "b", c), FIRST(7, 8, 9));
  return 0;
}

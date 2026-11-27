/* __VA_OPT__ (C23 6.10.5.1; gcc reads it in every C mode), compared with
   gcc: the expansion text of each case, then wlroots' logging shape run.
   feature-c-std-c23 */
#include <stdio.h>

#define STR_(...) #__VA_ARGS__
#define STR(...) STR_(__VA_ARGS__)

#define F(a, ...) f(a __VA_OPT__(,) __VA_ARGS__)
#define G(...) g(0 __VA_OPT__(, __VA_ARGS__))
#define H(x, ...) h(__VA_OPT__(x, x,) end)
#define K(...) [__VA_OPT__(<__VA_ARGS__>)]
#define N(x, ...) x __VA_OPT__(+ x) __VA_ARGS__

static int sum(int n, ...) { return n; }
#define LOG(fmt, ...) printf("[%s:%d] " fmt "\n", "file.c", 7 __VA_OPT__(,) __VA_ARGS__)
#define SUM(...) sum(0 __VA_OPT__(+ 1, __VA_ARGS__))

int main(void) {
  puts(STR(F(1)));
  puts(STR(F(1, 2)));
  puts(STR(F(1, 2, 3)));
  puts(STR(F(1,)));
  puts(STR(F(1, )));
  puts(STR(G()));
  puts(STR(G(a)));
  puts(STR(G(a, b)));
  puts(STR(H(p)));
  puts(STR(H(p, q)));
  puts(STR(K()));
  puts(STR(K(z)));
  puts(STR(N(5)));
  puts(STR(N(5, -1)));
  LOG("plain");
  LOG("one %d", 1);
  LOG("two %d %s", 2, "x");
  printf("%d %d\n", SUM(), SUM(9));
  return 0;
}

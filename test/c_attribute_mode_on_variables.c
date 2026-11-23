/* __attribute__((mode(..))) on a variable or member, not only a typedef: gcc
 * makes `int x __attribute__((mode(QI)))` one byte; pxx kept 4. Among the
 * specifiers it covers every declarator. Against gcc.
 * feature-c-int128-other-targets-float-and-narrow-modes */
#include <stdio.h>
int gq __attribute__((mode(QI)));
unsigned gh __attribute__((mode(HI)));
long gs __attribute__((mode(SI)));
struct s { int a __attribute__((mode(HI))); int b __attribute__((mode(QI))); };
struct t { unsigned __attribute__((mode(QI))) x, y; int z; };
int main(void) {
  int lq __attribute__((mode(QI))) = 300;
  unsigned lh __attribute__((mode(HI))) = 70000;
  int __attribute__((mode(QI))) le = 127, lf = -129;
  struct s v; struct t w;
  int i;
  gq = 257; gh = 65537; gs = 0x1ffffffffL;
  v.a = 40000; v.b = 200;
  w.x = 255; w.y = 256; w.z = 7;
  for (i = 0; i < 3; i++) le++;
  printf("%zu %zu %zu %zu %zu\n", sizeof gq, sizeof gh, sizeof gs, sizeof lq, sizeof lh);
  printf("%zu %zu %zu %zu\n", sizeof le, sizeof lf, sizeof(struct s), sizeof(struct t));
  printf("%d %u %ld %d %u\n", gq, gh, (long)gs, lq, lh);
  printf("%d %d %d %d %u %u %d\n", le, lf, v.a, v.b, w.x, w.y, w.z);
  return 0;
}

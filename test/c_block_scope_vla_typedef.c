/* A block-scope VLA typedef: the extent is evaluated once, at the typedef
   (C11 6.7.8p3); variables and sizeof of the type read it. LinuxKPI's
   BUILD_BUG_ON puts one in `while (0)` with a run-time bound (i915).
   feature-c-a-block-scope-vla-typedef. Expected output is gcc's. */
#include <stdio.h>
struct pt { int x, y; };
#define CHECK(x) while (0) { typedef char chk_line[(x) ? 1 : -1]; chk_line _c; _c[0] = 0; }
static unsigned idx(unsigned p) {
  const unsigned bits = sizeof(unsigned long) * 8 - 4;
  CHECK(!(30 > bits * 2));
  return p / bits;
}
static long fill(int n) {
  typedef int row[n + 1];
  n = 100;                          /* the typedef already took n + 1 */
  row a, b;
  long s = 0;
  for (int i = 0; i < (int)(sizeof(row) / sizeof(int)); i++) { a[i] = i; b[i] = 2 * i; }
  for (int i = 0; i < (int)(sizeof a / sizeof a[0]); i++) s += a[i] + b[i];
  return s * 1000 + (long)sizeof(row);
}
static int pts(int n) {
  typedef struct pt pts_t[n];
  pts_t v;
  for (int i = 0; i < n; i++) { v[i].x = i; v[i].y = -i; }
  return v[n - 1].x - v[n - 1].y + (int)sizeof(pts_t);
}
/* and `sizeof a` of a plain VLA, unparenthesised
   (bug-c-sizeof-of-a-vla-without-parentheses-is-the-pointer-size) */
static int count(int n) { int a[n * 2]; return (int)(sizeof a / sizeof a[0]); }
int main(void) {
  printf("%d %d\n", count(3), count(7));
  printf("%u %u\n", idx(130), idx(59));
  printf("%ld %ld\n", fill(3), fill(9));
  printf("%d\n", pts(5));
  return 0;
}

/* An EMPTY brace initializer (GNU, and C23) zero-fills a local array, like
 * any other brace list (C99 6.7.8p21 for the part no element reaches).
 * pxx zeroed a local array only when the list had elements, so an empty pair
 * left stack garbage: toybox readelf's flags buffer, `char sh_flags[16]`
 * initialised that way, printed a stray 0x01 in `readelf -S`.
 * bug-c-an-empty-brace-initializer-leaves-a-local-array-uninitialised
 * The stack is dirtied first so that a missing zero-fill shows. Expected
 * output is gcc's. */
#include <stdio.h>

struct pt { int x, y; };

static void dirty(void) {
  volatile unsigned char junk[512];
  int i;
  for (i = 0; i < 512; i++) junk[i] = 0xA5;
}

static void check(void) {
  char c[16] = {}, *p = c;
  int i4[4] = {};
  long m[2][3] = {};
  char *ptrs[3] = {};
  double d[2] = {};
  struct pt pts[2] = {};
  struct pt one = {};
  int i, sum = 0;
  for (i = 0; i < 16; i++) sum += c[i];
  for (i = 0; i < 4; i++) sum += i4[i];
  for (i = 0; i < 6; i++) sum += (int)m[i / 3][i % 3];
  for (i = 0; i < 3; i++) sum += ptrs[i] != 0;
  sum += d[0] != 0.0 || d[1] != 0.0;
  sum += pts[0].x + pts[0].y + pts[1].x + pts[1].y + one.x + one.y;
  *p++ = 'x';
  printf("sum=%d c=%s len=%d\n", sum, c, (int)sizeof c);
}

int main(void) {
  dirty();
  check();
  dirty();
  check();
  return 0;
}

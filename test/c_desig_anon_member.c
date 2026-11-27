/* A designated member of an anonymous union / struct, initialised with its
   own brace of designators: `.u = { .a = 1, .b = 2 }`. The brace is u's, not
   the anonymous aggregate's. wlroots' backend/drm/atomic.c initialises the
   kernel's struct hdr_output_metadata that way. Positional braces for an
   anonymous member (the case the anonymous-member path is for) beside it.
   Compared with gcc. bug-c-designated-init-of-an-anonymous-union-member */
#include <stdio.h>

struct inner { int a; int b; };
struct o2 { int t; union { struct inner u; long l; }; };
struct o3 { int t; struct { int x; int y; }; struct { struct inner v; int w; }; };

static int f(int v) { return v + 1; }

static struct o2 g1 = { .t = 1, .u = { .a = 2, .b = 3 } };
static struct o2 g2 = { .u = { .b = 4, .a = 5 } };
static struct o3 g3 = { .t = 6, .v = { .b = 7, .a = 8 }, .w = 9, .x = 10 };
static struct o3 g4 = { 11, { 12, 13 }, { { 14, 15 }, 16 } };   /* positional anonymous braces */

int main(void) {
  int k = 20;
  struct o2 l1 = { .t = 0, .u = { .a = f(k), .b = k } };
  struct o2 l2 = { .u = { .a = 1, .b = 2 } };
  struct o2 l3 = { .t = 3, .u = { .b = 4 } };
  struct o2 l4 = { .u = { 5, 6 } };
  struct o3 l5 = { .v = { .a = f(1), .b = f(2) }, .y = f(3), .t = 4 };
  struct o3 l6 = { 7, { 8, 9 }, { { 10, 11 }, 12 } };
  printf("g1 %d %d %d\n", g1.t, g1.u.a, g1.u.b);
  printf("g2 %d %d %d\n", g2.t, g2.u.a, g2.u.b);
  printf("g3 %d %d %d %d %d %d\n", g3.t, g3.x, g3.y, g3.v.a, g3.v.b, g3.w);
  printf("g4 %d %d %d %d %d %d\n", g4.t, g4.x, g4.y, g4.v.a, g4.v.b, g4.w);
  printf("l1 %d %d %d\n", l1.t, l1.u.a, l1.u.b);
  printf("l2 %d %d %d\n", l2.t, l2.u.a, l2.u.b);
  printf("l3 %d %d %d\n", l3.t, l3.u.a, l3.u.b);
  printf("l4 %d %d %d\n", l4.t, l4.u.a, l4.u.b);
  printf("l5 %d %d %d %d %d %d\n", l5.t, l5.x, l5.y, l5.v.a, l5.v.b, l5.w);
  printf("l6 %d %d %d %d %d %d\n", l6.t, l6.x, l6.y, l6.v.a, l6.v.b, l6.w);
  return 0;
}

/* UNION bitfields all alias the same storage at offset 0 — each member is its
   own declaration, so every one starts at bit 0. They were packed sequentially
   like STRUCT bitfields (f2 at bits 14..27), silently reading/writing the
   wrong bits — csmith seed 3's checksum diverged from the gcc oracle on
   exactly this shape (b352). Struct bitfields must keep packing. */
#include <stdio.h>

union U1 {
  unsigned f0;
  unsigned f1 : 14;
  unsigned f2 : 14;
  int f3;
};
static union U1 u = {0xFFFFFFFBu};

struct B {
  unsigned a : 14;
  unsigned b : 14;
};
static struct B s = {5, 9};

int main(void) {
  printf("f0=%x f1=%x f2=%x f3=%x sz=%d\n", u.f0, u.f1, u.f2, u.f3,
         (int)sizeof(u));
  u.f2 = 5;
  printf("after: f0=%x f1=%x\n", u.f0, u.f1);
  printf("struct: a=%x b=%x\n", s.a, s.b);
  s.b = 3;
  printf("struct after: a=%x b=%x\n", s.a, s.b);
  return 0;
}

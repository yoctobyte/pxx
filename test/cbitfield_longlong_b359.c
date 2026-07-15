/* Regression: C long-long bitfields (width 33-64). The bitfield storage unit,
   mask, sign/zero extension, and struct layout were all capped at 32 bits, so a
   `:40` field was read/written through only its low 32 bits and adjacent
   long-long bitfield units overlapped (an 8-byte store clobbered a neighbour).
   (bug-c-long-long-bitfield-promotion / gcc-torture bf64-1.) */
struct S {
  unsigned long long u:40;
  signed   long long s:40;
} x;

struct M {
  unsigned long long a:33;
  unsigned long long b:40;
  unsigned long long c:41;
} y;

int main(void) {
  x.u = 0xFFFFFFFFFFULL;          /* 40 bits all 1 */
  x.s = -5;
  if (x.u != 0xFFFFFFFFFFULL) return 1;   /* full 40-bit round-trip */
  if (x.s != -5)              return 2;   /* 40-bit sign extension */
  if (x.u != 0xFFFFFFFFFFULL) return 3;   /* neighbour not clobbered by x.s store */

  y.a = 0x1FFFFFFFFULL;          /* 33 bits all 1 */
  y.b = 0xFFFFFFFFFFULL;         /* 40 bits all 1 */
  y.c = 0x1FFFFFFFFFFULL;        /* 41 bits all 1 */
  if (y.a != 0x1FFFFFFFFULL)  return 4;
  if (y.b != 0xFFFFFFFFFFULL) return 5;
  if (y.c != 0x1FFFFFFFFFFULL) return 6;
  return 42;
}

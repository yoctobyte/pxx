/* Regression: C integer promotion of bitfields narrower than int.
   A bitfield of width < int reads as a SIGNED int (every value fits), so both
   signed and unsigned sub-int fields promote to `int` — the signed-vs-unsigned
   choice for the surrounding arithmetic comes from that promoted `int`, not the
   field's own signedness. Before the fix an unsigned sub-int bitfield stayed
   unsigned (x.u3 - 2 wrapped to a huge positive) and the read node kept the
   unsigned storage tag (bit.i % bit.u did an UNSIGNED modulo).
   (bug-c-bitfield-promotion-and-layout-cluster / gcc-torture bf-sign-2, bitfld-1). */
struct S { unsigned int u3:3; } x;                 /* x.u3 == 0 */
struct T { signed int i:7; unsigned int u:7; } bit;

int main(void) {
  if ((x.u3 - 2) >= 0) return 1;                   /* -2 < 0: unsigned sub-int promotes to signed */

  bit.i = -13; bit.u = 61;
  if (bit.i != -13) return 2;                      /* signed :7 sign-extends */
  if (bit.u != 61)  return 3;                      /* unsigned :7 zero-extends */

  /* bit.u promotes to signed int, so both modulos are SIGNED: -13 % 61 == -13. */
  if ((bit.i % bit.u) != -13) return 4;
  {
    int i = -13;
    if ((i % bit.u) != -13) return 5;
  }
  return 42;
}

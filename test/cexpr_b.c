/* Slice B fixture: C expression compiler at C precedence. One big return
   expression exercising arithmetic, bitwise, shift, relational, equality,
   logical (short-circuit), unary, and precedence/associativity. The return
   value is the process exit code; the Makefile asserts it equals a gcc oracle.
   (Local declarations and assignment statements are Slice C.) */
int main(void) {
  return (2 + 3 * 4)                                /* 14 */
       + (100 / 7)                                  /* 14 */
       + (17 % 5)                                   /* 2  */
       + ((1 << 3) - (16 >> 2))                     /* 4  */
       + (0xFF & 0x0F)                              /* 15 */
       + (0x10 | 0x05)                              /* 21 */
       + (12 ^ 10)                                  /* 6  */
       + ((5 > 3) + (2 >= 2) + (1 == 1) + (4 != 4)) /* 3  */
       + ((3 && 2) + (0 || 9) + !0 + !7)            /* 3  */
       + (~0 & 7);                                  /* 7  -> total 89 */
}

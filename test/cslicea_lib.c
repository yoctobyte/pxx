/* Slice A operator-fidelity fixture: every C bitwise/shift operator in enum
   const-expressions, exercising the distinct tokens (tkShl/tkShr/tkAmp/tkPipe/
   tkXor) and their precedence in CEvalConstExpr. Paired with test_c_slicea.pas;
   values cross-checked against gcc. */
enum {
  S_SHL  = 1 << 4,                 /* 16  */
  S_SHR  = 256 >> 3,               /* 32  */
  S_XOR  = 12 ^ 10,                /* 6   */
  S_AND  = 0xFF & 0x3C,            /* 60  */
  S_OR   = 0x10 | 0x05,            /* 21  */
  S_COMBO = (1 << 8) | (1 << 4) | 3, /* 275 */
  S_PREC = 1 | 2 & 0               /* & binds tighter than | -> 1 */
};

int dummy_a(int x);
int dummy_a(int x) { return x; }

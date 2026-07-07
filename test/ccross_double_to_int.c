/* Cross double->int truncation on assignment. Must be identical on every target
   (x86-64 cvttsd2si; i386 SSE2; aarch64 fcvtzs; arm32 VFP vcvt.s32.f64; riscv32
   softfloat __pxx_d2i64). Exit 42 iff all truncations are correct. */
int main(void){
  int x = 3.7;        /* -> 3 */
  int n = -3.7;       /* -> -3 (truncate toward zero) */
  char c = 65.0;      /* -> 'A' */
  int big = 1000.9;   /* -> 1000 */
  if (x != 3) return 1;
  if (n != -3) return 2;
  if (c != 'A') return 3;
  if (big != 1000) return 4;
  return 42;
}

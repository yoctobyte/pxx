/* Cross double->int truncation, identical on every target (x86-64 cvttsd2si;
   i386 SSE2; aarch64 fcvtzs; arm32 VFP vcvt.s32.f64; riscv32 softfloat
   __pxx_d2i64). Covers assignment (STORE_SYM) and field store (STORE_MEM).
   Exit 42 iff all truncations are correct. */
struct S { int i; char c; int arr[3]; };
int main(void){
  int x = 3.7;        /* STORE_SYM -> 3 */
  int n = -3.7;       /* -> -3 (truncate toward zero) */
  char c = 65.0;      /* -> 'A' */
  int big = 1000.9;   /* -> 1000 */
  if (x != 3) return 1;
  if (n != -3) return 2;
  if (c != 'A') return 3;
  if (big != 1000) return 4;
  struct S s;
  s.i = 7.9;          /* STORE_MEM field -> 7 */
  s.c = 66.0;         /* -> 'B' */
  s.arr[1] = 12.9;    /* STORE_MEM element -> 12 */
  if (s.i != 7) return 5;
  if (s.c != 'B') return 6;
  if (s.arr[1] != 12) return 7;
  return 42;
}

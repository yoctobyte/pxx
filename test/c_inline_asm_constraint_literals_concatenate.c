/* An asm constraint written as adjacent string literals is one constraint
   (FreeBSD ck_pr.h: `K "q" (v)` with K "Z"), and "Zq"/"eq" -- an immediate or a
   byte register -- read as "q". feature-c-inline-asm-flag-outputs.
   Expected output is gcc's. */
#include <stdio.h>
#include <stdint.h>

#define CK_CC_IMM_U32 "Z"
#define CK_CC_IMM_S32 "e"
#define STORE(S, T, I, K) \
  static void store_##S(T *target, T v) { __asm__ __volatile__(I " %1, %0" : "=m" (*target) : K "q" (v) : "memory"); }
STORE(8, uint8_t, "movb", CK_CC_IMM_U32)
STORE(32, uint32_t, "movl", CK_CC_IMM_U32)
STORE(64, int64_t, "movq", CK_CC_IMM_S32)

int main(void) {
  uint8_t a = 0; uint32_t b = 0; int64_t c = 0;
  store_8(&a, 0xab); store_32(&b, 0xdeadbeef); store_64(&c, -5);
  printf("%#x %#x %lld\n", a, b, (long long)c);
  return 0;
}

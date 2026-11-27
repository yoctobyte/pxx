/* x86 inline asm flag outputs, "=@ccCOND": the operand is the condition left
   by the template (FreeBSD's atomic_cmpset/testandset shapes).
   feature-c-inline-asm-flag-outputs. Expected output is gcc's. */
#include <stdio.h>
#include <stdbool.h>

static int cmpset(volatile unsigned *p, unsigned expect, unsigned src) {
  unsigned char res;
  __asm__ __volatile__("lock; cmpxchgl %3, %1"
                       : "=@cce" (res), "+m" (*p), "+a" (expect)
                       : "r" (src) : "memory", "cc");
  return res;
}
static bool testandset(volatile unsigned *p, unsigned bit) {
  bool res;
  __asm__ __volatile__("lock; btsl %2, %0" : "+m" (*p), "=@ccc" (res) : "Ir" (bit) : "cc");
  return res;
}
static long below(unsigned long a, unsigned long b) {
  long r;
  __asm__("cmpq %2, %1" : "=@ccb" (r) : "r" (a), "r" (b) : "cc");
  return r;
}
/* the other bit ops, register and immediate bit numbers, memory and register bases */
static int bitops(void) {
  unsigned m = 0x0f; unsigned long r = 0x100; unsigned char c1, c2, c3, c4;
  unsigned n = 2;
  __asm__("btrl %2, %0" : "+m" (m), "=@ccc" (c1) : "r" (n) : "cc");      /* clears bit 2 */
  __asm__("btcl $7, %0" : "+m" (m), "=@ccc" (c2) : : "cc");               /* sets bit 7 */
  __asm__("btq $8, %1" : "=@ccc" (c3) : "r" (r) : "cc");
  __asm__("btsq %2, %0" : "+r" (r), "=@ccnc" (c4) : "r" ((unsigned long)40) : "cc");
  printf("bitops m=%#x r=%#lx flags %d %d %d %d\n", m, r, c1, c2, c3, c4);
  return 0;
}
int main(void) {
  volatile unsigned v = 5, bits = 0;
  int a = cmpset(&v, 5, 9), b = cmpset(&v, 5, 7);
  printf("cmpset %d %d v=%u\n", a, b, v);
  int t1 = testandset(&bits, 3), t2 = testandset(&bits, 3);
  printf("testandset %d %d bits=%u\n", t1, t2, bits);
  printf("below %ld %ld\n", below(1, 2), below(3, 2));
  return bitops();
}

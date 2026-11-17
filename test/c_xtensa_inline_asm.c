#include <stdio.h>
/* GNU C inline asm on xtensa: operands, ties, names, immediates, barriers,
   the compare-and-swap pair and the acquire/release forms. Runs in user mode. */
static inline int add3(int a, int b) { int r; __asm__("add %0, %1, %2" : "=a"(r) : "a"(a), "a"(b)); return r; }
static inline int addi_n(int a) { int r; __asm__ volatile("addi %0, %1, %2" : "=r"(r) : "r"(a), "i"(-7)); return r; }
static inline void bump(unsigned *v) { __asm__("addi %0, %0, 1" : "+a"(*v)); }
static inline unsigned cas(volatile unsigned *p, unsigned o, unsigned n) {
  __asm__ __volatile__("wsr %2, scompare1\n\ts32c1i %0, %1, 0" : "+a"(n) : "a"(p), "a"(o) : "memory");
  return n; }
static inline unsigned ld_acq(volatile unsigned *p) { unsigned v; __asm__ volatile("l32ai %0, %1, 0" : "=a"(v) : "a"(p) : "memory"); return v; }
static inline void st_rel(volatile unsigned *p, unsigned v) { __asm__ volatile("s32ri %1, %0, 4" :: "a"(p), "a"(v) : "memory"); }
static inline int named(int x, int y) { int out; __asm__("sub %[o], %[a], %[b]; memw" : [o] "=&a"(out) : [a] "a"(x), [b] "a"(y) : "a8", "memory"); return out; }
static inline short narrow(short s) { short r; __asm__("mov %0, %1; extw; isync" : "=a"(r) : "0"(s)); return r; }
int main(void) {
  volatile unsigned w[2] = { 5, 0 };
  unsigned c = 41, old;
  bump(&c);
  old = cas(&w[0], 5, 9);
  printf("%d %d %u\n", add3(40, 2), addi_n(10), c);
  printf("cas ok %u now %u\n", old, w[0]);
  old = cas(&w[0], 5, 11);
  printf("cas miss %u now %u\n", old, w[0]);
  st_rel(&w[0], 77);
  printf("%u %u %d %d\n", ld_acq(&w[0]), w[1], named(100, 58), narrow(-3));
  __asm__ volatile("memw; rsync; esync; dsync; excw" ::: "memory");
  return 0;
}

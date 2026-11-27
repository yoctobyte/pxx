/* Three GPU-driver census finds, against gcc:
   - a self-referential function-like macro: only its NAME is painted, its
     arguments still expand (FreeBSD's malloc macro and M_ZERO).
     bug-cpp-a-self-referential-macro-call-leaves-its-arguments-unexpanded
   - "q" on x86-64 is any register (ck_pr.h's cmpxchg16b takes b c, clobbers
     rax rdx). bug-c-inline-asm-q-is-any-register-on-x86-64
   - a dead ?: arm holding _Generic is skipped in a constant expression
     (FreeBSD ilog2 as a bitfield width).
     bug-c-a-dead-ternary-arm-with-generic-is-not-skipped
   Expected output is gcc's. */
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#define M_ZERO 0x100
#define WRAP(x) (x)
static int seen;
static int (kalloc)(int size, int flags) { seen = flags; return size; }
#define kalloc(size, flags) ({ int _f = (flags); kalloc((size), _f & ~M_ZERO); })
#define twice(x) (twice_impl(twice_impl(x)))
#define twice_impl(x) ((x) * K2)
#define K2 2

static __inline int ilog2_int(int n) { return 31 - __builtin_clz((unsigned)n); }
static __inline int ilog2_long(long n) { return 63 - __builtin_clzl((unsigned long)n); }
#define ilog2_var(n) _Generic((n), default: ilog2_int, long: ilog2_long)(n)
#define ilog2_const(n) (8 * (int)sizeof(unsigned long long) - 1 - __builtin_clzll(n))
#define ilog2(n) (__builtin_constant_p(n) ? ilog2_const(n) : ilog2_var(n))
struct cfg { uint8_t rate : (8 - ilog2(4)); uint8_t lanes : ilog2(4); };
enum { LOG16 = ilog2(16) };

static bool cas_any_reg(uint64_t *target, uint64_t expect, uint64_t set, uint64_t other) {
  bool z;
  uint64_t a = expect;
  __asm__ __volatile__("lock; cmpxchgq %3, %0; setz %1"
                       : "+m" (*target), "=q" (z), "+a" (a)
                       : "q" (set), "b" (other), "c" (other)
                       : "memory", "cc", "rdx");
  return z;
}

int main(void) {
  int r = kalloc(64, 0x103);
  printf("kalloc %d flags %#x\n", r, seen);
  r = WRAP(kalloc(8, M_ZERO | 1));
  printf("wrapped %d flags %#x twice %d\n", r, seen, twice(3));
  printf("cfg %zu LOG16 %d runtime %d %d\n", sizeof(struct cfg), LOG16, ilog2_var(1000), ilog2_var(1L << 40));
  struct cfg c = { .rate = 63, .lanes = 3 };
  printf("fields %d %d\n", c.rate, c.lanes);
  uint64_t t = 5;
  int c1 = cas_any_reg(&t, 5, 9, 1);
  int c2 = cas_any_reg(&t, 5, 7, 1);
  printf("cas %d %d t=%llu\n", c1, c2, (unsigned long long)t);
  enum { CLZ = __builtin_clzll(1ULL << 20), CTZ = __builtin_ctz(48), POP = __builtin_popcountl(0xF0F0UL), FFS = __builtin_ffs(8) };
  int dims[63 - __builtin_clzll(16)];
  printf("folded %d %d %d %d dims %zu\n", CLZ, CTZ, POP, FFS, sizeof dims / sizeof dims[0]);
  return 0;
}

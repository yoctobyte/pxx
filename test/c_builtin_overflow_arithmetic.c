/* gcc's __builtin_{add,sub,mul}_overflow and the typed spellings: the result
   wrapped to the destination's type, and whether the exact result fits.
   drm-kmod's overflow.h (check_mul_overflow, array_size) is built on them.
   feature-c-builtin-overflow-arithmetic. Expected output is gcc's. */
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <limits.h>

static int n_calls;
static size_t next(size_t v) { n_calls++; return v; }

int main(void) {
  size_t z; int i; unsigned u; uint8_t b; int64_t l; uint64_t q; long sl; unsigned long ul;
  int o;
  o = __builtin_mul_overflow((size_t)1 << 40, (size_t)1 << 30, &z); printf("mul size_t %d %zu\n", o, z);
  o = __builtin_mul_overflow((size_t)1 << 32, (size_t)1 << 32, &z); printf("mul size_t wrap %d %zu\n", o, z);
  o = __builtin_mul_overflow(UINT64_MAX, UINT64_MAX, &q); printf("mul max %d %llu\n", o, (unsigned long long)q);
  o = __builtin_mul_overflow(INT_MAX, 2, &i); printf("mul int %d %d\n", o, i);
  o = __builtin_mul_overflow(-3, 7, &i); printf("mul neg %d %d\n", o, i);
  o = __builtin_mul_overflow(-3, 7, &u); printf("mul neg->unsigned %d %u\n", o, u);
  o = __builtin_add_overflow(200, 100, &b); printf("add u8 %d %u\n", o, b);
  o = __builtin_add_overflow(INT64_MAX, 1, &l); printf("add i64 %d %lld\n", o, (long long)l);
  o = __builtin_sub_overflow(0u, 1u, &u); printf("sub u %d %u\n", o, u);
  o = __builtin_sub_overflow(INT64_MIN, (int64_t)1, &l); printf("sub i64 %d %lld\n", o, (long long)l);
  o = __builtin_umull_overflow(1UL << 63, 2UL, &ul); printf("umull %d %lu\n", o, ul);
  o = __builtin_saddl_overflow(LONG_MAX, 0L, &sl); printf("saddl %d %ld\n", o, sl);
  o = __builtin_mul_overflow(next(6), next(7), &z); printf("once %d %zu calls %d\n", o, z, n_calls);
  if (__builtin_mul_overflow(next(1) << 62, 8, &z)) printf("as condition ok\n");
  return 0;
}

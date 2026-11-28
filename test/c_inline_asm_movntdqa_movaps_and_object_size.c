/* drm_cache.c's __memcpy_ntdqa: movntdqa loads (66 0F 38 2A), movaps and
   movups stores, through xmm0..xmm3 and xmm9. __builtin_object_size answers
   gcc's "unknown". feature-asm-movntdqa-and-movaps, feature-c-builtin-object-size.
   Expected output is gcc's. */
#include <stdio.h>
#include <string.h>
static void copy_ntdqa(void *dst, const void *src, unsigned long len) {
  while (len >= 4) {
    asm("movntdqa	(%0), %%xmm0\n"
        "movntdqa 16(%0), %%xmm1\n"
        "movntdqa 32(%0), %%xmm2\n"
        "movntdqa 48(%0), %%xmm3\n"
        "movaps %%xmm0,   (%1)\n"
        "movaps %%xmm1, 16(%1)\n"
        "movaps %%xmm2, 32(%1)\n"
        "movaps %%xmm3, 48(%1)\n"
        :: "r" (src), "r" (dst) : "memory", "xmm0", "xmm1", "xmm2", "xmm3");
    src = (const char *)src + 64; dst = (char *)dst + 64; len -= 4;
  }
  while (len--) {
    asm("movntdqa (%0), %%xmm9\n"
        "movups %%xmm9, (%1)\n"
        "movaps (%1), %%xmm9\n"
        "movaps %%xmm9, (%1)\n"
        :: "r" (src), "r" (dst) : "memory", "xmm9");
    src = (const char *)src + 16; dst = (char *)dst + 16;
  }
}
static unsigned char a[16 * 7] __attribute__((aligned(16)));
static unsigned char b[16 * 7] __attribute__((aligned(16)));
int main(void) {
  for (int i = 0; i < (int)sizeof a; i++) a[i] = (unsigned char)(i * 37 + 5);
  copy_ntdqa(b, a, 7);
  unsigned sum = 0;
  for (int i = 0; i < (int)sizeof b; i++) sum = sum * 31 + b[i];
  printf("%d %u\n", memcmp(a, b, sizeof a), sum);
  /* either the exact size (gcc knows &k) or the "unknown" answer for the type
     (pxx tracks no sizes): both are what the builtin may return */
  int k = 3;
  unsigned long o0 = __builtin_object_size(&k, 0), o2 = __builtin_object_size(&k, 2);
  printf("%d %d\n", o0 == sizeof k || o0 == (unsigned long)-1, o2 == sizeof k || o2 == 0);
  return 0;
}

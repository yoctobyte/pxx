/* Three things mbedTLS and curl need from the C front end, all x86-64:
   - an empty asm whose outputs are all read-write (`+r`): mbedTLS's
     constant-time barrier, mbedtls_ct_compiler_opaque. The value must come
     through unchanged. It used to be refused.
   - a clobber named by gcc's register NUMBER ("0", "1" = ax, dx): mbedTLS's
     aesni.c. The block must still preserve what the compiler keeps live.
   - __builtin_ia32_pause(): curl's spinlock. A hint, no effect.
   bug-c-an-empty-asm-with-in-out-operands-is-refused,
   bug-c-a-numbered-asm-clobber-is-refused, feature-c-builtin-ia32-pause */
#include <stdio.h>

static inline unsigned long opaque(unsigned long x) {
  asm volatile ("" : [x] "+r" (x) :);
  return x;
}

static unsigned long both(unsigned long a, unsigned long b) {
  asm volatile ("" : "+r" (a), "+r" (b) : : "memory");
  return a * 3 + b;
}

static unsigned long clobber_ax_dx(unsigned long v) {
  unsigned long keep = v ^ 0x5a5a;
  asm volatile ("movl $7, %%eax\n\tmovl $9, %%edx" : : : "0", "1", "cc");
  return keep + v;
}

int main(void) {
  unsigned long m = opaque(0) - 1;   /* all ones: how mbedTLS builds a mask */
  int i;
  printf("opaque %lu %lu %lx\n", opaque(42), opaque(0), m);
  printf("both %lu\n", both(5, 11));
  for (i = 0; i < 3; i++) __builtin_ia32_pause();
  printf("clobber %lu\n", clobber_ax_dx(1000));
  return 0;
}

/* x86-64 inline asm with more register operands than the nine caller-saved
   registers: the rest come from rbx, r12-r15 under a push/pop pair, as
   xz-utils' range decoder needs (eleven operands in one block). The values
   must come out right, and the callee-saved registers must hold what they
   held before the block. Fourteen register operands: all nine plus all five.
   Expected output = gcc -O0's (sum12 is noinline, so the probes in main
   bracket only a call, which must preserve rbx and r12-r15). */
#include <stdio.h>

__attribute__((noinline)) static unsigned long sum12(unsigned long *v)
{
  unsigned long a = v[0], b = v[1], c = v[2], d = v[3], e = v[4], f = v[5];
  unsigned long g = v[6], h = v[7], i = v[8], j = v[9], k = v[10], l = v[11];
  unsigned long out;
  /* named operands, a %q-width base, a %c displacement, %b on a named one */
  __asm__ (
    "mov %[a], %[out]\n\t"
    "add %[b], %[out]\n\t"
    "add %[c], %[out]\n\t"
    "add %[d], %[out]\n\t"
    "add %[e], %[out]\n\t"
    "add %[f], %[out]\n\t"
    "add %[g], %[out]\n\t"
    "add %[h], %[out]\n\t"
    "add %[i], %[out]\n\t"
    "add %[j], %[out]\n\t"
    "add %[k], %[out]\n\t"
    "add %[l], %[out]\n\t"
    "imul $3, %[out]\n\t"
    "add %c[off](%q[p]), %[out]\n\t"
    "movzbl %b[a], %k[a]\n\t"
    "add %[a], %[out]\n\t"
    : [out] "=&r" (out), [a] "+r" (a)
    : [b] "r" (b), [c] "r" (c), [d] "r" (d), [e] "r" (e), [f] "r" (f),
      [g] "r" (g), [h] "r" (h), [i] "r" (i), [j] "r" (j), [k] "r" (k),
      [l] "r" (l), [p] "r" (v), [off] "i" (8 * 11)
    : "cc");
  return out;
}

int main(void)
{
  unsigned long v[12], before[5], after[5];
  int n, ok = 1;
  for (n = 0; n < 12; n++) v[n] = 0x1000u * (unsigned long)(n + 1) + 0x1ffu;
  __asm__ volatile ("mov %%rbx, %0\n\tmov %%r12, %1\n\tmov %%r13, %2\n\tmov %%r14, %3\n\tmov %%r15, %4"
                    : "=m" (before[0]), "=m" (before[1]), "=m" (before[2]), "=m" (before[3]), "=m" (before[4]));
  printf("sum12 = %#lx\n", sum12(v));
  __asm__ volatile ("mov %%rbx, %0\n\tmov %%r12, %1\n\tmov %%r13, %2\n\tmov %%r14, %3\n\tmov %%r15, %4"
                    : "=m" (after[0]), "=m" (after[1]), "=m" (after[2]), "=m" (after[3]), "=m" (after[4]));
  for (n = 0; n < 5; n++) if (before[n] != after[n]) ok = 0;
  printf("callee-saved registers preserved: %s\n", ok ? "yes" : "NO");
  return 0;
}

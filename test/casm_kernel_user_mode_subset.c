/* Kernel-style inline asm that ALSO runs in user mode, so it can be executed
   and compared with gcc rather than only disassembled:
   - a far return through a numeric local label (`leaq 1f(%rip)` + lretq),
     the sequence a kernel reloads CS with after lgdt;
   - reads and writes of segment registers (movw %cs/%ds/%es, movw to %es);
   - named operands (%[name]) and "i" immediates, including one through a
     macro;
   - backward and forward numeric labels in one template (1b, 2f);
   - a "cli; hlt"-style multi-instruction template, here "nop; nop".
   Expected output is gcc's; Linux x86-64 user CS is 0x33. */
#include <stdio.h>
#include <stdint.h>

#define FOUR 4

static unsigned long far_return_to_own_cs(void)
{
    unsigned long cs;
    __asm__ volatile ("movq $0, %%rax\n\t"
                      "movw %%cs, %%ax\n\t"
                      "movq %%rax, %0" : "=c"(cs) : : "rax");
    __asm__ volatile (
        "pushq %[cs]\n\t"
        "leaq 1f(%%rip), %%rax\n\t"
        "pushq %%rax\n\t"
        "lretq\n"
        "1:\n\t"
        "nop"
        : : [cs] "c"(cs) : "rax", "memory");
    return cs;
}

static unsigned es_roundtrip(void)
{
    unsigned short ds, es;
    __asm__ volatile ("movw %%ds, %%ax\n\t"
                      "movw %%ax, %%es\n\t"
                      "movw %%es, %%dx"
                      : "=d"(es) : : "rax");
    __asm__ volatile ("movw %%ds, %%ax" : "=a"(ds));
    return (unsigned)(es == ds);
}

static long imm_operands(void)
{
    long r;
    __asm__ volatile ("movq %[a], %%rax\n\t"
                      "addq %[b], %%rax\n\t"
                      "movq %%rax, %0"
                      : "=d"(r) : [a] "i"(FOUR * 10), [b] "n"(-3) : "rax");
    return r;
}

static long label_loop(long n)
{
    long acc;
    /* 1b counts down, 2f skips the poison: both directions in one template */
    __asm__ volatile ("xorq %%rax, %%rax\n"
                      "1:\n\t"
                      "addq $3, %%rax\n\t"
                      "decq %%rcx\n\t"
                      "jnz 1b\n\t"
                      "jmp 2f\n\t"
                      "movq $-1, %%rax\n"
                      "2:\n\t"
                      "nop; nop\n\t"
                      "movq %%rax, %0"
                      : "=d"(acc) : "c"(n) : "rax");
    return acc;
}

int main(void)
{
    printf("far return cs=%#lx\n", far_return_to_own_cs());
    printf("es roundtrip %u\n", es_roundtrip());
    printf("imm %ld\n", imm_operands());
    printf("labels %ld\n", label_loop(5));
    return 0;
}

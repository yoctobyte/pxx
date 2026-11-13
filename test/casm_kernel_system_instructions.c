/* The privileged instructions a freestanding x86-64 kernel writes in inline
   asm (Gibux's io.h, x86.h, cpu.c). They cannot run in user mode, so this
   file is COMPILED, by pxx and by gcc, and tools/casm_sysinsn_vs_gcc.sh
   compares the encodings objdump reads back. Every register operand is
   fixed ("a", "c", "d") so both compilers must produce identical bytes;
   the frame-slot forms ("m") are compared by mnemonic only, because the two
   compilers lay frames out differently. Never executed. */
#include <stdint.h>

struct table_ptr { uint16_t limit; uint64_t base; } __attribute__((packed));

void k_cli(void)    { __asm__ volatile ("cli"); }
void k_sti(void)    { __asm__ volatile ("sti"); }
void k_halt(void)   { __asm__ volatile ("cli; hlt"); }
void k_swapgs(void) { __asm__ volatile ("swapgs"); }
void k_iretq(void)  { __asm__ volatile ("iretq"); }
void k_sysretq(void){ __asm__ volatile ("sysretq"); }

void k_outb(uint16_t port, uint8_t v)  { __asm__ volatile ("outb %0, %1" : : "a"(v), "Nd"(port)); }
void k_outw(uint16_t port, uint16_t v) { __asm__ volatile ("outw %0, %1" : : "a"(v), "Nd"(port)); }
void k_outl(uint16_t port, uint32_t v) { __asm__ volatile ("outl %0, %1" : : "a"(v), "Nd"(port)); }
uint8_t  k_inb(uint16_t port) { uint8_t v;  __asm__ volatile ("inb %1, %0" : "=a"(v) : "Nd"(port)); return v; }
uint16_t k_inw(uint16_t port) { uint16_t v; __asm__ volatile ("inw %1, %0" : "=a"(v) : "Nd"(port)); return v; }
uint32_t k_inl(uint16_t port) { uint32_t v; __asm__ volatile ("inl %1, %0" : "=a"(v) : "Nd"(port)); return v; }
void k_out80(uint8_t v) { __asm__ volatile ("outb %%al, $0x80" : : "a"(v)); }
uint8_t k_in71(void) { uint8_t v; __asm__ volatile ("inb $0x71, %%al" : "=a"(v)); return v; }

uint64_t k_rdmsr(uint32_t msr)
{
    uint32_t lo, hi;
    __asm__ volatile ("rdmsr" : "=a"(lo), "=d"(hi) : "c"(msr));
    return ((uint64_t)hi << 32) | lo;
}
void k_wrmsr(uint32_t msr, uint64_t v)
{
    __asm__ volatile ("wrmsr" : : "c"(msr), "a"((uint32_t)v), "d"((uint32_t)(v >> 32)));
}

uint64_t k_cr0(void) { uint64_t v; __asm__ volatile ("movq %%cr0, %0" : "=a"(v)); return v; }
uint64_t k_cr2(void) { uint64_t v; __asm__ volatile ("movq %%cr2, %0" : "=c"(v)); return v; }
uint64_t k_cr3(void) { uint64_t v; __asm__ volatile ("movq %%cr3, %0" : "=d"(v)); return v; }
uint64_t k_cr4(void) { uint64_t v; __asm__ volatile ("movq %%cr4, %0" : "=a"(v)); return v; }
uint64_t k_cr8(void) { uint64_t v; __asm__ volatile ("movq %%cr8, %0" : "=a"(v)); return v; }
void k_set_cr3(uint64_t v) { __asm__ volatile ("movq %0, %%cr3" : : "a"(v) : "memory"); }
void k_set_cr8(uint64_t v) { __asm__ volatile ("movq %0, %%cr8" : : "d"(v) : "memory"); }

void k_invlpg(uint64_t va) { __asm__ volatile ("invlpg (%0)" : : "a"(va) : "memory"); }
void k_lgdt_reg(void *p) { __asm__ volatile ("lgdt (%0)" : : "a"(p)); }
void k_lidt_reg(void *p) { __asm__ volatile ("lidt (%0)" : : "c"(p)); }

void k_lgdt_m(uint16_t lim, uint64_t base)
{
    struct table_ptr ptr = { lim, base };
    __asm__ volatile ("lgdt %0" : : "m"(ptr));
}
void k_lidt_m(uint16_t lim, uint64_t base)
{
    struct table_ptr ptr = { lim, base };
    __asm__ volatile ("lidt %0" : : "m"(ptr));
}

void k_segments(void)
{
    __asm__ volatile ("movw $0x10, %%ax\n\t"
                      "movw %%ax, %%ds\n\t"
                      "movw %%ax, %%es\n\t"
                      "movw %%ax, %%ss\n\t"
                      "movw %%ax, %%fs\n\t"
                      "movw %%ax, %%gs\n\t"
                      "movw $0x28, %%ax\n\t"
                      "ltr %%ax" : : : "rax", "memory");
}

void k_fxsave(void *area)  { __asm__ volatile ("fxsave64 (%0)" : : "a"(area) : "memory"); }
void k_fxrstor(void *area) { __asm__ volatile ("fxrstor64 (%0)" : : "c"(area) : "memory"); }
void k_fninit(void)        { __asm__ volatile ("fninit"); }
void k_ldmxcsr(void *p)    { __asm__ volatile ("ldmxcsr (%0)" : : "d"(p)); }

/* XSAVE state (Gibux: CR4.OSXSAVE, XCR0, per-process xsave areas). The
   requested-feature bitmap is edx:eax; the area is the one operand. The
   r12/r13 rows force a SIB byte and a disp8. */
void k_xsave64(void *p, uint64_t m)    { __asm__ volatile ("xsave64 (%0)"    : : "S"(p), "a"((uint32_t)m), "d"((uint32_t)(m >> 32)) : "memory"); }
void k_xrstor64(void *p, uint64_t m)   { __asm__ volatile ("xrstor64 (%0)"   : : "D"(p), "a"((uint32_t)m), "d"((uint32_t)(m >> 32)) : "memory"); }
void k_xsaveopt64(void *p, uint64_t m) { __asm__ volatile ("xsaveopt64 (%0)" : : "c"(p), "a"((uint32_t)m), "d"((uint32_t)(m >> 32)) : "memory"); }
void k_xsavec64(void *p, uint64_t m)   { __asm__ volatile ("xsavec64 (%0)"   : : "b"(p), "a"((uint32_t)m), "d"((uint32_t)(m >> 32)) : "memory"); }
void k_xsave(void *p, uint64_t m)      { __asm__ volatile ("xsave (%0)"      : : "S"(p), "a"((uint32_t)m), "d"((uint32_t)(m >> 32)) : "memory"); }
void k_xrstor(void *p, uint64_t m)     { __asm__ volatile ("xrstor (%0)"     : : "D"(p), "a"((uint32_t)m), "d"((uint32_t)(m >> 32)) : "memory"); }
void k_xsaveopt(void *p, uint64_t m)   { __asm__ volatile ("xsaveopt (%0)"   : : "c"(p), "a"((uint32_t)m), "d"((uint32_t)(m >> 32)) : "memory"); }
void k_xsavec(void *p, uint64_t m)     { __asm__ volatile ("xsavec (%0)"     : : "b"(p), "a"((uint32_t)m), "d"((uint32_t)(m >> 32)) : "memory"); }
void k_xsave_r12(void)  { __asm__ volatile ("xsave64 (%%r12)"     : : "a"(7), "d"(0) : "memory"); }
void k_xrstor_r13(void) { __asm__ volatile ("xrstor64 16(%%r13)"  : : "a"(7), "d"(0) : "memory"); }
void k_xsetbv(uint32_t which, uint64_t v)
{
    __asm__ volatile ("xsetbv" : : "c"(which), "a"((uint32_t)v), "d"((uint32_t)(v >> 32)));
}

/* Hardware entropy: CF says whether the value is valid, read with setc. */
uint64_t k_rdrand64(void) { uint64_t v; uint8_t ok; __asm__ volatile ("rdrand %0; setc %1" : "=a"(v), "=c"(ok) : : "cc"); return v + ok; }
uint32_t k_rdseed32(void) { uint32_t v; uint8_t ok; __asm__ volatile ("rdseed %0; setc %1" : "=d"(v), "=a"(ok) : : "cc"); return v + ok; }
void k_rdrand_r11(void)   { __asm__ volatile ("rdrand %%r11" : : : "r11", "cc"); }
void k_rdseed_ax(void)    { __asm__ volatile ("rdseed %%ax" : : : "rax", "cc"); }
/* "=qm" (byte register or memory) is read as "=q". Named u_, not k_, so the
   picker skips it: gcc may choose memory or another register for it. */
uint64_t u_rdrand_qm(void) { uint64_t v; uint8_t ok; __asm__ volatile ("rdrand %0; setc %1" : "=r"(v), "=qm"(ok) : : "cc"); return v + ok; }

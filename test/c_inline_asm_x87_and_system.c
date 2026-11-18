/* NetBSD x86/include/cpufunc.h's inline asm (rump g26), the user-mode-safe
   part run for real against gcc's output: the x87 control word and status
   word, fnsave/frstor and fxsave/fxrstor round trips through
   `*(char (*)[N])area`, pushfq/popfq, and an "m" INPUT of a pointer-to-array
   deref (which used to hand the template the pointer, not the array).
   The privileged ones (clts, wbinvd, invd, lldt, monitor, mwait, rdpmc) only
   need to assemble: they sit in static inlines nothing here calls, which is
   exactly how cpufunc.h holds them.
   feature-c-inline-asm-x87-and-system-instructions
   bug-c-an-m-input-of-a-pointer-to-array-deref-reads-the-pointer */
#include <stdio.h>
#include <string.h>

static __inline void fnclex(void) { __asm volatile ("fnclex"); }
static __inline void fninit(void) { __asm volatile ("fninit"); }
static __inline void fnstcw(unsigned short *val) { __asm volatile ("fnstcw %[val]" : [val] "=m" (*val)); }
static __inline void fnstsw(unsigned short *val) { __asm volatile ("fnstsw %[val]" : [val] "=m" (*val)); }
static __inline void fldcw(unsigned short *val) { __asm volatile ("fldcw %[val]" : : [val] "m" (*val)); }
static __inline void fnsave(void *area) { __asm volatile ("fnsave %[area]" : [area] "=m" (*(char (*)[108])area) : : "memory"); }
static __inline void frstor(const void *area) { __asm volatile ("frstor %[area]" : : [area] "m" (*(const char (*)[108])area) : "memory"); }
static __inline void fxsave(void *area) { __asm volatile ("fxsave %[area]" : [area] "=m" (*(char (*)[512])area) : : "memory"); }
static __inline void fxrstor(const void *area) { __asm volatile ("fxrstor %[area]" : : [area] "m" (*(const char (*)[512])area) : "memory"); }
static __inline void fwait(void) { __asm volatile ("fwait"); }
static __inline void clts(void) { __asm volatile ("clts" ::: "memory"); }
static __inline void wbinvd(void) { __asm volatile ("wbinvd" ::: "memory"); }
static __inline void invd(void) { __asm volatile ("invd" ::: "memory"); }
static __inline void lldt(unsigned short sel) { __asm volatile ("lldt %0" : : "r" (sel)); }
static __inline void x86_monitor(const void *a, unsigned e, unsigned h) { __asm volatile ("monitor" : : "a" (a), "c" (e), "d" (h)); }
static __inline void x86_mwait(unsigned e, unsigned h) { __asm volatile ("mwait" : : "a" (e), "c" (h)); }
static __inline unsigned long rdpmc(unsigned c) { unsigned lo, hi; __asm volatile ("rdpmc" : "=a" (lo), "=d" (hi) : "c" (c)); return lo | ((unsigned long)hi << 32); }

static unsigned char fsave_area[108] __attribute__((aligned(16)));
static unsigned char fx_area[512] __attribute__((aligned(16)));
static unsigned char fx_area2[512] __attribute__((aligned(16)));
static long pair[2] = { 0x1122334455667788L, 99 };

static long read_m_cast(const void *a) { long x; __asm volatile ("movq %1, %0" : "=r" (x) : "m" (*(const long (*)[2])a)); return x; }
static long read_m_var(long (*q)[2]) { long x; __asm volatile ("movq %1, %0" : "=r" (x) : "m" (*q)); return x; }
static void write_m_cast(void *a) { __asm volatile ("movq $42, %0" : "=m" (*(long (*)[2])a)); }

int main(void)
{
    unsigned short cw, cw2, sw, newcw;
    unsigned long fl;

    fninit();
    fnstcw(&cw);
    printf("cw after fninit %04x\n", cw);
    newcw = (unsigned short)((cw & ~0x0C00) | 0x0C00);   /* round toward zero */
    fldcw(&newcw);
    fnstcw(&cw2);
    printf("cw after fldcw %04x\n", cw2);
    fnclex();
    fwait();
    fnstsw(&sw);
    printf("sw after fnclex %04x\n", sw & 0x00FF);

    memset(fsave_area, 0xAB, sizeof fsave_area);
    fnsave(fsave_area);                 /* also re-initialises the FPU */
    fnstcw(&cw);
    printf("fnsave stored cw %04x, live cw %04x\n",
           fsave_area[0] | (fsave_area[1] << 8), cw);
    frstor(fsave_area);
    fnstcw(&cw);
    printf("cw after frstor %04x\n", cw);

    memset(fx_area, 0, sizeof fx_area);
    fxsave(fx_area);
    printf("fxsave fcw %04x\n", fx_area[0] | (fx_area[1] << 8));
    fninit();
    fxrstor(fx_area);
    fnstcw(&cw);
    printf("cw after fxrstor %04x\n", cw);
    fxsave(fx_area2);
    printf("fxsave round trip %s\n", memcmp(fx_area, fx_area2, 32) == 0 ? "same" : "DIFFERENT");
    fninit();

    __asm volatile ("pushfq; popq %0" : "=r" (fl));
    __asm volatile ("pushq %0; popfq" : : "r" (fl));
    printf("rflags bit 1 %lu\n", (fl >> 1) & 1);

    printf("m input cast %lx\n", read_m_cast(pair));
    printf("m input var %lx\n", read_m_var(&pair));
    write_m_cast(pair);
    printf("m output cast %ld\n", pair[0]);
    return 0;
}

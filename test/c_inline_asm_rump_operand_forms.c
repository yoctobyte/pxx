/* Inline asm forms from NetBSD/rump's x86 headers (rump repros g14a/g14c),
   run and compared with gcc: the "qQ" byte class, %k and %q size modifiers,
   a named operand as a 32-bit base (gcc emits the 0x67 prefix), the rep
   prefixes with movs/stos/scas/cmps in each width, "=A" on x86-64 (rax),
   and an "N" port constant. */
#include <stdio.h>
#include <string.h>
static unsigned char xb(volatile unsigned char *p, unsigned char v)
{ __asm__ volatile("xchgb %0, %1" : "=qQ"(v), "+m"(*p) : "0"(v) : "memory"); return v; }
static unsigned long lo(unsigned long a) { __asm__("movl %k0,%k0" : "+r"(a)); return a; }
static unsigned long qq(unsigned int a) { unsigned long r; __asm__("movq %q1,%0" : "=r"(r) : "r"((unsigned long)a)); return r; }
static int named(int a) { int r; __asm__("leal 1(%[x]),%[y]" : [y]"=r"(r) : [x]"r"(a)); return r; }
static void set(void *d, int c, unsigned long n)
{ __asm__ volatile("rep stosb" : "+D"(d), "+c"(n) : "a"(c) : "memory"); }
static void setq(void *d, unsigned long v, unsigned long n)
{ __asm__ volatile("rep stosq" : "+D"(d), "+c"(n) : "a"(v) : "memory"); }
static void cpyl(void *d, const void *s, unsigned long n)
{ __asm__ volatile("rep movsl" : "+D"(d), "+S"(s), "+c"(n) : : "memory"); }
static void cpyw(void *d, const void *s, unsigned long n)
{ __asm__ volatile("rep movsw" : "+D"(d), "+S"(s), "+c"(n) : : "memory"); }
static unsigned long find(const char *s, char c, unsigned long n)
{ __asm__ volatile("repne scasb" : "+D"(s), "+c"(n) : "a"(c) : "memory"); return n; }
static unsigned long same(const char *a, const char *b, unsigned long n)
{ __asm__ volatile("repe cmpsb" : "+S"(a), "+D"(b), "+c"(n) : : "memory"); return n; }
static unsigned long acc(unsigned long v) { unsigned long r; __asm__("movq %1,%%rax" : "=A"(r) : "r"(v)); return r; }
static int nport(void) { int r; __asm__("movl %1,%0" : "=r"(r) : "N"(0x80)); return r; }
int main(void)
{
    volatile unsigned char c = 'p';
    char buf[16], src[16] = "abcdefghijklmno", dst[16];
    unsigned long qb[3];
    unsigned short w[4] = { 1, 2, 3, 4 }, w2[4] = { 0 };
    unsigned char o = xb(&c, 'q');
    set(buf, 'x', 15); buf[15] = 0;
    setq(qb, 0x0102030405060708UL, 3);
    memset(dst, 0, sizeof dst);
    cpyl(dst, src, 3);
    cpyw(w2, w, 4);
    printf("xb %c %c lo %lx qq %lx named %d\n", o, c, lo(0xffffffff12345678UL), qq(7u), named(41));
    printf("set %s q %lx %lx movsl %s movsw %u %u %u %u\n", buf, qb[0], qb[2], dst, w2[0], w2[1], w2[2], w2[3]);
    printf("scas %lu cmps %lu %lu A %lx N %d\n", find("hello", 'l', 5), same("abcd", "abxd", 4),
           same("abcd", "abcd", 4), acc(0x55), nport());
    return 0;
}

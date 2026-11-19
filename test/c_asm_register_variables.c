/* Local register variables, `register long x __asm__("reg")`, as inline-asm
   operands: the one place gcc guarantees the binding, and the shape of every
   hand-rolled syscall wrapper (Rainyday's tests/xtensa, musl's x86-64
   syscall_arch.h). The asm reads the bound registers by name, so a binding
   that did not hold gives a wrong value, not just a slower one.
   feature-c-asm-register-variables */
#include <stdio.h>

#if defined(__x86_64__)
static long sys_write(long fd, const char *p, long n)
{
    register long rax __asm__("rax") = 1;
    register long r10 __asm__("r10") = 0;   /* a 4th argument, unused by write */
    __asm__ volatile("syscall" : "+r"(rax) : "D"(fd), "S"(p), "d"(n), "r"(r10) : "rcx", "r11", "memory");
    return rax;
}
static long add_named(long x, long y)
{
    register long r12 __asm__("r12") = x;
    register long r9 __asm__("r9") = y;
    long r;
    __asm__("mov %%r12, %0\n\tadd %%r9, %0" : "=r"(r) : "r"(r12), "r"(r9));
    return r;
}
#elif defined(__i386__)
static long sys_write(long fd, const char *p, long n)
{
    register long eax __asm__("eax") = 4;
    register long ebx __asm__("ebx") = fd;
    register long ecx __asm__("ecx") = (long)p;
    register long edx __asm__("edx") = n;
    __asm__ volatile("int $0x80" : "+r"(eax) : "r"(ebx), "r"(ecx), "r"(edx) : "memory");
    return eax;
}
static long add_named(long x, long y)
{
    register long esi __asm__("esi") = x;
    register long edi __asm__("edi") = y;
    long r;
    __asm__("mov %%esi, %0\n\tadd %%edi, %0" : "=r"(r) : "r"(esi), "r"(edi));
    return r;
}
#elif defined(__xtensa__)
/* the Linux xtensa syscall ABI, which is Rainyday's: number in a2,
   arguments in a6, a3, a4, a5, a8, a9 */
static long sys6(long nr, long a, long b, long c, long d, long e, long f)
{
    register long a2 __asm__("a2") = nr;
    register long a6 __asm__("a6") = a;
    register long a3 __asm__("a3") = b;
    register long a4 __asm__("a4") = c;
    register long a5 __asm__("a5") = d;
    register long a8 __asm__("a8") = e;
    register long a9 __asm__("a9") = f;
    __asm__ volatile("syscall" : "+r"(a2) : "r"(a6), "r"(a3), "r"(a4), "r"(a5), "r"(a8), "r"(a9) : "memory");
    return a2;
}
static long sys_write(long fd, const char *p, long n)
{
    return sys6(13, fd, (long)p, n, 0, 0, 0);
}
static long add_named(long x, long y)
{
    register long a10 __asm__("a10") = x;
    register long a11 __asm__("a11") = y;
    long r;
    __asm__("add %0, a10, a11" : "=r"(r) : "r"(a10), "r"(a11));
    return r;
}
#endif

/* a register variable is an ordinary local everywhere else */
static int plain(int v)
{
#if defined(__x86_64__)
    register int k __asm__("r13") = v;
#elif defined(__i386__)
    register int k __asm__("ebx") = v;
#else
    register int k __asm__("a5") = v;
#endif
    k = k * 3 + 1;
    return k;
}

int main(void)
{
    long w = sys_write(1, "hi\n", 3);
    printf("%ld %ld %d\n", w, add_named(40, 2), plain(-5));
    return 0;
}

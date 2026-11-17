/* Inline asm memory outputs, "=m" and "+m" (x86-64), checked against gcc:
   the template writes the object itself -- through its address in a register,
   or straight into a plain local's slot -- so nothing is copied back. The
   shapes of rump/NetBSD's and Nilix's atomic helpers: xchg on *p, add to a
   struct field, a global, an array element, and a local.
   feature-c-inline-asm-plus-m-read-write-memory-operand */
#include <stdio.h>
struct s { int a, b; long c; };
static long glob = 40;
static int arr[4] = { 1, 2, 3, 4 };
static unsigned xchg32(volatile unsigned *p, unsigned v)
{
    __asm__ volatile("xchgl %0, %1" : "=r"(v), "+m"(*p) : "0"(v) : "memory");
    return v;
}
static unsigned char xchg8(volatile unsigned char *p, unsigned char v)
{
    __asm__ volatile("xchgb %0, %1" : "=q"(v), "+m"(*p) : "0"(v) : "memory");
    return v;
}
int main(void)
{
    struct s st = { 1, 2, 3 };
    struct s *ps = &st;
    volatile unsigned w = 7;
    volatile unsigned char c = 'a';
    int loc = 5, i = 2;
    unsigned old = xchg32(&w, 99);
    unsigned char oc = xchg8(&c, 'z');
    __asm__ volatile("movl $11, %0" : "=m"(st.b));
    __asm__ volatile("addq $5, %0" : "+m"(ps->c));
    __asm__ volatile("addq %1, %0" : "+m"(glob) : "r"(2L));
    __asm__ volatile("incl %0" : "+m"(arr[i]));
    __asm__ volatile("movl $9, %0" : "=m"(arr[0]));
    __asm__ volatile("shll $3, %0" : "+m"(loc));
    printf("old %u w %u oc %c c %c b %d c %ld glob %ld arr %d %d %d %d loc %d\n",
           old, w, oc, c, st.b, st.c, glob, arr[0], arr[1], arr[2], arr[3], loc);
    return 0;
}

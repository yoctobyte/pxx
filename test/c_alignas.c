/* C11 _Alignas (and <stdalign.h>'s alignas): on a local, a global, a struct
   member (moves the layout) and with a type argument. It was read as a call to
   an undeclared function: dhcpcd's dhcp_readbpf, `alignas(sizeof(struct ip *))
   uint8_t buf[...]`. Against gcc. bug-c-alignas-is-read-as-a-call */
#include <stdio.h>
#include <stddef.h>
#include <stdint.h>
#include <stdalign.h>

struct ip;
_Alignas(64) static char gbuf[10];
struct S { char c; _Alignas(16) int x; char d; alignas(double) char e; };

static int aligned_at(const void *p, unsigned a) { return ((uintptr_t)p % a) == 0; }

int main(void)
{
    char pad = 1;
    alignas(sizeof(struct ip *)) uint8_t buf[37];
    _Alignas(16) char big[3];
    struct S s;
    (void)pad;
    buf[0] = 1; big[0] = 2;
    printf("local %d %d global %d\n", aligned_at(buf, 8), aligned_at(big, 16), aligned_at(gbuf, 64));
    printf("struct size %u x@%u d@%u e@%u align %u\n", (unsigned)sizeof(struct S),
           (unsigned)offsetof(struct S, x), (unsigned)offsetof(struct S, d),
           (unsigned)offsetof(struct S, e), (unsigned)_Alignof(struct S));
    s.x = 5; s.e = 'e';
    printf("member %d %c\n", s.x, s.e);
    return buf[0] + big[0] == 3 ? 0 : 1;
}

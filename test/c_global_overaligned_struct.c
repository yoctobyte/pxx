/* A global whose STRUCT TYPE is over-aligned (a member carries aligned(4096))
 * sits on that alignment, in .bss and in .data, as an array element and
 * alone; and _Alignof / __alignof__ answer the type's alignment. Before the
 * fix the slot offsets were multiples of 4096 from a .bss base that was only
 * 8- or 16-aligned. Output equals gcc's.
 * bug-c-a-global-of-an-over-aligned-struct-type-is-not-placed-on-its-alignment */
#include <stdio.h>
#include <stddef.h>
#include <stdint.h>

struct sqe { uint32_t a[16]; };
struct q { struct sqe *sq; int x; };
struct ctrl {
    volatile uint8_t *regs; uint32_t dstrd; struct q admin, io;
    struct sqe asq[16] __attribute__((aligned(4096)));
    uint8_t acq[256] __attribute__((aligned(4096)));
    uint8_t bounce[65536] __attribute__((aligned(4096)));
};
struct hba { char port; uint8_t clb[1024] __attribute__((aligned(1024))); uint8_t fis[256] __attribute__((aligned(256))); };

static char before = 1;
static struct ctrl ctrls[4];
static char between;
struct ctrl one;
static struct ctrl two = { 0, 5 };
static struct hba hbas[3];
static struct hba hinit = { 9 };

static unsigned long m(const volatile void *p, unsigned long a) { return (unsigned long)((uintptr_t)p % a); }

int main(void) {
    printf("off asq %zu acq %zu bounce %zu size %zu\n", offsetof(struct ctrl, asq),
           offsetof(struct ctrl, acq), offsetof(struct ctrl, bounce), sizeof(struct ctrl));
    printf("ctrl %lu %lu %lu %lu %lu\n", m(ctrls, 4096), m(ctrls[1].asq, 4096), m(ctrls[3].bounce, 4096),
           m(&one, 4096), m(two.acq, 4096));
    printf("hba %lu %lu %lu %lu\n", m(hbas, 1024), m(hbas[2].clb, 1024), m(hbas[1].fis, 256), m(hinit.clb, 1024));
    printf("init %u %d %d %d\n", two.dstrd, hinit.port, before, between);
    printf("alignof %zu %zu %zu %zu %zu %zu\n", _Alignof(struct ctrl), _Alignof(struct hba), _Alignof(int),
           _Alignof(char *), __alignof__(one), _Alignof(struct sqe));
    {
        static char arr[_Alignof(struct hba) / 256];
        printf("const %zu\n", sizeof arr);
    }
    return 0;
}

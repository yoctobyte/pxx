/* --emit-obj --freestanding: globals of over-aligned struct types land on
   their alignment once linked (the object sections carry it). Driven by
   c_freestanding_overaligned_main.c (gcc); fs_mods is 0 when all are aligned.
   bug-c-a-global-of-an-over-aligned-struct-type-is-not-placed-on-its-alignment */
struct sqe { unsigned int a[16]; };
struct ctrl {
    volatile unsigned char *regs; unsigned int dstrd;
    struct sqe asq[16] __attribute__((aligned(4096)));
    unsigned char acq[256] __attribute__((aligned(4096)));
};
static struct ctrl ctrls[3];
static struct ctrl inited = { 0, 7 };
struct a1k { char pad; char q[100] __attribute__((aligned(1024))); };
static struct a1k ahci[2];
static char tail_byte;
unsigned long fs_mods(void) {
    return ((unsigned long)ctrls % 4096) + ((unsigned long)ctrls[2].acq % 4096)
         + ((unsigned long)&inited % 4096) + ((unsigned long)ahci[1].q % 1024)
         + inited.dstrd - 7 + tail_byte;
}

/* Struct copy and zero in a freestanding xtensa object: no RTL, so no
   PXXMemZero / PXXMemMove -- inline loops (XtensaInlineMem). Covers
   `= {0}`, compound literals, assignment, return by value, an odd size
   (bytes) and a misaligned destination (byte loop chosen at run time).
   check() & 255 == 81, the value gcc -O0 gives on x86-64; run under
   qemu-xtensa by tools/check_xtensa_freestanding_struct.py.
   bug-c-struct-copy-and-zero-in-a-freestanding-xtensa-object */
struct big { unsigned w[12]; };
struct odd { unsigned char c[7]; };
struct q { char c[8]; };
struct big g, h;
struct q qa[2];
static struct big mk(unsigned k) { struct big b = {0}; b.w[0] = k; b.w[11] = k * 3; return b; }
static void set(const struct big *b) { g = *b; }
int check(void) {
    struct big z = {0}; struct odd o = {{1,2,3,4,5,6,7}}, p; struct q *u;
    unsigned s = 0, i;
    for (i = 0; i < 12; i++) h.w[i] = 100 + i;
    set(&h);
    h = mk(9);
    for (i = 0; i < 12; i++) s += g.w[i] + z.w[i] + h.w[i];
    p = o; o = (struct odd){0};
    for (i = 0; i < 7; i++) s += p.c[i] * 10 + o.c[i];
    u = (struct q *)((char *)qa + 1);      /* an unaligned struct copy */
    qa[0].c[0] = 0; *u = (struct q){{5,5,5,5,5,5,5,5}};
    for (i = 0; i < 8; i++) s += ((char *)qa)[i];
    return (int)s;
}

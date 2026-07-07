/* b189 (feature-c-corpus-tcc): C99 6.7.8p21 — a local aggregate initializer
   with fewer initializers than members zero-fills the remainder. Every shape
   here left stack garbage before the fix (dirty() poisons the frame first);
   tcc's `struct scope f = { 0 };` read a garbage Sym* from cl.s and its
   goto-cleanup walk crashed 0.6s into self-compiling tcc.c. Exit 42 = pass. */
static void dirty(void) {
    volatile long a[32]; int i;
    for (i = 0; i < 32; i++) a[i] = 0x2000 + i;
}
struct flat { long a, b, c, d; };
struct named_inner { struct { int x, y; } v; long tail; };
struct arr_s { int a[4]; long tail; };
struct scope {
    struct scope *prev;
    struct { int loc, locorig, num; } vla;
    struct { void *s; int n; } cl;
    int *bsym, *csym;
    void *lstk, *llstk;
};
static int t1(void) { struct flat f = { 0 };
  return (f.a || f.b || f.c || f.d) ? 1 : 0; }
static int t2(void) { struct named_inner f = { 0 };
  return (f.v.x || f.v.y || f.tail) ? 1 : 0; }
static int t3(void) { struct arr_s f = { 0 };
  return (f.a[0] || f.a[1] || f.a[2] || f.a[3] || f.tail) ? 1 : 0; }
static int t4(void) { struct flat f = { 1, 2 };
  return (f.a == 1 && f.b == 2 && !f.c && !f.d) ? 0 : 1; }
static int t5(void) { int a[4] = { 1, 2 };
  return (a[0] == 1 && a[1] == 2 && !a[2] && !a[3]) ? 0 : 1; }
static int t6(void) { struct scope f = { 0 };
  return (f.prev || f.vla.loc || f.vla.locorig || f.vla.num || f.cl.s ||
          f.cl.n || f.bsym || f.csym || f.lstk || f.llstk) ? 1 : 0; }
int main(void) {
    dirty(); if (t1()) return 1;
    dirty(); if (t2()) return 2;
    dirty(); if (t3()) return 3;
    dirty(); if (t4()) return 4;
    dirty(); if (t5()) return 5;
    dirty(); if (t6()) return 6;
    return 42;
}

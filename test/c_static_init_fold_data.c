/* Static initialisers a freestanding object must fold into .data (NetBSD rump
   row 4): __builtin_offsetof (also of an array member's element), __BIT-style
   guarded shifts (a constant ternary and comparisons, signed and unsigned),
   and a `__typeof__(fn) *` initialised with `&f`. Linked with
   c_static_init_fold_main.c and compared with gcc's object. */
typedef unsigned long uintmax_t;
#define BIT(n) (((uintmax_t)(n) >= 8 * sizeof(uintmax_t)) ? 0 : ((uintmax_t)1 << (uintmax_t)((n) & (8 * sizeof(uintmax_t) - 1))))
struct args { int a; void *b; long c; short d[5]; struct { char x; int y; } in; };
struct desc { int off; const char *name; long c_off; long d_off; long y_off; };
const struct desc init_d = { 1, "x", __builtin_offsetof(struct args, c),
                             __builtin_offsetof(struct args, d[3]), __builtin_offsetof(struct args, in.y) };
struct fo { long flags; int cmp[8]; };
const struct fo init_f = { .flags = BIT(0) | BIT(1) | BIT(70) | BIT(63),
  .cmp = { -1 < 0, (unsigned)-1 < 0u, -1 < 0u, 3 >= 3, 2 == 3, 2 != 3, (uintmax_t)-2 > 5, (long)-2 > 5 } };
int init_def(int a) { return a + 1; }
int init_alias(int);
__typeof__(init_alias) *init_p = &init_def;

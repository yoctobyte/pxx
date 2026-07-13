/* A multidimensional LOCAL array of POINTERS must honour its brace initializer.

   The multi-dim brace-init path was gated on `(declTk <> tyPointer) and (ordinal or
   float)`, so a pointer-element multi-dim array fell through to the "unconsumed
   initializer" balanced SKIP -- the initializer was parsed past and THROWN AWAY, and
   every element read back as nil. Silent: no error, no warning.

   1-D pointer arrays always worked, and multi-dim INT arrays always worked, so the
   hole was exactly the intersection. csmith seed 711 crashed on it (a local
   `int32_t * const *l_34[4][1][3]` whose elements it then dereferenced).

   The GLOBAL form had the same hole for a different reason: a flat pointer pre-scan
   (which knows nothing of nested braces or of the array's shape) consumed the whole
   `{...}` before the multi-dim walker could see it, then emitted nothing. It now
   declines multi-dim arrays and leaves them to the walker. */
int printf(const char *, ...);

static int gv = 5;
static int *pv = &gv;

/* the GLOBAL forms — a flat pre-scan used to eat these and store nothing */
static int  *g2[2][3]    = {{&gv, &gv, &gv}, {&gv, &gv, &gv}};
static int **g3[2][1][2] = {{{&pv, &pv}}, {{&pv, &pv}}};

int main(void)
{
    /* nested braces, flat braces, and 3-D -- all must work */
    int *b2[2][3]  = {{&gv, &gv, &gv}, {&gv, &gv, &gv}};
    int *f2[2][3]  = {&gv, &gv, &gv, &gv, &gv, &gv};
    int **p3[4][1][3] = {{{&pv, &pv, &pv}}, {{&pv, &pv, &pv}},
                         {{&pv, &pv, &pv}}, {{&pv, &pv, &pv}}};
    int *one[3]    = {&gv, &gv, &gv};      /* 1-D: was always fine, keep it honest */
    int  ints[2][3] = {{1, 2, 3}, {4, 5, 6}};  /* multi-dim int: was always fine */

    printf("braced=%d %d\n", (int)(b2[0][0] == &gv), (int)(b2[1][2] == &gv));
    printf("flat=%d %d\n",   (int)(f2[0][0] == &gv), (int)(f2[1][2] == &gv));
    printf("3d=%d %d\n",     (int)(p3[0][0][0] == &pv), (int)(p3[3][0][2] == &pv));
    printf("deref3d=%d\n",   **p3[2][0][1]);
    printf("1d=%d\n",        (int)(one[2] == &gv));
    printf("ints=%d %d\n",   ints[0][0], ints[1][2]);
    printf("global2d=%d %d\n", (int)(g2[0][0] == &gv), (int)(g2[1][2] == &gv));
    printf("global3d=%d %d\n", (int)(g3[0][0][0] == &pv), (int)(g3[1][0][1] == &pv));

    /* NOTE: partial ROWS (`{{&gv}, {&gv}}`) are still wrong -- the multi-dim brace
       pre-scan flattens nested braces and ignores row boundaries, so the elision does
       not zero-fill each row. That is PRE-EXISTING and hits multi-dim INT arrays too
       (`int q[2][3] = {{1},{2}}` gives q[0][1]=2 instead of 0), so it is filed on its
       own as bug-c-multidim-brace-elision-flattens-rows, not asserted here. */
    return 0;
}

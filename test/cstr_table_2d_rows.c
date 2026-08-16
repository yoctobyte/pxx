/* `char names[N][M] = {"ab", "cd"}` — a string table, which every C program of
   any size has. The row is not a scalar, but both initializer paths treated it
   as one: the literal was read as its ADDRESS and the low byte of that address
   was stored into the row's first character. Row 0 held one garbage byte, row 1
   held nothing, and strcmp / printf("%s") then read whatever followed — silent,
   on an everyday declaration.

   Two paths, because a global and a local reach the initializer through
   different code: the global goes through CInitWalkArray (fixed with
   CInitFillCharFlat), the local through ParseCLocalDeclAST's flattening
   pre-scan. Braced rows (`{{"ab"},{"cd"}}`) enter each one level deeper, so
   both spellings are asserted on both paths.
   bug-c-a-string-literal-row-of-a-2d-char-array-stores-its-address */
#include <stdio.h>
#include <string.h>

char g[2][8] = {"ab", "cd"};
char gb[2][8] = {{"ab"}, {"cd"}};
char g3[2][2][4] = {{"a", "b"}, {"c", "d"}};
char gfull[2][3] = {"abc", "de"};        /* row 0 has no room for the NUL */

static int fails;

static void chk(const char *what, int got, int want)
{
    if (got != want) { printf("FAIL %s: got %d want %d\n", what, got, want); fails++; }
}

int main(void)
{
    char l[2][8] = {"ab", "cd"};
    char lb[2][8] = {{"ab"}, {"cd"}};
    char l3[2][2][4] = {{"a", "b"}, {"c", "d"}};
    char lc[2][8] = {{97, 98}, {99, 100}};

    chk("g0", strcmp(g[0], "ab"), 0);
    chk("g1", strcmp(g[1], "cd"), 0);
    chk("gb0", strcmp(gb[0], "ab"), 0);
    chk("gb1", strcmp(gb[1], "cd"), 0);
    chk("g3", g3[1][0][0] * 100 + g3[0][1][0], 'c' * 100 + 'b');
    chk("gfull", gfull[0][2], 'c');
    chk("gfull-row1", strcmp(gfull[1], "de"), 0);

    chk("l0", strcmp(l[0], "ab"), 0);
    chk("l1", strcmp(l[1], "cd"), 0);
    chk("lb0", strcmp(lb[0], "ab"), 0);
    chk("lb1", strcmp(lb[1], "cd"), 0);
    chk("l3", l3[1][1][0], 'd');
    chk("lc", strcmp(lc[1], "cd"), 0);

    /* the rows are still ordinary writable arrays afterwards */
    strcpy(l[1], "zz");
    chk("after-strcpy", strcmp(l[1], "zz"), 0);
    chk("row-stride", (int)(&g[1][0] - &g[0][0]), 8);

    if (fails == 0) printf("ok\n");
    return 42 + fails;
}
